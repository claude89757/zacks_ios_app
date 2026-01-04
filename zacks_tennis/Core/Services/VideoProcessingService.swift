//
//  VideoProcessingService.swift
//  zacks_tennis
//
//  视频处理服务 - 视频导入/导出和辅助工具
//  注意：视频分析功能已迁移到 VideoProcessingEngine
//

import Foundation
import AVFoundation
import UIKit

/// 视频处理服务
@MainActor
@Observable
class VideoProcessingService {
    static let shared = VideoProcessingService()

    var isProcessing = false
    var processingProgress: Double = 0.0
    var currentOperation: String = ""

    private init() {}

    // MARK: - 视频导入

    /// 从 URL 导入视频并创建 Video 模型（旧版本，保留兼容性）
    func importVideo(from url: URL, title: String) async throws -> Video {
        let fileName = "\(UUID().uuidString).\(url.pathExtension)"
        let destinationURL = getDocumentsDirectory().appendingPathComponent(fileName)

        print("📁 复制视频到 Documents 目录")
        print("   源: \(url.path)")
        print("   目标: \(destinationURL.path)")

        // 如果目标文件已存在，先删除
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: url, to: destinationURL)

        // 验证复制成功
        guard FileManager.default.fileExists(atPath: destinationURL.path),
              FileManager.default.isReadableFile(atPath: destinationURL.path) else {
            throw VideoError.exportFailedWithReason("视频文件复制失败，无法访问目标文件")
        }

        print("   ✅ 视频文件复制成功")

