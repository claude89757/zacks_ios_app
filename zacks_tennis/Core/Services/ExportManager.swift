//
//  ExportManager.swift
//  zacks_tennis
//
//  核心导出管理器 - 支持后台导出、取消、超时
//

import Foundation
import AVFoundation
import Photos

/// 导出管理器 - 单例模式，支持后台导出
@MainActor
@Observable
final class ExportManager {

    // MARK: - Singleton

    static let shared = ExportManager()

    // MARK: - Published State

    /// 当前导出状态
    private(set) var state: ExportState = .idle

    /// 当前操作描述
    private(set) var currentOperation: String = ""

    /// 当前正在导出的索引
    private(set) var currentIndex: Int = 0

    /// 总数
    private(set) var totalCount: Int = 0

    // MARK: - Private Properties

    private var exportTask: Task<[ExportedFile], Error>?
    private var currentExportSession: AVAssetExportSession?
    private var progressObservation: NSKeyValueObservation?
    private var timeoutTask: Task<Void, Never>?

    private let fileManager = FileManager.default
    private let documentsDirectory: URL

    // MARK: - Initialization

    private init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Public API

    /// 开始导出任务（支持后台运行）
    /// - Parameter config: 导出配置
    /// - Returns: 导出的文件列表
    func startExport(config: ExportTaskConfiguration) async throws -> [ExportedFile] {
        // 确保没有正在进行的导出
        guard !state.isActive else {
            throw ExportError.unknownError(message: "当前有导出任务进行中")
        }

        // 重置状态
        state = .preparing
        currentOperation = "正在准备..."
        currentIndex = 0
        totalCount = config.highlights.count

        // 创建导出任务
        exportTask = Task {
            try await performExport(config: config)
        }

        do {
            let result = try await exportTask!.value
            return result
        } catch {
            if Task.isCancelled || error is CancellationError {
                state = .cancelled
                throw ExportError.cancelled
            }
            if let exportError = error as? ExportError {
                state = .failed(error: exportError)
                throw exportError
            }
            let exportError = ExportError.unknownError(message: error.localizedDescription)
            state = .failed(error: exportError)
            throw exportError
        }
    }

    /// 取消导出
    func cancelExport() {
        print("📤 ExportManager: 取消导出")

        // 1. 取消当前 AVAssetExportSession
        currentExportSession?.cancelExport()
        currentExportSession = nil

        // 2. 取消超时任务
        timeoutTask?.cancel()
        timeoutTask = nil

        // 3. 停止进度观察
        progressObservation?.invalidate()
        progressObservation = nil

        // 4. 取消整体 Task
        exportTask?.cancel()
        exportTask = nil

        // 5. 清理临时文件
        cleanupTemporaryFiles()

        // 6. 更新状态
        state = .cancelled
        currentOperation = "已取消"
    }

    /// 重置状态（用于开始新导出前）
    func reset() {
        guard !state.isActive else { return }
        state = .idle
        currentOperation = ""
        currentIndex = 0
        totalCount = 0
    }

    // MARK: - Private Implementation

    private func performExport(config: ExportTaskConfiguration) async throws -> [ExportedFile] {
        // 1. 验证源文件
        try await validateSourceFile(config.videoFilePath)

        // 2. 检查存储空间
        let estimatedSize = estimateExportSize(config)
        try checkStorageSpace(estimatedSize: estimatedSize)

        var exportedFiles: [ExportedFile] = []

        if config.mergeIntoSingle {
            // 合并导出
            currentOperation = "正在合并 \(config.highlights.count) 个片段..."
            let file = try await exportMergedVideo(config: config)
            exportedFiles.append(file)
        } else {
            // 逐个导出
            for (index, highlight) in config.highlights.enumerated() {
                try Task.checkCancellation()

                currentIndex = index
                let segmentProgress = Double(index) / Double(totalCount)
                state = .exporting(progress: segmentProgress)
                currentOperation = "导出片段 \(index + 1)/\(totalCount)"

                let file = try await exportSingleHighlight(
                    config: config,
                    highlight: highlight,
                    index: index,
                    timeout: config.timeoutSeconds / Double(max(1, totalCount))
                )
                exportedFiles.append(file)
            }
        }

        // 3. 验证导出文件
        currentOperation = "验证导出文件..."
        try await verifyExportedFiles(exportedFiles)

        // 4. 保存到相册
        state = .savingToPhotos
        currentOperation = "保存到相册..."
        let savedCount = await saveToPhotoLibrary(files: exportedFiles)

        // 5. 更新状态
        state = .completed(count: savedCount)
        currentOperation = "导出完成"

        return exportedFiles
    }

    // MARK: - Single Highlight Export

    private func exportSingleHighlight(
        config: ExportTaskConfiguration,
        highlight: HighlightInfo,
        index: Int,
        timeout: TimeInterval
    ) async throws -> ExportedFile {
        let videoURL = documentsDirectory.appendingPathComponent(config.videoFilePath)
        let asset = AVAsset(url: videoURL)

        // 验证时间范围
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard highlight.startTime >= 0,
              highlight.endTime <= durationSeconds,
              highlight.startTime < highlight.endTime else {
            throw ExportError.invalidTimeRange(start: highlight.startTime, end: highlight.endTime)
        }

        // 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: config.quality.avPreset
        ) else {
            throw ExportError.exportSessionCreationFailed
        }

