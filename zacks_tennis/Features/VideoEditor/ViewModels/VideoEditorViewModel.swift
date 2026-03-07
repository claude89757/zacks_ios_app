//
//  VideoEditorViewModel.swift
//  zacks_tennis
//
//  AI 视频剪辑 ViewModel - 管理视频列表、分析和导出逻辑
//

import Foundation
import SwiftData
import PhotosUI
import Photos
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
class VideoEditorViewModel {
    // MARK: - Properties

    var videos: [Video] = []
    var selectedVideo: Video?
    var isImporting: Bool = false
    var isAnalyzing: Bool = false
    var isExporting: Bool = false
    var processingProgress: Double = 0.0
    var currentOperation: String = ""
    var errorMessage: String?
    var showError: Bool = false
    var exportedFileCount: Int = 0  // 成功导出并保存到相册的文件数量

    // MARK: - Computed Properties

    /// 是否有任何正在进行的任务（导入、分析、导出）
    var isBusy: Bool {
        return isImporting || isAnalyzing || isExporting
    }

    /// 是否可以开始新任务
    var canStartNewTask: Bool {
        return !isBusy
    }

    /// 获取忙碌状态提示信息
    var busyStatusMessage: String? {
        if isImporting {
            return "正在导入视频，请稍候..."
        } else if isAnalyzing {
            return "正在分析视频，请稍候..."
        } else if isExporting {
            return "正在导出视频，请稍候..."
        }
        return nil
    }

    // MARK: - Dependencies

    private let processingEngine = VideoProcessingEngine()
    private var modelContext: ModelContext?

    // 分析任务管理（用于取消）
    private var analysisTaskMap: [UUID: Task<Void?, Never>] = [:]

    // 🔥 性能优化：批量更新Rally检测结果
    private var rallyBatchCounter: Int = 0
    private var lastRallyUpdateTime: Date = Date()