        // 使用新方法读取元数据
        return try await importVideoFromExistingFile(
            at: destinationURL,
            fileName: fileName,
            title: title,
            progressHandler: nil
        )
    }

    /// 从已存在的文件导入视频（优化版本）
    /// - Parameters:
    ///   - url: 已在Documents目录的文件URL
    ///   - fileName: 文件名（用于存储）
    ///   - title: 视频标题
    ///   - progressHandler: 进度回调（0.0-1.0）
    /// - Returns: Video模型
    func importVideoFromExistingFile(
        at url: URL,
        fileName: String,
        title: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> Video {

        print("📊 读取视频元数据")
        print("   文件: \(url.path)")

        // 验证文件存在
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw VideoError.exportFailedWithReason("视频文件不存在或不可读")
        }

        // 🚀 优化：使用AVURLAsset并设置加载选项
        let options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,  // 使用快速估算
            AVURLAssetAllowsCellularAccessKey: true
        ]
        let asset = AVURLAsset(url: url, options: options)

        progressHandler?(0.1)

        // 🚀 优化：并发加载视频信息
        async let duration = asset.load(.duration)
        async let tracks = asset.load(.tracks)

        let (loadedDuration, loadedTracks) = try await (duration, tracks)

        progressHandler?(0.4)

        guard let videoTrack = loadedTracks.first(where: { $0.mediaType == .video }) else {
            throw VideoError.noVideoTrack
        }

        // 🚀 并发加载视频轨道信息
        async let naturalSize = videoTrack.load(.naturalSize)
        async let nominalFrameRate = videoTrack.load(.nominalFrameRate)

        let (loadedSize, loadedFrameRate) = try await (naturalSize, nominalFrameRate)
        let fileSize = try getFileSize(from: url)

        progressHandler?(0.7)

        print("   ✅ 元数据读取成功")
        print("      时长: \(String(format: "%.2f", loadedDuration.seconds))秒")
        print("      分辨率: \(Int(loadedSize.width))x\(Int(loadedSize.height))")
        print("      帧率: \(Int(loadedFrameRate))fps")
        print("      文件大小: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")

        progressHandler?(0.8)

        // 生成缩略图（已优化尺寸为400x400，生成很快）
        print("   🖼️  开始生成缩略图...")
        let thumbnailPath = try await generateThumbnail(from: asset, videoID: fileName)
        print("   ✅ 缩略图生成完成")

        progressHandler?(0.95)

        // 创建 Video 模型
        let video = Video(
            title: title,
            originalFilePath: fileName,
            duration: loadedDuration.seconds,
            width: Int(loadedSize.width),
            height: Int(loadedSize.height),
            fileSize: fileSize,
            framerate: loadedFrameRate
        )
        video.thumbnailPath = thumbnailPath

        progressHandler?(1.0)

        return video
    }

    // MARK: - 视频导出

    // ⚠️ 注意：视频分析功能已迁移到 VideoProcessingEngine
    // 此服务现在只负责：
    // 1. 视频导入（importVideo）
    // 2. 视频导出（exportTopHighlights, exportHighlight）
    // 3. 辅助工具方法（generateThumbnail, getFileSize等）

    /// 导出 Top N 精彩片段
    func exportTopHighlights(from video: Video, count: Int, type: String) async throws -> [ExportedFile] {
        isProcessing = true
        processingProgress = 0.0
        currentOperation = "正在导出精彩片段..."
        defer { isProcessing = false }

        let highlights = video.getTopHighlights(count: count)
        var exportedFiles: [ExportedFile] = []

        for (index, highlight) in highlights.enumerated() {
            let progress = Double(index) / Double(highlights.count)
            await updateProgress(progress, operation: "导出片段 \(index + 1)/\(highlights.count)")

            let fileName = makeExportFileName(for: video, exportName: "highlight", index: index + 1)
            let exportedFile = try await exportHighlight(
                from: video,
                highlight: highlight,
                fileName: fileName
            )
            exportedFiles.append(exportedFile)
        }

        await updateProgress(1.0, operation: "导出完成")

        return exportedFiles
    }

    /// 导出自定义精彩片段列表（合并为一个视频）
    func exportCustomHighlights(from video: Video, highlights: [VideoHighlight], exportName: String) async throws -> [ExportedFile] {
        isProcessing = true
        processingProgress = 0.0
        currentOperation = "正在合并精彩片段..."
        defer { isProcessing = false }

        // 合并所有片段为一个视频
        let mergedFile = try await exportMergedHighlights(
            from: video,
            highlights: highlights,
            exportName: exportName
        )

        await updateProgress(1.0, operation: "导出完成")

        return [mergedFile]
    }

    /// 合并多个精彩片段为一个视频
    private func exportMergedHighlights(from video: Video, highlights: [VideoHighlight], exportName: String) async throws -> ExportedFile {
        print("🎬 开始合并 \(highlights.count) 个精彩片段")

        guard !video.originalFilePath.isEmpty else {
            throw VideoError.exportFailedWithReason("视频文件路径为空")
        }

        let videoURL = getVideoURL(for: video)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw VideoError.exportFailedWithReason("源视频文件不存在")
        }

        let asset = AVAsset(url: videoURL)

        // 创建组合对象
        let composition = AVMutableComposition()

        // 添加视频和音频轨道
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.noVideoTrack
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoError.exportFailedWithReason("无法创建视频轨道")
        }

        // 🔧 修复：为每个音频轨道创建对应的组合轨道（支持多音频轨道）
        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        for _ in audioTracks {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                compositionAudioTracks.append(compositionAudioTrack)
            }
        }

        // 按时间顺序添加每个片段
        var currentTime = CMTime.zero

        for (index, highlight) in highlights.enumerated() {
            let progress = Double(index) / Double(highlights.count)
            await updateProgress(progress, operation: "合并片段 \(index + 1)/\(highlights.count)")

            let startTime = CMTime(seconds: highlight.startTime, preferredTimescale: 600)
            let endTime = CMTime(seconds: highlight.endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, end: endTime)

            do {
                // 插入视频片段
                try compositionVideoTrack.insertTimeRange(
                    timeRange,
                    of: videoTrack,
                    at: currentTime
                )

                // 🔧 修复：插入所有音频轨道（保留多轨道音频）
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

            } catch {
                print("⚠️ 片段 \(index + 1) 插入失败: \(error.localizedDescription)")
                throw VideoError.exportFailedWithReason("合并片段失败: \(error.localizedDescription)")
            }
        }

        // 生成导出文件名
        let fileName = "\(exportName)_merged_\(Date().timeIntervalSince1970).mp4"
        let outputURL = getDocumentsDirectory().appendingPathComponent(fileName)

        // 如果文件已存在，删除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        await updateProgress(0.9, operation: "正在编码合并后的视频...")

        // 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoError.exportFailedWithReason("无法创建导出会话")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        // 执行导出
        await exportSession.export()

        // 检查导出状态
        switch exportSession.status {
        case .completed:
            // 🔧 添加：导出文件完整性验证
            try await verifyExportedFile(at: outputURL)

            let fileSize = try getFileSize(from: outputURL)
            print("✅ 合并完成: \(fileName)")
            print("   文件大小: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            print("   总时长: \(composition.duration.seconds)秒")

            return ExportedFile(
                id: UUID(),
                filePath: fileName,
                exportedAt: Date(),
                type: exportName,
                fileSize: fileSize
            )

        case .failed:
            // 🔧 添加：取消时清理不完整文件
            try? FileManager.default.removeItem(at: outputURL)
            let errorMsg = exportSession.error?.localizedDescription ?? "未知错误"
            print("❌ 导出失败: \(errorMsg)")
            throw VideoError.exportFailedWithReason("视频合并失败: \(errorMsg)")

        case .cancelled:
            // 🔧 添加：取消时清理不完整文件
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoError.exportFailedWithReason("导出已取消")

        default:
            throw VideoError.exportFailed
        }
    }

    /// 验证导出文件的完整性
    private func verifyExportedFile(at url: URL) async throws {
        // 1. 验证文件存在
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoError.exportFailedWithReason("导出文件不存在")
        }

        // 2. 验证文件大小 > 0
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw VideoError.exportFailedWithReason("导出文件为空")
        }

        // 3. 验证文件可读
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw VideoError.exportFailedWithReason("导出文件不可读")
        }

        // 4. 验证视频可播放
        let asset = AVAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            try? FileManager.default.removeItem(at: url)
            throw VideoError.exportFailedWithReason("导出的视频文件损坏或不可播放")
        }

        print("✅ 文件验证通过: \(url.lastPathComponent)")
    }

    /// 导出带网球标注的精彩片段（调试用）
    func exportWithBallAnnotations(from video: Video, highlights: [VideoHighlight], exportName: String) async throws -> [ExportedFile] {
        isProcessing = true
        processingProgress = 0.0
        currentOperation = "正在导出带标注的视频..."
        defer { isProcessing = false }

        var exportedFiles: [ExportedFile] = []

        for (index, highlight) in highlights.enumerated() {
            let progress = Double(index) / Double(highlights.count)
            await updateProgress(progress, operation: "导出带标注片段 \(index + 1)/\(highlights.count)")

            let fileName = makeExportFileName(for: video, exportName: exportName, index: index + 1)
            let exportedFile = try await exportHighlightWithAnnotations(
                from: video,
                highlight: highlight,
                fileName: fileName
            )
            exportedFiles.append(exportedFile)
        }

        await updateProgress(1.0, operation: "导出完成")

        return exportedFiles
    }

    /// 导出单个精彩片段
    private func exportHighlight(from video: Video, highlight: VideoHighlight, fileName: String) async throws -> ExportedFile {
        print("🎬 开始导出: \(fileName)")
        
        // 验证0: 检查视频路径是否为空
        guard !video.originalFilePath.isEmpty else {
            print("   ❌ 错误: 视频文件路径为空")
            throw VideoError.exportFailedWithReason("视频文件路径为空，请重新导入视频")
        }
        
        let videoURL = getVideoURL(for: video)
        print("   源视频路径: \(video.originalFilePath)")
        print("   完整URL: \(videoURL.path)")
        print("   时间范围: \(highlight.startTime)s - \(highlight.endTime)s")

        // 验证1: 检查源视频文件是否存在
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("   ❌ 错误: 源视频文件不存在")
            print("   检查路径: \(videoURL.path)")
            
            // 列出Documents目录内容以便调试
            let documentsURL = getDocumentsDirectory()
            if let files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
                print("   Documents目录中的视频文件:")
                for file in files.filter({ $0.pathExtension == "mp4" || $0.pathExtension == "mov" }) {
                    print("     - \(file.lastPathComponent)")
                }
            }
            
            throw VideoError.exportFailedWithReason("源视频文件不存在: \(videoURL.lastPathComponent)。文件可能已被删除，请重新导入视频")
        }
        
        // 验证1.5: 检查文件是否可读
        guard FileManager.default.isReadableFile(atPath: videoURL.path) else {
            print("   ❌ 错误: 源视频文件不可读")
            throw VideoError.exportFailedWithReason("源视频文件不可读，请检查文件权限")
        }
        
        print("   ✅ 源视频文件验证通过")

        // 验证2: 检查时间范围是否有效
        guard highlight.startTime >= 0 && highlight.endTime > highlight.startTime else {
            print("   ❌ 错误: 时间范围无效")
            throw VideoError.exportFailedWithReason("时间范围无效 (\(highlight.startTime)s - \(highlight.endTime)s)")
        }

        let asset = AVAsset(url: videoURL)

        // 验证3: 检查AVAsset是否可用
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                print("   ❌ 错误: 视频文件不可播放")
                throw VideoError.exportFailedWithReason("视频文件损坏或格式不支持")
            }
        } catch {
            print("   ❌ 错误: 无法加载视频资源: \(error.localizedDescription)")
            throw VideoError.exportFailedWithReason("无法加载视频资源: \(error.localizedDescription)")
        }

        // 验证4: 检查时间范围是否在视频时长内
        let duration = try await asset.load(.duration)
        guard highlight.endTime <= duration.seconds else {
            print("   ❌ 错误: 结束时间超出视频时长")
            throw VideoError.exportFailedWithReason("结束时间(\(highlight.endTime)s)超出视频时长(\(duration.seconds)s)")
        }

        // 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("   ❌ 错误: 无法创建导出会话")
            throw VideoError.exportFailedWithReason("无法创建导出会话。可能原因: 视频格式不支持、编解码器不兼容或系统资源不足")
        }

        // 设置时间范围
        let startTime = CMTime(seconds: highlight.startTime, preferredTimescale: 600)
        let endTime = CMTime(seconds: highlight.endTime, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)

        // 设置输出路径
        let outputURL = getDocumentsDirectory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        print("   输出路径: \(outputURL.path)")

        // 执行导出并监控进度
        let exportTask = Task {
            while exportSession.status == .exporting {
                let progress = Double(exportSession.progress)
                await updateProgress(progress, operation: "导出片段... \(Int(progress * 100))%")
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }
        }

        await exportSession.export()
        exportTask.cancel()

        // 检查导出状态并捕获详细错误
        guard exportSession.status == .completed else {
            let statusDescription: String
            switch exportSession.status {
            case .failed:
                statusDescription = "失败"
            case .cancelled:
                statusDescription = "已取消"
            case .unknown:
                statusDescription = "未知状态"
            case .waiting:
                statusDescription = "等待中"
            case .exporting:
                statusDescription = "导出中"
            case .completed:
                statusDescription = "已完成"
            @unknown default:
                statusDescription = "未知(\(exportSession.status.rawValue))"
            }

            // 🔧 添加：导出失败时清理不完整文件
            try? FileManager.default.removeItem(at: outputURL)

            if let error = exportSession.error {
                print("   ❌ 导出失败: \(statusDescription)")
                print("   错误详情: \(error.localizedDescription)")
                throw VideoError.exportFailedWithReason("\(statusDescription) - \(error.localizedDescription)")
            } else {
                print("   ❌ 导出失败: \(statusDescription)")
                throw VideoError.exportFailedWithReason("导出状态: \(statusDescription)")
            }
        }

        // 🔧 添加：导出文件完整性验证
        try await verifyExportedFile(at: outputURL)

        let fileSize = try getFileSize(from: outputURL)
        print("   ✅ 导出成功! 文件大小: \(fileSize) bytes")

        return ExportedFile(
            id: UUID(),
            filePath: fileName,
            exportedAt: Date(),
            type: "highlight",
            fileSize: fileSize
        )
    }

    /// 导出带网球标注的单个精彩片段
    private func exportHighlightWithAnnotations(from video: Video, highlight: VideoHighlight, fileName: String) async throws -> ExportedFile {
        print("🎬 开始导出带标注的视频: \(fileName)")

        // 基本验证（复用exportHighlight的逻辑）
        guard !video.originalFilePath.isEmpty else {
            throw VideoError.exportFailedWithReason("视频文件路径为空")
        }

        let videoURL = getVideoURL(for: video)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw VideoError.exportFailedWithReason("源视频文件不存在")
        }

        let asset = AVAsset(url: videoURL)

        // 如果highlight没有ballTrajectoryData，直接调用普通导出
        guard let ballTrajectory = highlight.ballTrajectoryData, !ballTrajectory.trajectoryPoints.isEmpty else {
            print("   ⚠️ 该回合没有网球轨迹数据，使用普通导出")
            return try await exportHighlight(from: video, highlight: highlight, fileName: fileName)
        }

        print("   ✅ 找到 \(ballTrajectory.trajectoryPoints.count) 个网球轨迹点")

        // 创建输出路径
        let outputURL = getDocumentsDirectory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // 使用AVAssetReader和AVAssetWriter进行逐帧处理
        try await exportVideoWithAnnotations(
            asset: asset,
            outputURL: outputURL,
            timeRange: CMTimeRange(
                start: CMTime(seconds: highlight.startTime, preferredTimescale: 600),
                end: CMTime(seconds: highlight.endTime, preferredTimescale: 600)
            ),
            ballTrajectory: ballTrajectory,
            highlightStartTime: highlight.startTime
        )

        let fileSize = try getFileSize(from: outputURL)
        print("   ✅ 带标注视频导出成功! 文件大小: \(fileSize) bytes")

        return ExportedFile(
            id: UUID(),
            filePath: fileName,
            exportedAt: Date(),
            type: "annotated-highlight",
            fileSize: fileSize
        )
    }

    /// 使用逐帧处理导出带标注的视频
    private nonisolated func exportVideoWithAnnotations(
        asset: AVAsset,
        outputURL: URL,
        timeRange: CMTimeRange,
        ballTrajectory: BallTrajectoryData,
        highlightStartTime: Double
    ) async throws {

        // 加载视频轨道
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoError.exportFailedWithReason("找不到视频轨道")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)

        // 创建AssetReader
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)

        // 创建AssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let writerInputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: naturalSize.width,
            AVVideoHeightKey: naturalSize.height
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerInputSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: naturalSize.width,
                kCVPixelBufferHeightKey as String: naturalSize.height
            ]
        )

        writer.add(writerInput)

        // 创建网球可视化引擎
        let visualizer = BallVisualizationEngine()

        // 开始读写
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: timeRange.start)

        var frameIndex = 0
        let trajectoryPoints = ballTrajectory.trajectoryPoints

        // 逐帧处理（需要使用同步方式）
        await withTaskGroup(of: Void.self) { group in
            while reader.status == .reading {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    break
                }

                let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                CMSampleBufferInvalidate(sampleBuffer)

                guard let imageBuffer = imageBuffer else {
                    continue
                }

                let timestamp = CMTimeGetSeconds(presentationTime) - CMTimeGetSeconds(timeRange.start)

                // 找到当前时间戳对应的网球检测数据
                let relevantPoints = trajectoryPoints.filter { point in
                    abs(point.timestamp - (timestamp + highlightStartTime)) < 0.1
                }

                // 构造BallAnalysisResult（用于可视化）
                let detections = relevantPoints.map { point in
                    BallDetection(
                        boundingBox: CGRect(
                            x: point.position.x - 0.02,
                            y: point.position.y - 0.02,
                            width: 0.04,
                            height: 0.04
                        ),
                        center: point.position.cgPoint,
                        velocity: point.velocity.cgVector,
                        confidence: point.confidence,
                        timestamp: point.timestamp,
                        trajectory: nil
                    )
                }

                let ballResult = BallAnalysisResult(timestamp: timestamp, detections: detections)

                // 使用可视化引擎添加标注（同步等待）
                if let annotatedBuffer = await visualizer.visualize(
                    pixelBuffer: imageBuffer,
                    result: ballResult,
                    audioEvents: nil
                ) {
                    // 等待writer准备好
                    while !writerInput.isReadyForMoreMediaData {
                        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01秒
                    }

                    adaptor.append(annotatedBuffer, withPresentationTime: presentationTime)
                }

                frameIndex += 1
            }
        }

        // 完成写入
        writerInput.markAsFinished()
        await writer.finishWriting()

        if reader.status == .failed, let error = reader.error {
            throw VideoError.exportFailedWithReason("读取视频失败: \(error.localizedDescription)")
        }

        if writer.status == .failed, let error = writer.error {
            throw VideoError.exportFailedWithReason("写入视频失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 辅助方法

    private func generateThumbnail(from asset: AVAsset, videoID: String) async throws -> String {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        // 🚀 优化：限制缩略图最大尺寸，减少解码时间和内存占用
        imageGenerator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: time).image

        let image = UIImage(cgImage: cgImage)
        let thumbnailFileName = "\(videoID)_thumbnail.jpg"
        let thumbnailPath = getDocumentsDirectory().appendingPathComponent(thumbnailFileName)

        if let data = image.jpegData(compressionQuality: 0.7) {
            try data.write(to: thumbnailPath)
        }

        return thumbnailFileName
    }

    private func getVideoURL(for video: Video) -> URL {
        getDocumentsDirectory().appendingPathComponent(video.originalFilePath)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getFileSize(from url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    private func updateProgress(_ progress: Double, operation: String) async {
        await MainActor.run {
            self.processingProgress = progress
            self.currentOperation = operation
        }
    }

    private func makeExportFileName(for video: Video, exportName: String, index: Int) -> String {
        let titleComponent = video.title.sanitizedFileComponent(fallback: "video")
        let exportComponent = exportName.sanitizedFileComponent(fallback: "export")
        return "\(titleComponent)_\(exportComponent)_\(index).mp4"
    }
}

// MARK: - 错误类型
enum VideoError: LocalizedError {
    case noVideoTrack
    case exportFailed
    case exportFailedWithReason(String)
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "无法找到视频轨道"
        case .exportFailed:
            return "视频导出失败"
        case .exportFailedWithReason(let reason):
            return "视频导出失败: \(reason)"
        case .analysisFailed:
            return "视频分析失败"
        }
    }
}