        currentExportSession = exportSession

        // 配置时间范围
        let startTime = CMTime(seconds: highlight.startTime, preferredTimescale: 600)
        let endTime = CMTime(seconds: highlight.endTime, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)

        // 配置输出
        let fileName = makeExportFileName(config: config, index: index)
        let outputURL = documentsDirectory.appendingPathComponent(fileName)

        // 清理已存在的文件
        try? fileManager.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // 使用 KVO 监听进度（替代轮询）
        let baseProgress = Double(index) / Double(max(1, totalCount))
        setupProgressObservation(for: exportSession, baseProgress: baseProgress)

        // 启动超时监控
        startTimeoutMonitor(timeout: timeout)

        // 执行导出
        await exportSession.export()

        // 清理观察者
        progressObservation?.invalidate()
        progressObservation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        currentExportSession = nil

        // 检查结果
        return try handleExportResult(
            session: exportSession,
            outputURL: outputURL,
            fileName: fileName,
            type: config.exportNamePrefix
        )
    }

    // MARK: - Merged Export

    private func exportMergedVideo(config: ExportTaskConfiguration) async throws -> ExportedFile {
        state = .encoding(progress: 0.0)

        let videoURL = documentsDirectory.appendingPathComponent(config.videoFilePath)
        let asset = AVAsset(url: videoURL)

        // 创建组合对象
        let composition = AVMutableComposition()

        // 加载所有轨道
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        // 添加组合视频轨道
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.unknownError(message: "无法创建视频轨道")
        }

        // 为每个音频轨道创建对应的组合轨道（支持多音频轨道）
        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        for _ in audioTracks {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                compositionAudioTracks.append(compositionAudioTrack)
            }
        }

        var currentTime = CMTime.zero

        for (index, highlight) in config.highlights.enumerated() {
            try Task.checkCancellation()

            let progress = Double(index) / Double(config.highlights.count)
            state = .encoding(progress: progress)
            currentOperation = "合并片段 \(index + 1)/\(config.highlights.count)"

            let startTime = CMTime(seconds: highlight.startTime, preferredTimescale: 600)
            let endTime = CMTime(seconds: highlight.endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, end: endTime)

            // 插入视频
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: currentTime)

            // 插入所有音频轨道（保留多轨道音频）
            for (trackIndex, audioTrack) in audioTracks.enumerated() {
                if trackIndex < compositionAudioTracks.count {
                    try compositionAudioTracks[trackIndex].insertTimeRange(
                        timeRange,
                        of: audioTrack,
                        at: currentTime
                    )
                }
            }

            currentTime = CMTimeAdd(currentTime, timeRange.duration)
        }

        // 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: config.quality.avPreset
        ) else {
            throw ExportError.exportSessionCreationFailed
        }

        currentExportSession = exportSession

        let fileName = "\(config.exportNamePrefix)_merged_\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = documentsDirectory.appendingPathComponent(fileName)

        try? fileManager.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // 进度观察
        setupProgressObservation(for: exportSession, baseProgress: 0.0)
        startTimeoutMonitor(timeout: config.timeoutSeconds)

        // 执行导出
        state = .exporting(progress: 0.5)
        currentOperation = "正在编码..."
        await exportSession.export()

        // 清理
        progressObservation?.invalidate()
        progressObservation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        currentExportSession = nil

        return try handleExportResult(
            session: exportSession,
            outputURL: outputURL,
            fileName: fileName,
            type: config.exportNamePrefix
        )
    }

    // MARK: - Export Result Handling

    private func handleExportResult(
        session: AVAssetExportSession,
        outputURL: URL,
        fileName: String,
        type: String
    ) throws -> ExportedFile {
        switch session.status {
        case .completed:
            let fileSize = try getFileSize(at: outputURL)
            print("✅ 导出完成: \(fileName), 大小: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")

            return ExportedFile(
                id: UUID(),
                filePath: fileName,
                exportedAt: Date(),
                type: type,
                fileSize: fileSize
            )

        case .cancelled:
            // 清理不完整文件
            try? fileManager.removeItem(at: outputURL)
            throw ExportError.cancelled

        case .failed:
            // 清理不完整文件
            try? fileManager.removeItem(at: outputURL)

            let reason = session.error?.localizedDescription ?? "未知错误"
            throw ExportError.exportSessionFailed(reason: reason)

        default:
            throw ExportError.unknownError(message: "未知导出状态: \(session.status.rawValue)")
        }
    }

    // MARK: - Progress Observation (KVO 替代轮询)

    private func setupProgressObservation(for session: AVAssetExportSession, baseProgress: Double) {
        progressObservation = session.observe(\.progress, options: [.new]) { [weak self] session, _ in
            guard let self = self else { return }

            Task { @MainActor in
                let segmentProgress = Double(session.progress)
                let overallProgress: Double

                if self.totalCount <= 1 {
                    overallProgress = segmentProgress
                } else {
                    overallProgress = baseProgress + segmentProgress / Double(self.totalCount)
                }

                // 只在导出状态时更新
                if case .exporting = self.state {
                    self.state = .exporting(progress: overallProgress)
                } else if case .encoding = self.state {
                    // 合并导出时保持编码状态
                    self.state = .encoding(progress: overallProgress)
                }
            }
        }
    }

    // MARK: - Timeout Monitor

    private func startTimeoutMonitor(timeout: TimeInterval) {
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                guard let self = self, !Task.isCancelled else { return }

                await MainActor.run {
                    print("⚠️ 导出超时")
                    self.currentExportSession?.cancelExport()
                    self.state = .failed(error: .timeout)
                }
            } catch {
                // Task 被取消，正常情况
            }
        }
    }

    // MARK: - Validation

    private func validateSourceFile(_ filePath: String) async throws {
        let videoURL = documentsDirectory.appendingPathComponent(filePath)

        guard fileManager.fileExists(atPath: videoURL.path) else {
            throw ExportError.sourceFileNotFound(path: filePath)
        }

        guard fileManager.isReadableFile(atPath: videoURL.path) else {
            throw ExportError.sourceFileNotFound(path: filePath)
        }

        // 验证视频可播放
        let asset = AVAsset(url: videoURL)
        let isPlayable = try await asset.load(.isPlayable)

        guard isPlayable else {
            throw ExportError.unknownError(message: "源视频不可播放")
        }
    }

    private func checkStorageSpace(estimatedSize: Int64) throws {
        do {
            let attributes = try fileManager.attributesOfFileSystem(
                forPath: documentsDirectory.path
            )
            let freeSpace = attributes[.systemFreeSize] as? Int64 ?? 0

            // 预留 20% 余量
            let requiredSpace = Int64(Double(estimatedSize) * 1.2)

            if freeSpace < requiredSpace {
                print("⚠️ 存储空间不足: 需要 \(requiredSpace), 可用 \(freeSpace)")
                throw ExportError.insufficientStorage
            }
        } catch let error as ExportError {
            throw error
        } catch {
            // 如果无法检查空间，继续尝试
            print("⚠️ 无法检查存储空间: \(error)")
        }
    }

    private func verifyExportedFiles(_ files: [ExportedFile]) async throws {
        for file in files {
            let fileURL = documentsDirectory.appendingPathComponent(file.filePath)

            // 验证文件存在
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw ExportError.fileVerificationFailed
            }

            // 验证文件大小 > 0
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = attributes[.size] as? Int64 ?? 0
            guard size > 0 else {
                throw ExportError.fileVerificationFailed
            }

            // 验证视频可播放
            let asset = AVAsset(url: fileURL)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw ExportError.fileVerificationFailed
            }
        }
    }

    // MARK: - Photo Library

    private func saveToPhotoLibrary(files: [ExportedFile]) async -> Int {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        if status == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                print("⚠️ 相册权限被拒绝")
                return 0
            }
        } else if status != .authorized && status != .limited {
            print("⚠️ 相册权限不足: \(status.rawValue)")
            return 0
        }

        var successCount = 0

        for file in files {
            let fileURL = documentsDirectory.appendingPathComponent(file.filePath)

            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("⚠️ 文件不存在，跳过保存: \(file.filePath)")
                continue
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
                successCount += 1
                print("✅ 已保存到相册: \(file.filePath)")
            } catch {
                print("❌ 保存到相册失败: \(file.filePath) - \(error.localizedDescription)")
            }
        }

        return successCount
    }

    // MARK: - Cleanup

    private func cleanupTemporaryFiles() {
        // 清理所有以 "export_temp_" 开头的临时文件
        if let files = try? fileManager.contentsOfDirectory(atPath: documentsDirectory.path) {
            for file in files where file.hasPrefix("export_temp_") {
                let fileURL = documentsDirectory.appendingPathComponent(file)
                try? fileManager.removeItem(at: fileURL)
                print("🗑 清理临时文件: \(file)")
            }
        }
    }

    // MARK: - Helpers

    private func estimateExportSize(_ config: ExportTaskConfiguration) -> Int64 {
        let totalDuration = config.highlights.reduce(0) { $0 + $1.duration }
        let bytesPerSecond = config.quality.estimatedBitrate
        return Int64(totalDuration * Double(bytesPerSecond))
    }

    private func makeExportFileName(config: ExportTaskConfiguration, index: Int) -> String {
        let baseName = config.videoTitle.sanitizedFileName
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(config.exportNamePrefix)_\(baseName)_\(index + 1)_\(timestamp).mp4"
    }

    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}

// MARK: - String Extension

private extension String {
    /// 清理文件名中的非法字符
    var sanitizedFileName: String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        var result = self.components(separatedBy: invalidCharacters).joined(separator: "_")
        // 限制长度
        if result.count > 50 {
            result = String(result.prefix(50))
        }
        // 如果为空，使用默认值
        if result.trimmingCharacters(in: .whitespaces).isEmpty {
            result = "video"
        }
        return result
    }
}