    // MARK: - Initialization

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadVideos()
    }

    // MARK: - Data Loading

    /// 加载所有视频
    func loadVideos() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<Video>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            videos = try context.fetch(descriptor)
        } catch {
            handleError(error)
        }
    }

    // MARK: - Video Import

    /// 从照片库导入视频（带详细进度）
    func importVideo(from photoItem: PhotosPickerItem) async {
        // 🔥 并发控制：如果有任务在进行，则拒绝新导入
        guard canStartNewTask else {
            errorMessage = busyStatusMessage ?? "当前有任务正在进行，请稍候"
            showError = true
            return
        }

        // 🔥 设置全局导入标志（控制并发和UI状态）
        isImporting = true
        defer { isImporting = false }

        // 🔥 创建占位视频对象，立即插入数据库（这样列表中立即显示）
        let title = "网球视频 \(Date().formatted(date: .numeric, time: .omitted))"
        let placeholderVideo = Video(
            title: title,
            originalFilePath: "",  // 临时占位
            duration: 0.0,
            width: 0,
            height: 0,
            fileSize: 0
        )

        // 设置为导入中状态
        placeholderVideo.startImport()

        // 立即插入数据库，使其出现在列表中
        modelContext?.insert(placeholderVideo)
        try? modelContext?.save()
        loadVideos()

        do {
            // 🔥 阶段1: 获取视频文件URL（0-10%）
            placeholderVideo.updateImportProgress(0.05, stage: "正在从照片库加载视频...")
            try? modelContext?.save()

            // 使用自定义的 MovieFile Transferable 来获取文件 URL（不加载到内存）
            guard let movieFile = try await photoItem.loadTransferable(type: MovieFile.self) else {
                // 导入失败，删除占位视频
                modelContext?.delete(placeholderVideo)
                try? modelContext?.save()
                loadVideos()
                throw VideoError.exportFailed
            }

            placeholderVideo.updateImportProgress(0.1, stage: "视频接收成功，开始复制到本地...")
            try? modelContext?.save()

            // 🔥 阶段2: 复制文件到Documents目录（10-50%，带实时进度）
            let fileName = "\(UUID().uuidString).\(movieFile.url.pathExtension)"
            let destinationURL = getDocumentsDirectory().appendingPathComponent(fileName)

            print("📁 开始复制视频到 Documents 目录")
            print("   源: \(movieFile.url.path)")
            print("   目标: \(destinationURL.path)")

            let copier = AsyncFileCopier()
            let finalURL = try await copier.copyFile(
                from: movieFile.url,
                to: destinationURL
            ) { copyProgress in
                // 将文件复制进度映射到10%-50%
                let overallProgress = 0.1 + (copyProgress * 0.4)
                placeholderVideo.updateImportProgress(
                    overallProgress,
                    stage: String(format: "正在复制视频文件... %.0f%%", copyProgress * 100)
                )
                try? self.modelContext?.save()
            }

            placeholderVideo.updateImportProgress(0.5, stage: "视频复制完成，正在读取元数据...")
            try? modelContext?.save()

            // 🔥 阶段3: 读取视频元数据（50-70%，不再复制文件）
            let importedVideo = try await VideoProcessingService.shared.importVideoFromExistingFile(
                at: finalURL,
                fileName: fileName,
                title: title,
                progressHandler: { metadataProgress in
                    // 将元数据加载进度映射到50%-70%
                    let overallProgress = 0.5 + (metadataProgress * 0.2)
                    placeholderVideo.updateImportProgress(
                        overallProgress,
                        stage: "正在读取视频信息..."
                    )
                    try? self.modelContext?.save()
                }
            )

            placeholderVideo.updateImportProgress(0.7, stage: "正在保存到数据库...")
            try? modelContext?.save()

            // 🔥 阶段4: 更新占位视频的实际数据（70-100%）
            placeholderVideo.originalFilePath = importedVideo.originalFilePath
            placeholderVideo.thumbnailPath = importedVideo.thumbnailPath
            placeholderVideo.duration = importedVideo.duration
            placeholderVideo.width = importedVideo.width
            placeholderVideo.height = importedVideo.height
            placeholderVideo.fileSize = importedVideo.fileSize

            // 完成导入，准备分析
            placeholderVideo.completeImport()

            try? modelContext?.save()
            loadVideos()

            print("✅ 视频导入完成: \(title)")

            // 🔥 后台自动分析（不阻塞 UI）
            startBackgroundAnalysis(for: placeholderVideo)

        } catch {
            // 导入失败，标记错误状态
            placeholderVideo.failImport(error: error.localizedDescription)
            try? modelContext?.save()
            loadVideos()
            handleError(error)
        }
    }

    /// 获取Documents目录
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Video Analysis

    /// 后台自动分析（不阻塞 UI）
    func startBackgroundAnalysis(for video: Video) {
        // 如果已经在分析或已完成，则跳过
        guard video.analysisStatus == "等待分析" else { return }

        // 🔥 性能优化：使用更低优先级，避免阻塞UI响应
        let task = Task.detached(priority: .utility) { [weak self] in
            await self?.analyzeVideoInBackground(video)
        }

        // 保存任务引用以便取消
        analysisTaskMap[video.id] = task
    }

    /// 后台分析视频（内部方法）
    private func analyzeVideoInBackground(_ video: Video) async {
        // 切换到主线程更新状态
        await MainActor.run {
            video.startAnalysis()
            isAnalyzing = true
            // 🔥 重置批量更新计数器
            self.rallyBatchCounter = 0
            self.lastRallyUpdateTime = Date()
        }

        // 设置进度回调（已在 Engine 中切换到主线程，无需再包装）
        processingEngine.onProgressUpdate = { [weak self] progress in
            guard let self = self else { return }
            video.updateAnalysisStatus(
                "分析中",
                progress: progress.overallProgress,
                stage: progress.currentOperation
            )
            self.processingProgress = progress.overallProgress
            self.currentOperation = progress.currentOperation
        }

        // 🔥 性能优化：批量更新Rally检测结果（每10个或每15秒）
        // 🔧 修复：使用 videoId 而不是强引用 video 对象，避免循环引用
        let videoId = video.id
        processingEngine.onRallyDetected = { [weak self] rally in
            guard let self = self else { return }

            // 通过 id 查找 video（避免强引用）
            guard let targetVideo = self.videos.first(where: { $0.id == videoId }) else { return }

            // 仅在内存中累积
            targetVideo.highlights.append(rally)
            self.rallyBatchCounter += 1

            // 计算距离上次更新的时间
            let timeSinceLastUpdate = Date().timeIntervalSince(self.lastRallyUpdateTime)

            // 🔥 只在满足条件时才更新UI（每10个rally或每15秒）
            if self.rallyBatchCounter >= 10 || timeSinceLastUpdate >= 15.0 {
                Task { @MainActor in
                    targetVideo.rallyCount = targetVideo.highlights.count
                    self.rallyBatchCounter = 0
                    self.lastRallyUpdateTime = Date()
                }
            }
        }

        do {
            // 执行 AI 分析（耗时操作）- 使用新引擎
            let highlights = try await processingEngine.processVideo(video)

            // 检查任务是否被取消
            if Task.isCancelled {
                await MainActor.run {
                    video.cancelAnalysis()
                    analysisTaskMap.removeValue(forKey: video.id)
                }
                return
            }

            // 分析成功，更新模型
            await MainActor.run {
                // highlights已经通过onRallyDetected实时添加了，这里只需要确保完整性
                video.highlights = highlights
                video.rallyCount = highlights.count
                video.completeAnalysis()

                try? modelContext?.save()
                loadVideos()

                // 清理任务引用
                analysisTaskMap.removeValue(forKey: video.id)
                isAnalyzing = analysisTaskMap.count > 0
            }

        } catch {
            // 分析失败
            await MainActor.run {
                video.failAnalysis(error: error.localizedDescription)
                try? modelContext?.save()
                loadVideos()

                analysisTaskMap.removeValue(forKey: video.id)
                isAnalyzing = analysisTaskMap.count > 0
            }
        }
    }

    /// 分析视频（手动触发或重新分析）
    func analyzeVideo(_ video: Video) async {
        // 🔥 并发控制：如果有任务在进行，则拒绝新分析
        guard canStartNewTask else {
            errorMessage = busyStatusMessage ?? "当前有任务正在进行，请稍候"
            showError = true
            return
        }

        isAnalyzing = true
        selectedVideo = video
        video.startAnalysis()

        // 设置进度回调（已在 Engine 中切换到主线程，无需再包装）
        processingEngine.onProgressUpdate = { [weak self] progress in
            guard let self = self else { return }
            video.updateAnalysisStatus(
                "分析中",
                progress: progress.overallProgress,
                stage: progress.currentOperation
            )
            self.processingProgress = progress.overallProgress
            self.currentOperation = progress.currentOperation
        }

        // 设置实时回合检测回调（仅累积到内存，分析完成后统一保存）
        // 🔧 修复：使用 videoId 而不是强引用 video 对象，避免循环引用
        let analyzeVideoId = video.id
        processingEngine.onRallyDetected = { [weak self] rally in
            guard let self = self else { return }
            // 通过 id 查找 video（避免强引用）
            guard let targetVideo = self.videos.first(where: { $0.id == analyzeVideoId }) else { return }

            // 仅在内存中累积，避免频繁的数据库I/O和列表刷新
            targetVideo.highlights.append(rally)
            targetVideo.rallyCount = targetVideo.highlights.count
        }

        do {
            let highlights = try await processingEngine.processVideo(video)

            // 检查任务是否被取消
            if Task.isCancelled {
                video.cancelAnalysis()
                isAnalyzing = false
                return
            }

            // 更新模型
            video.highlights = highlights
            video.rallyCount = highlights.count
            video.completeAnalysis()

            try modelContext?.save()
            loadVideos()

        } catch {
            video.failAnalysis(error: error.localizedDescription)
            handleError(error)
        }

        isAnalyzing = false
    }

    /// 取消分析
    func cancelAnalysis(_ video: Video) {
        // 取消后台任务
        if let task = analysisTaskMap[video.id] {
            task.cancel()
            analysisTaskMap.removeValue(forKey: video.id)
        }

        // 更新视频状态
        video.cancelAnalysis()
        try? modelContext?.save()
        loadVideos()

        // 更新全局状态
        isAnalyzing = analysisTaskMap.count > 0
    }

    // MARK: - Video Export

    /// 导出 Top N 精彩片段
    func exportTopHighlights(from video: Video, count: Int) async {
        resetErrorState()

        // 🔥 并发控制：如果有任务在进行，则拒绝新导出
        guard canStartNewTask else {
            errorMessage = busyStatusMessage ?? "当前有任务正在进行，请稍候"
            showError = true
            return
        }

        isExporting = true
        exportedFileCount = 0  // 重置导出计数
        processingProgress = 0.0  // 重置进度
        currentOperation = "正在导出精彩片段..."

        // 启动进度同步任务
        let progressTask = Task {
            while !Task.isCancelled && isExporting {
                self.processingProgress = VideoProcessingService.shared.processingProgress
                self.currentOperation = VideoProcessingService.shared.currentOperation
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        do {
            let exportedFiles = try await VideoProcessingService.shared.exportTopHighlights(
                from: video,
                count: count,
                type: "top\(count)"
            )

            progressTask.cancel()

            // 保存导出记录
            for file in exportedFiles {
                video.addExportedFile(file)
            }

            try modelContext?.save()
            loadVideos()

            processingProgress = 1.0
            currentOperation = "正在保存到相册..."

            // 保存到相册
            await saveToPhotoLibrary(files: exportedFiles)

            // 只有在成功保存到相册后才标记为完成
            if exportedFileCount > 0 {
                currentOperation = "导出完成！"
            }

        } catch {
            progressTask.cancel()
            handleError(error)
        }

        isExporting = false
    }

    /// 导出自定义精彩片段
    func exportCustomHighlights(from video: Video, highlights: [VideoHighlight]) async {
        isExporting = true
        currentOperation = "正在导出自定义片段..."

        // 实现自定义导出逻辑
        // ...

        isExporting = false
    }

    /// 导出最长的 N 个回合
    func exportLongestHighlights(from video: Video, count: Int) async {
        resetErrorState()

        // 🔥 并发控制：如果有任务在进行，则拒绝新导出
        guard canStartNewTask else {
            errorMessage = busyStatusMessage ?? "当前有任务正在进行，请稍候"
            showError = true
            return
        }

        let longestHighlights = video.getLongestHighlights(count: count)
        guard !longestHighlights.isEmpty else {
            errorMessage = "没有可导出的回合"
            showError = true
            return
        }

        isExporting = true
        exportedFileCount = 0  // 重置导出计数
        processingProgress = 0.0  // 重置进度
        currentOperation = "正在导出最长的 \(count) 个回合..."

        // 启动进度同步任务
        let progressTask = Task {
            while !Task.isCancelled && isExporting {
                // 同步 Service 的进度到 ViewModel
                self.processingProgress = VideoProcessingService.shared.processingProgress
                self.currentOperation = VideoProcessingService.shared.currentOperation
                try? await Task.sleep(nanoseconds: 100_000_000) // 每 0.1 秒更新一次
            }
        }

        do {
            let exportedFiles = try await VideoProcessingService.shared.exportCustomHighlights(
                from: video,
                highlights: longestHighlights,
                exportName: "longest\(count)"
            )

            // 取消进度同步任务
            progressTask.cancel()

            // 保存导出记录
            for file in exportedFiles {
                video.addExportedFile(file)
            }

            try modelContext?.save()
            loadVideos()

            processingProgress = 1.0
            currentOperation = "正在保存到相册..."

            // 保存到相册
            await saveToPhotoLibrary(files: exportedFiles)

            // 只有在成功保存到相册后才标记为完成
            if exportedFileCount > 0 {
                currentOperation = "导出完成！"
            }

        } catch {
            progressTask.cancel()
            handleError(error)
        }

        isExporting = false
    }

    /// 导出收藏的回合
    func exportFavoriteHighlights(from video: Video) async {
        resetErrorState()

        // 🔥 并发控制：如果有任务在进行，则拒绝新导出
        guard canStartNewTask else {
            errorMessage = busyStatusMessage ?? "当前有任务正在进行，请稍候"
            showError = true
            return
        }

        let favorites = video.favoriteHighlights
        guard !favorites.isEmpty else {
            errorMessage = "没有收藏的回合"
            showError = true
            return
        }

        isExporting = true
        exportedFileCount = 0  // 重置导出计数
        processingProgress = 0.0  // 重置进度
        currentOperation = "正在导出 \(favorites.count) 个收藏回合..."

        // 启动进度同步任务
        let progressTask = Task {
            while !Task.isCancelled && isExporting {
                self.processingProgress = VideoProcessingService.shared.processingProgress
                self.currentOperation = VideoProcessingService.shared.currentOperation
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        do {
            let exportedFiles = try await VideoProcessingService.shared.exportCustomHighlights(
                from: video,
                highlights: favorites,
                exportName: "favorites"
            )

            progressTask.cancel()

            // 保存导出记录
            for file in exportedFiles {
                video.addExportedFile(file)
            }

            try modelContext?.save()
            loadVideos()

            processingProgress = 1.0
            currentOperation = "正在保存到相册..."

            // 保存到相册
            await saveToPhotoLibrary(files: exportedFiles)

            // 只有在成功保存到相册后才标记为完成
            if exportedFileCount > 0 {
                currentOperation = "导出完成！"
            }

        } catch {
            progressTask.cancel()
            handleError(error)
        }

        isExporting = false
    }

    /// 导出带网球标注的视频（调试用）
    func exportWithBallAnnotations(from video: Video) async {
        resetErrorState()

        // 🔥 并发控制：如果有任务在进行，则拒绝新导出
        guard canStartNewTask else {
            errorMessage = busyStatusMessage ?? "当前有任务正在进行，请稍候"
            showError = true
            return
        }

        let highlights = video.getLongestHighlights(count: 10) // 导出最长的10个回合
        guard !highlights.isEmpty else {
            errorMessage = "没有检测到回合"
            showError = true
            return
        }

        isExporting = true
        exportedFileCount = 0  // 重置导出计数
        processingProgress = 0.0  // 重置进度
        currentOperation = "正在导出带标注的视频..."

        // 启动进度同步任务
        let progressTask = Task {
            while !Task.isCancelled && isExporting {
                self.processingProgress = VideoProcessingService.shared.processingProgress
                self.currentOperation = VideoProcessingService.shared.currentOperation
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        do {
            // 导出带标注的视频
            let exportedFiles = try await VideoProcessingService.shared.exportWithBallAnnotations(
                from: video,
                highlights: highlights,
                exportName: "ball-annotations"
            )

            progressTask.cancel()

            // 保存导出记录
            for file in exportedFiles {
                video.addExportedFile(file)
            }

            try modelContext?.save()
            loadVideos()

            processingProgress = 1.0
            currentOperation = "正在保存到相册..."

            // 保存到相册
            await saveToPhotoLibrary(files: exportedFiles)

            // 只有在成功保存到相册后才标记为完成
            if exportedFileCount > 0 {
                currentOperation = "导出完成！"
            }

        } catch {
            progressTask.cancel()
            handleError(error)
        }

        isExporting = false
    }

    // MARK: - Video Management

    /// 删除视频
    func deleteVideo(_ video: Video) {
        // 删除文件
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent(video.originalFilePath)

        try? FileManager.default.removeItem(at: videoURL)

        if let thumbnailPath = video.thumbnailPath {
            let thumbnailURL = documentsURL.appendingPathComponent(thumbnailPath)
            try? FileManager.default.removeItem(at: thumbnailURL)
        }

        // 删除导出的文件
        for exportedFile in video.exportedFiles {
            let fileURL = documentsURL.appendingPathComponent(exportedFile.filePath)
            try? FileManager.default.removeItem(at: fileURL)
        }

        // 删除音频诊断文件
        if let diagnosticPath = video.audioDiagnosticDataPath {
            let diagnosticURL = URL(fileURLWithPath: diagnosticPath)
            try? FileManager.default.removeItem(at: diagnosticURL)
        }

        // 从数据库删除
        modelContext?.delete(video)
        try? modelContext?.save()

        loadVideos()
    }

    /// 更新视频标题
    func updateVideoTitle(_ video: Video, title: String) {
        video.title = title
        try? modelContext?.save()
        loadVideos()
    }

    // MARK: - Helper Methods

    /// 保存到相册
    private func saveToPhotoLibrary(files: [ExportedFile]) async {
        guard !files.isEmpty else { return }

        // 检查相册权限
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        // 如果没有权限，请求权限
        if status == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                await MainActor.run {
                    errorMessage = "需要相册权限才能保存视频。\n\n建议：请在设置中允许访问相册。"
                    showError = true
                }
                return
            }
        } else if status == .denied || status == .restricted {
            await MainActor.run {
                errorMessage = "无法保存到相册：权限被拒绝。\n\n建议：请在设置中允许应用访问相册。"
                showError = true
            }
            return
        }

        // 保存每个文件到相册
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var successCount = 0

        for file in files {
            let fileURL = documentsURL.appendingPathComponent(file.filePath)

            // 验证文件存在
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
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
                // 继续尝试保存其他文件
            }
        }

        // 更新成功保存的文件数量
        await MainActor.run {
            exportedFileCount = successCount
        }

        // 如果部分失败，显示警告
        if successCount < files.count && successCount > 0 {
            await MainActor.run {
                errorMessage = "部分视频保存失败。\n\n成功: \(successCount)/\(files.count)\n建议：请稍后重试失败的文件。"
                showError = true
            }
        } else if successCount == 0 {
            await MainActor.run {
                errorMessage = "所有视频保存失败。\n\n建议：\n• 检查相册权限\n• 确认设备存储空间充足\n• 重启应用后重试"
                showError = true
            }
        }
    }

    /// 错误处理
    private func handleError(_ error: Error) {
        print("❌ 错误发生: \(error.localizedDescription)")
        
        // 根据错误类型提供更友好的错误消息
        if let videoError = error as? VideoError {
            switch videoError {
            case .noVideoTrack:
                errorMessage = "视频文件无效：找不到视频轨道。\n\n建议：请确认这是一个有效的视频文件。"
            case .exportFailed:
                errorMessage = "视频导出失败。\n\n建议：请稍后重试，或尝试重新导入视频。"
            case .exportFailedWithReason(let reason):
                errorMessage = "导出失败：\(reason)\n\n建议：\n• 如果提示文件不存在，请重新导入视频\n• 如果提示空间不足，请清理设备存储空间\n• 如果问题持续，请联系技术支持"
            case .analysisFailed:
                errorMessage = "视频分析失败。\n\n建议：请稍后重试。"
            }
        } else {
            // 通用错误处理
            let errorDesc = error.localizedDescription
            
            if errorDesc.contains("not found") || errorDesc.contains("不存在") {
                errorMessage = "文件未找到。\n\n可能原因：\n• 视频文件已被删除\n• 文件路径无效\n\n建议：请重新导入视频。"
            } else if errorDesc.contains("space") || errorDesc.contains("空间") {
                errorMessage = "存储空间不足。\n\n建议：\n• 删除一些不需要的文件\n• 清理设备缓存\n• 导出到云存储"
            } else if errorDesc.contains("permission") || errorDesc.contains("权限") {
                errorMessage = "没有访问权限。\n\n建议：\n• 检查应用权限设置\n• 重启应用后重试"
            } else {
                errorMessage = "操作失败：\(errorDesc)\n\n建议：请稍后重试。如果问题持续，请重启应用。"
            }
        }

        showError = true
    }

    /// 获取处理状态文本
    func getStatusText(for video: Video) -> String {
        switch video.analysisStatus {
        case "导入中":
            return "导入中 \(Int(video.analysisProgress * 100))%"
        case "导入失败":
            return "导入失败"
        case "等待分析":
            return "待分析"
        case "分析中":
            return "分析中 \(Int(video.analysisProgress * 100))%"
        case "已完成":
            return "已分析 · \(video.rallyCount) 个回合"
        case "失败":
            return "分析失败"
        case "已取消":
            return "已取消"
        default:
            return video.analysisStatus
        }
    }

    private func resetErrorState() {
        errorMessage = nil
        showError = false
    }

    /// 获取处理状态颜色
    func getStatusColor(for video: Video) -> Color {
        switch video.analysisStatus {
        case "导入中":
            return .blue
        case "导入失败":
            return .red
        case "等待分析":
            return .gray
        case "分析中":
            return .blue
        case "已完成":
            return .green
        case "失败":
            return .red
        case "已取消":
            return .orange
        default:
            return .gray
        }
    }

    // MARK: - 新导出方法（使用 ExportManager）

    /// 使用 ExportManager 导出视频片段
    /// - Parameters:
    ///   - video: 源视频
    ///   - highlights: 要导出的片段列表
    ///   - quality: 导出质量
    ///   - mergeIntoSingle: 是否合并为单个视频
    ///   - exportNamePrefix: 导出文件名前缀
    func exportWithManager(
        from video: Video,
        highlights: [VideoHighlight],
        quality: ExportQuality = .high,
        mergeIntoSingle: Bool = true,
        exportNamePrefix: String = "export"
    ) async {
        resetErrorState()

        guard !highlights.isEmpty else {
            errorMessage = "没有可导出的片段"
            showError = true
            return
        }

        // 创建导出配置
        let highlightInfos = highlights.map { highlight in
            HighlightInfo(
                id: highlight.id,
                startTime: highlight.startTime,
                endTime: highlight.endTime
            )
        }

        let config = ExportTaskConfiguration(
            videoId: video.id,
            videoFilePath: video.originalFilePath,
            videoTitle: video.title,
            highlights: highlightInfos,
            quality: quality,
            mergeIntoSingle: mergeIntoSingle,
            exportNamePrefix: exportNamePrefix
        )

        do {
            let exportedFiles = try await ExportManager.shared.startExport(config: config)

            // 保存导出记录到视频模型
            for file in exportedFiles {
                video.addExportedFile(file)
            }

            try modelContext?.save()
            loadVideos()

            // 更新导出计数
            if case .completed(let count) = ExportManager.shared.state {
                exportedFileCount = count
            }

        } catch {
            if let exportError = error as? ExportError {
                errorMessage = exportError.localizedDescription
                if let suggestion = exportError.recoverySuggestion {
                    errorMessage = "\(errorMessage ?? "")\n\n建议：\(suggestion)"
                }
            } else {
                handleError(error)
            }
            showError = true
        }
    }

    /// 使用 ExportManager 导出最长的 N 个回合
    func exportLongestWithManager(from video: Video, count: Int, quality: ExportQuality = .high) async {
        let longestHighlights = video.getLongestHighlights(count: count)
        await exportWithManager(
            from: video,
            highlights: longestHighlights,
            quality: quality,
            mergeIntoSingle: true,
            exportNamePrefix: "longest\(count)"
        )
    }

    /// 使用 ExportManager 导出收藏的回合
    func exportFavoritesWithManager(from video: Video, quality: ExportQuality = .high) async {
        let favorites = video.favoriteHighlights
        await exportWithManager(
            from: video,
            highlights: favorites,
            quality: quality,
            mergeIntoSingle: true,
            exportNamePrefix: "favorites"
        )
    }

    /// 取消当前导出
    func cancelCurrentExport() {
        ExportManager.shared.cancelExport()
    }
}

// MARK: - Movie Transferable

/// 自定义的 Transferable 类型，用于从 PhotosPickerItem 获取视频文件 URL
/// 修复版本：复制到稳定的临时位置（received.file在闭包结束后可能失效）
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            print("📥 接收视频文件")
            print("   源文件: \(received.file.path)")

            // 🔑 关键：访问安全作用域资源（PhotosPicker提供的临时文件需要）
            let sourceURL = received.file
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            // 验证源文件存在
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                print("   ❌ 错误: 源文件不存在")
                throw VideoError.exportFailedWithReason("源文件不存在")
            }

            // 获取文件大小（用于日志）
            let fileSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0
            print("   文件大小: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")

            // 🔑 关键修复：必须复制到稳定的临时位置
            // 因为 received.file 在 importing 闭包结束后可能被系统删除
            let timestamp = Date().timeIntervalSince1970
            let tempFileName = "import_\(Int(timestamp))_\(UUID().uuidString)"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(tempFileName)
                .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)

            print("   目标临时路径: \(tempURL.path)")

            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // 复制文件到稳定的临时位置
            do {
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                print("   ✅ 文件复制到临时位置成功")

                // 验证复制后的文件存在且可读
                guard FileManager.default.fileExists(atPath: tempURL.path),
                      FileManager.default.isReadableFile(atPath: tempURL.path) else {
                    print("   ❌ 错误: 复制后的文件不可读")
                    throw VideoError.exportFailedWithReason("复制后的文件不可读")
                }
            } catch {
                print("   ❌ 文件复制失败: \(error.localizedDescription)")
                throw VideoError.exportFailedWithReason("文件复制失败: \(error.localizedDescription)")
            }

            return Self(url: tempURL)
        }
    }
}
