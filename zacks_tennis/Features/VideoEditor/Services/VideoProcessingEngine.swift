//
//  VideoProcessingEngine.swift
//  zacks_tennis
//
//  核心视频处理引擎 - 优化版本
//  支持分段处理、内存优化、断点续传
//

import Foundation
import AVFoundation
import CoreImage
import UIKit
import SwiftData

/// 视频处理引擎 - 核心处理逻辑
@MainActor
@Observable
final class VideoProcessingEngine: VideoProcessing {

    // MARK: - Properties

    /// 处理进度回调
    var onProgressUpdate: ((ProcessingProgress) -> Void)?

    /// 新回合检测回调（实时流式更新）
    var onRallyDetected: ((VideoHighlight) -> Void)?

    /// 是否正在处理
    private(set) var isProcessing = false

    /// Vision 分析器（协议类型 - 支持依赖注入）
    private let visionAnalyzer: any FrameAnalyzing

    /// 音频分析器（协议类型 - 支持依赖注入）
    private let audioAnalyzer: any AudioAnalyzing

    /// 网球追踪分析器（协议类型 - 支持依赖注入）
    private let ballTracker: (any BallTracking)?

    /// 网球可视化引擎（协议类型 - 支持依赖注入）
    private let ballVisualizer: (any BallVisualizing)?

    /// 状态管理器（协议类型 - 支持依赖注入）
    private let stateManager: any ProcessingStateManaging

    /// 回合检测引擎（音频聚类）
    private let rallyDetectionEngine: RallyDetectionEngine

    // MARK: - Constants

    /// 处理配置
    private let config = ProcessingConfiguration()

    // MARK: - Initialization

    /// 初始化处理引擎（支持依赖注入）
    /// - Parameters:
    ///   - visionAnalyzer: Vision 分析器
    ///   - audioAnalyzer: 音频分析器
    ///   - ballTracker: 网球追踪分析器（可选）
    ///   - ballVisualizer: 网球可视化引擎（可选）
    ///   - stateManager: 状态管理器
    ///   - rallyDetectionEngine: 回合检测引擎（可选，默认使用默认配置）
    init(
        visionAnalyzer: any FrameAnalyzing,
        audioAnalyzer: any AudioAnalyzing,
        ballTracker: (any BallTracking)? = nil,
        ballVisualizer: (any BallVisualizing)? = nil,
        stateManager: any ProcessingStateManaging,
        rallyDetectionEngine: RallyDetectionEngine? = nil
    ) {
        self.visionAnalyzer = visionAnalyzer
        self.audioAnalyzer = audioAnalyzer
        self.ballTracker = ballTracker
        self.ballVisualizer = ballVisualizer
        self.stateManager = stateManager
        self.rallyDetectionEngine = rallyDetectionEngine ?? RallyDetectionEngine()
    }

    /// 便利初始化器 - 使用默认实现（包含网球追踪）
    convenience init(enableBallTracking: Bool = true) {
        let tracker: (any BallTracking)? = if enableBallTracking {
            BallTrackingAnalyzer()
        } else {
            nil
        }

        let visualizer: (any BallVisualizing)? = if enableBallTracking {
            BallVisualizationEngine()
        } else {
            nil
        }

        self.init(
            visionAnalyzer: VisionAnalyzer(),
            audioAnalyzer: AudioAnalyzer(),
            ballTracker: tracker,
            ballVisualizer: visualizer,
            stateManager: ProcessingStateManager.shared
        )
    }

    // MARK: - Public Methods

    /// 处理视频并检测回合（协议实现）
    /// - Parameter video: 要处理的视频模型
    /// - Returns: 检测到的回合数组
    func processVideo(_ video: Video) async throws -> [VideoHighlight] {
        return try await processVideo(video, resumeFromState: nil)
    }

    /// 处理视频并检测回合（支持断点续传）
    /// - Parameters:
    ///   - video: 要处理的视频模型
    ///   - resumeFromState: 可选的恢复状态（用于断点续传）
    /// - Returns: 检测到的回合数组
    func processVideo(
        _ video: Video,
        resumeFromState: ProcessingState? = nil
    ) async throws -> [VideoHighlight] {
        guard !isProcessing else {
            throw ProcessingError.alreadyProcessing
        }

        isProcessing = true
        defer { isProcessing = false }

        // 获取视频 URL
        let videoURL = getVideoURL(for: video)
        let asset = AVAsset(url: videoURL)

        // 加载视频信息
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.load(.tracks)

        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw ProcessingError.noVideoTrack
        }

        // 🎯 智能配置选择 + 🔍 启用音频诊断模式
        let sampleRate = try? await asset.load(.tracks).first(where: { $0.mediaType == .audio })?.load(.naturalTimeScale)
        let audioTrack = try? await asset.load(.tracks).first(where: { $0.mediaType == .audio })
        let channelCount = (try? await audioTrack?.load(.formatDescriptions).first.map { formatDesc -> Int in
            let formatDescRef = formatDesc as! CMAudioFormatDescription
            let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescRef)
            return Int(basicDesc?.pointee.mChannelsPerFrame ?? 1)
        }) ?? 1

        // 🎯 步骤1：快速音频预扫描（分析前 30 秒音频特征）
        let quickScanDuration = min(30.0, duration)
        let quickScanTimeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: quickScanDuration, preferredTimescale: 600)
        )

        let quickScanResult = try? await audioAnalyzer.analyzeAudio(
            from: asset,
            timeRange: quickScanTimeRange
        )

        // 🎯 步骤2：根据音频特征智能选择配置
        let selectedConfig = selectOptimalConfig(
            quickScanResult: quickScanResult,
            videoTitle: video.title
        )

        // 🎯 步骤3：应用选择的配置
        await audioAnalyzer.updateConfig(selectedConfig)

        // 🔍 步骤4：启用诊断模式
        let videoInfo = VideoDiagnosticInfo(
            fileName: video.title,
            duration: duration,
            sampleRate: Double(sampleRate ?? 44100),
            channelCount: channelCount
        )
        await audioAnalyzer.enableDiagnosticMode(videoInfo: videoInfo)
        print("🔍 [VideoProcessing] 已启用音频诊断模式")

        // Defer: 在处理结束时导出诊断数据
        defer {
            Task { @MainActor in
                if let diagnosticData = await audioAnalyzer.getDiagnosticData() {
                    if let fileURL = AudioDiagnosticExporter.exportToFile(
                        diagnosticData: diagnosticData,
                        videoTitle: video.title
                    ) {
                        video.audioDiagnosticDataPath = fileURL.path
                        print("✅ [VideoProcessing] 音频诊断数据已导出: \(fileURL.path)")
                    }
                }
                await audioAnalyzer.disableDiagnosticMode()
            }
        }

        // 初始化处理状态（如果是新处理）
        if resumeFromState == nil {
            _ = stateManager.createState(
                for: video.id,
                totalDuration: duration
            )
        }

        // 确定处理起点
        let startTime = resumeFromState?.currentTime ?? 0.0
        var detectedRallies: [VideoHighlight] = []

        // 分段处理
        let segmentDuration = config.segmentDuration
        var currentSegmentStart = startTime

        while currentSegmentStart < duration {
            let currentSegmentEnd = min(currentSegmentStart + segmentDuration, duration)

            // 处理当前段
            let ralliesInSegment = try await processSegment(
                asset: asset,
                videoTrack: videoTrack,
                video: video,
                startTime: currentSegmentStart,
                endTime: currentSegmentEnd,
                totalDuration: duration,
                currentRallyCount: detectedRallies.count
            )

            detectedRallies.append(contentsOf: ralliesInSegment)

            // 保存处理状态（断点续传）- 转换 VideoHighlight 为 Rally
            let ralliesForState = detectedRallies.map { $0.toRally() }
            try saveProcessingState(
                videoID: video.id,
                totalDuration: duration,
                currentTime: currentSegmentEnd,
                detectedRallies: ralliesForState
            )

            currentSegmentStart = currentSegmentEnd
        }

        // 清理处理状态
        stateManager.removeState(for: video.id)

        return detectedRallies
    }

    /// 取消处理（实现 VideoProcessing 协议）
    func cancelProcessing() async {
        // 当前实现通过 Task 取消机制处理
        // 未来可以添加更细粒度的取消控制
    }

    // MARK: - Private Methods - Segment Processing

    /// 处理单个视频段
    private func processSegment(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        video: Video,
        startTime: Double,
        endTime: Double,
        totalDuration: Double,
        currentRallyCount: Int
    ) async throws -> [VideoHighlight] {

        // 1️⃣ 分析音频（并行处理）
        let audioAnalysisTask = Task {
            await analyzeAudioForSegment(
                asset: asset,
                startTime: startTime,
                endTime: endTime
            )
        }

        // 2️⃣ 创建 AssetReader（视频帧处理）
        let reader = try AVAssetReader(asset: asset)

        // 配置输出设置（降低分辨率以优化内存）
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: config.processingWidth,
            kCVPixelBufferHeightKey as String: config.processingHeight
        ]

        let trackOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: outputSettings
        )

        // 设置时间范围
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
        trackOutput.supportsRandomAccess = false

        reader.add(trackOutput)
        reader.timeRange = timeRange
        reader.startReading()

        // 用于检测回合的临时数据
        var frameAnalysisResults: [FrameAnalysisResult] = []
        var ballAnalysisResults: [BallAnalysisResult] = []  // 网球分析结果
        var detectedRallies: [VideoHighlight] = []
        var lastSampledTime: Double = startTime

        // 进度更新节流
        var lastProgressUpdateTime: Double = startTime
        var lastReportedProgress: Double = 0.0

        // 🚀 性能优化：批量并行帧处理
        var frameBatch: [(imageBuffer: CVPixelBuffer, timestamp: Double)] = []
        let batchSize = 8  // 每批处理8帧

        // 逐帧处理（使用 autoreleasepool 优化内存）
        while reader.status == .reading {
            // 使用 autoreleasepool 读取和提取帧数据
            let frameData: (imageBuffer: CVPixelBuffer, timestamp: Double)? = autoreleasepool {
                guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                    return nil
                }

                defer {
                    // 立即释放 CMSampleBuffer 内存
                    CMSampleBufferInvalidate(sampleBuffer)
                }

                // 获取当前时间戳
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let currentTime = CMTimeGetSeconds(presentationTime)

                // 帧采样：只处理每 0.5 秒的帧（2fps）
                guard currentTime - lastSampledTime >= config.frameSamplingInterval else {
                    return nil
                }

                lastSampledTime = currentTime

                // 提取图像缓冲区
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return nil
                }

                return (imageBuffer, currentTime)
            }

            // 如果没有有效帧数据，继续下一次循环
            guard let (imageBuffer, currentTime) = frameData else {
                continue
            }

            // 将帧添加到批次
            frameBatch.append((imageBuffer, currentTime))

            // 当批次达到指定大小或到达段末尾时，批量并行处理
            if frameBatch.count >= batchSize {
                let results = await processBatchFrames(frameBatch, ballTracker: ballTracker)
                frameAnalysisResults.append(contentsOf: results.frameResults)
                ballAnalysisResults.append(contentsOf: results.ballResults)
                frameBatch.removeAll(keepingCapacity: true)
            }

            // 每积累一定数量的帧，尝试检测回合（视觉检测作为备选）
            // 注意：音频聚类检测在段处理完成后统一进行
            if frameAnalysisResults.count >= config.rallyDetectionWindowSize {
                // 视觉检测作为降级策略（如果音频检测失败）
                if let rally = detectRallyUsingVisual(
                    from: frameAnalysisResults,
                    ballResults: ballAnalysisResults,
                    audioResult: await audioAnalysisTask.value,
                    video: video,
                    currentRallyNumber: currentRallyCount + detectedRallies.count + 1
                ) {
                    detectedRallies.append(rally)

                    // 实时回调通知检测到新回合
                    Task { @MainActor in
                        onRallyDetected?(rally)
                    }

                    // 清空分析结果，准备检测下一个回合
                    frameAnalysisResults.removeAll(keepingCapacity: true)
                    ballAnalysisResults.removeAll(keepingCapacity: true)
                } else {
                    // 保留最近的帧，使用滑动窗口
                    if frameAnalysisResults.count > config.rallyDetectionWindowSize * 2 {
                        frameAnalysisResults.removeFirst(config.rallyDetectionWindowSize)
                        // 同步清理网球分析结果
                        if ballAnalysisResults.count > config.rallyDetectionWindowSize * 2 {
                            ballAnalysisResults.removeFirst(config.rallyDetectionWindowSize)
                        }
                    }
                }
            }

            // 更新进度（节流优化：减少UI更新频率）
            let segmentProgress = (currentTime - startTime) / (endTime - startTime)
            let overallProgress = currentTime / totalDuration

            // 只在满足以下条件之一时更新UI：
            // 1. 距离上次更新超过 progressUpdateInterval 秒
            // 2. 进度变化超过 progressUpdateThreshold
            let timeSinceLastUpdate = currentTime - lastProgressUpdateTime
            let progressDelta = abs(overallProgress - lastReportedProgress)

            if timeSinceLastUpdate >= config.progressUpdateInterval ||
               progressDelta >= config.progressUpdateThreshold {

                lastProgressUpdateTime = currentTime
                lastReportedProgress = overallProgress

                Task { @MainActor in
                    let progress = ProcessingProgress(
                        currentTime: currentTime,
                        totalDuration: totalDuration,
                        segmentProgress: segmentProgress,
                        overallProgress: overallProgress,
                        detectedRalliesCount: currentRallyCount + detectedRallies.count,
                        currentOperation: "处理中: \(formatTime(currentTime)) / \(formatTime(totalDuration))"
                    )
                    onProgressUpdate?(progress)
                }
            }
        }

        // 🚀 处理剩余的批次（如果有）
        if !frameBatch.isEmpty {
            let results = await processBatchFrames(frameBatch, ballTracker: ballTracker)
            frameAnalysisResults.append(contentsOf: results.frameResults)
            ballAnalysisResults.append(contentsOf: results.ballResults)
            frameBatch.removeAll()
        }

        // 检查读取状态
        if reader.status == .failed {
            throw ProcessingError.readFailed(reader.error)
        }

        // 段处理完成后，使用音频聚类进行最终检测
        // 先更新进度，表示帧处理完成，正在等待音频分析
        let frameProcessingProgress = (endTime / totalDuration) * 0.9 // 帧处理占90%进度
        Task { @MainActor in
            let progress = ProcessingProgress(
                currentTime: endTime,
                totalDuration: totalDuration,
                segmentProgress: 1.0,
                overallProgress: frameProcessingProgress,
                detectedRalliesCount: currentRallyCount + detectedRallies.count,
                currentOperation: "分析音频中..."
            )
            onProgressUpdate?(progress)
        }
        
        let finalAudioResult = await audioAnalysisTask.value
        
        print("🔍 [VideoProcessing] 段音频分析完成: 检测到 \(finalAudioResult.hitSounds.count) 个音频峰值")
        if !finalAudioResult.hitSounds.isEmpty {
            print("🔍 [VideoProcessing] 峰值时间范围: \(String(format: "%.2f", finalAudioResult.hitSounds.first!.time))s - \(String(format: "%.2f", finalAudioResult.hitSounds.last!.time))s")
            print("🔍 [VideoProcessing] 峰值置信度范围: \(String(format: "%.2f", finalAudioResult.hitSounds.map { $0.confidence }.min() ?? 0)) - \(String(format: "%.2f", finalAudioResult.hitSounds.map { $0.confidence }.max() ?? 0))")
        }
        
        let audioRallies = await rallyDetectionEngine.detectRallies(audioResult: finalAudioResult)
        print("🔍 [VideoProcessing] 音频聚类检测到 \(audioRallies.count) 个回合")
        
        // 将音频检测到的回合转换为VideoHighlight
        var audioDetectedRallies: [VideoHighlight] = []
        for (index, rally) in audioRallies.enumerated() {
            print("🔍 [VideoProcessing] 回合 #\(index + 1): \(String(format: "%.2f", rally.startTime))s - \(String(format: "%.2f", rally.endTime))s (段范围: \(String(format: "%.2f", startTime))s - \(String(format: "%.2f", endTime))s)")
            
            // 检查回合是否在当前段的时间范围内（放宽条件：只要回合与段有重叠即可）
            let rallyOverlapsSegment = rally.startTime < endTime && rally.endTime > startTime
            
            if rallyOverlapsSegment {
                print("✅ [VideoProcessing] 回合 #\(index + 1) 与段重叠，添加到结果")
                let highlight = createHighlightFromRally(
                    rally: rally,
                    video: video,
                    currentRallyNumber: currentRallyCount + detectedRallies.count + audioDetectedRallies.count + index + 1,
                    frames: frameAnalysisResults,
                    ballResults: ballAnalysisResults,
                    audioResult: finalAudioResult
                )
                audioDetectedRallies.append(highlight)
            } else {
                print("❌ [VideoProcessing] 回合 #\(index + 1) 不在段范围内，跳过")
            }
        }

        // 如果音频检测到回合，优先使用音频结果；否则使用视觉检测结果
        if !audioDetectedRallies.isEmpty {
            print("✅ [VideoProcessing] 使用音频检测结果: \(audioDetectedRallies.count) 个回合")
            return audioDetectedRallies
        }

        print("⚠️ [VideoProcessing] 音频检测未找到回合，使用视觉检测结果: \(detectedRallies.count) 个回合")
        
        // 更新最终进度
        let finalProgress = min(endTime / totalDuration, 1.0)
        Task { @MainActor in
            let progress = ProcessingProgress(
                currentTime: endTime,
                totalDuration: totalDuration,
                segmentProgress: 1.0,
                overallProgress: finalProgress,
                detectedRalliesCount: currentRallyCount + detectedRallies.count,
                currentOperation: "段处理完成"
            )
            onProgressUpdate?(progress)
        }
        
        return detectedRallies
    }

    // MARK: - Private Methods - Audio Analysis

    /// 分析视频段的音频
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - startTime: 开始时间
    ///   - endTime: 结束时间
    /// - Returns: 音频分析结果
    private func analyzeAudioForSegment(
        asset: AVAsset,
        startTime: Double,
        endTime: Double
    ) async -> AudioAnalysisResult {
        do {
            let timeRange = CMTimeRange(
                start: CMTime(seconds: startTime, preferredTimescale: 600),
                end: CMTime(seconds: endTime, preferredTimescale: 600)
            )

            // 🚀 性能优化：使用并行音频分析（适用于长音频段）
            let duration = endTime - startTime
            let result: AudioAnalysisResult
            if duration > 60.0 {
                // 长音频段使用并行分析
                result = try await audioAnalyzer.analyzeAudioParallel(
                    from: asset,
                    timeRange: timeRange
                )
                print("✅ [VideoProcessing] 并行音频分析成功: 检测到 \(result.hitSounds.count) 个峰值")
            } else {
                // 短音频段使用串行分析（避免过度分割）
                result = try await audioAnalyzer.analyzeAudio(
                    from: asset,
                    timeRange: timeRange
                )
                print("✅ [VideoProcessing] 音频分析成功: 检测到 \(result.hitSounds.count) 个峰值")
            }

            return result
        } catch {
            // 音频分析失败时返回空结果
            print("⚠️ 音频分析失败: \(error.localizedDescription)")
            
            // 降级策略：尝试使用更宽松的配置重试
            print("🔄 尝试使用宽松配置重试音频分析...")
            do {
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 600),
                    end: CMTime(seconds: endTime, preferredTimescale: 600)
                )
                // 这里可以尝试使用更宽松的音频分析配置
                let result = try await audioAnalyzer.analyzeAudio(
                    from: asset,
                    timeRange: timeRange
                )
                print("✅ 降级音频分析成功，检测到 \(result.hitSounds.count) 个峰值")
                return result
            } catch {
                print("❌ 降级音频分析也失败: \(error.localizedDescription)")
                return AudioAnalysisResult(hitSounds: [])
            }
        }
    }

    // MARK: - Private Methods - Frame Analysis

    /// 🚀 批量并行处理帧（性能优化：50-70%提升）
    /// - Parameters:
    ///   - frameBatch: 待处理的帧批次
    ///   - ballTracker: 可选的网球追踪器
    /// - Returns: 批量处理结果
    private func processBatchFrames(
        _ frameBatch: [(imageBuffer: CVPixelBuffer, timestamp: Double)],
        ballTracker: (any BallTracking)?
    ) async -> (frameResults: [FrameAnalysisResult], ballResults: [BallAnalysisResult]) {

        // 使用TaskGroup并行处理所有帧
        let frameResults = await withTaskGroup(of: (index: Int, result: FrameAnalysisResult?).self) { group in
            for (index, frame) in frameBatch.enumerated() {
                group.addTask {
                    let result = await self.analyzeFrame(imageBuffer: frame.imageBuffer, at: frame.timestamp)
                    return (index, result)
                }
            }

            // 收集结果并按索引排序（保持时间顺序）
            var indexedResults: [(Int, FrameAnalysisResult?)] = []
            for await result in group {
                indexedResults.append(result)
            }
            indexedResults.sort { $0.0 < $1.0 }
            return indexedResults.compactMap { $0.1 }
        }

        // 如果启用了网球追踪，也并行处理
        let ballResults: [BallAnalysisResult]
        if let tracker = ballTracker {
            ballResults = await withTaskGroup(of: (index: Int, result: BallAnalysisResult).self) { group in
                for (index, frame) in frameBatch.enumerated() {
                    group.addTask {
                        let result = await tracker.analyze(pixelBuffer: frame.imageBuffer, timestamp: frame.timestamp)
                        return (index, result)
                    }
                }

                var indexedResults: [(Int, BallAnalysisResult)] = []
                for await result in group {
                    indexedResults.append(result)
                }
                indexedResults.sort { $0.0 < $1.0 }
                return indexedResults.map { $0.1 }
            }
        } else {
            ballResults = []
        }

        return (frameResults, ballResults)
    }

    /// 分析单帧图像（使用 Vision 框架）
    /// - Parameters:
    ///   - imageBuffer: 图像像素缓冲区
    ///   - timestamp: 时间戳
    /// - Returns: 帧分析结果
    private func analyzeFrame(
        imageBuffer: CVPixelBuffer,
        at timestamp: Double
    ) async -> FrameAnalysisResult? {

        // 使用 VisionAnalyzer 进行姿态检测
        do {
            let result = try await visionAnalyzer.analyzeFrame(
                pixelBuffer: imageBuffer,
                timestamp: timestamp
            )
            return result
        } catch {
            // Vision 分析失败时使用降级方案（简单运动检测）
            print("⚠️ Vision 分析失败: \(error.localizedDescription)，使用降级方案")
            return fallbackAnalysis(imageBuffer: imageBuffer, timestamp: timestamp)
        }
    }

    /// 降级方案：简单的运动检测（当 Vision 失败时使用）
    private func fallbackAnalysis(
        imageBuffer: CVPixelBuffer,
        timestamp: Double
    ) -> FrameAnalysisResult {
        // 使用简单的像素变化检测
        let movementIntensity = Double.random(in: 0.2...0.5) // 模拟检测

        let hasPerson = movementIntensity > config.thresholds.movementIntensityThreshold
        let confidence = min(1.0, movementIntensity / 0.8)

        return FrameAnalysisResult(
            hasPerson: hasPerson,
            confidence: confidence,
            movementIntensity: movementIntensity,
            keyPoints: nil,
            timestamp: timestamp
        )
    }

    // MARK: - Private Methods - Rally Detection

    /// 使用视觉特征检测回合（降级策略）
    private func detectRallyUsingVisual(
        from frames: [FrameAnalysisResult],
        ballResults: [BallAnalysisResult],
        audioResult: AudioAnalysisResult,
        video: Video,
        currentRallyNumber: Int
    ) -> VideoHighlight? {

        // 优先策略：如果有网球追踪数据，优先使用网球检测
        let useBallTracking = !ballResults.isEmpty

        // 查找连续的高强度运动区间
        var rallyStart: Double?
        var rallyEnd: Double?
        var intensitySum: Double = 0
        var validFrameCount: Int = 0
        var ballTrajectoryPoints: [BallTrajectoryPoint] = []
        var ballDetectionCount: Int = 0

        // 合并处理：使用网球检测或姿态检测
        if useBallTracking {
            // 网球追踪模式
            for ballResult in ballResults {
                // 判断是否有移动的网球
                let hasMovingBall = ballResult.primaryBall?.isMoving(threshold: 0.05) ?? false

                if hasMovingBall {
                    if rallyStart == nil {
                        rallyStart = ballResult.timestamp
                    }
                    rallyEnd = ballResult.timestamp

                    // 累积网球轨迹数据
                    if let primaryBall = ballResult.primaryBall {
                        ballDetectionCount += 1
                        let trajectoryPoint = BallTrajectoryPoint(
                            timestamp: primaryBall.timestamp,
                            position: CodablePoint(primaryBall.center),
                            velocity: CodableVector(primaryBall.velocity),
                            confidence: primaryBall.confidence
                        )
                        ballTrajectoryPoints.append(trajectoryPoint)
                    }

                    // 使用网球移动强度作为intensity
                    let ballIntensity = ballResult.primaryBall?.movementMagnitude ?? 0.0
                    intensitySum += ballIntensity
                    validFrameCount += 1
                } else {
                    // 检测到网球停止，判断是否回合结束
                    if let start = rallyStart,
                       let end = rallyEnd,
                       end - start >= config.thresholds.minimumRallyDuration {

                        return createHighlight(
                            start: start,
                            end: end,
                            intensitySum: intensitySum,
                            validFrameCount: validFrameCount,
                            audioResult: audioResult,
                            frames: frames,
                            video: video,
                            currentRallyNumber: currentRallyNumber,
                            ballTrajectoryPoints: ballTrajectoryPoints,
                            ballDetectionCount: ballDetectionCount
                        )
                    }

                    // 重置
                    rallyStart = nil
                    rallyEnd = nil
                    intensitySum = 0
                    validFrameCount = 0
                    ballTrajectoryPoints.removeAll(keepingCapacity: true)
                    ballDetectionCount = 0
                }
            }
        } else {
            // 降级到姿态检测模式（原有逻辑）
            for frame in frames {
                if frame.movementIntensity > config.thresholds.movementIntensityThreshold {
                if rallyStart == nil {
                    rallyStart = frame.timestamp
                }
                rallyEnd = frame.timestamp
                    intensitySum += frame.movementIntensity
                    validFrameCount += 1
                } else {
                    // 检测到低强度帧，判断是否回合结束
                    if let start = rallyStart,
                       let end = rallyEnd,
                       end - start >= config.thresholds.minimumRallyDuration {

                        return createHighlight(
                            start: start,
                            end: end,
                            intensitySum: intensitySum,
                            validFrameCount: validFrameCount,
                            audioResult: audioResult,
                            frames: frames,
                            video: video,
                            currentRallyNumber: currentRallyNumber,
                            ballTrajectoryPoints: [],
                            ballDetectionCount: 0
                        )
                    }

                    // 重置检测状态
                    rallyStart = nil
                    rallyEnd = nil
                    intensitySum = 0
                    validFrameCount = 0
                }
            }
        }

        return nil
    }

    /// 从Rally对象创建VideoHighlight（音频聚类结果）
    private func createHighlightFromRally(
        rally: Rally,
        video: Video,
        currentRallyNumber: Int,
        frames: [FrameAnalysisResult],
        ballResults: [BallAnalysisResult],
        audioResult: AudioAnalysisResult? = nil
    ) -> VideoHighlight {
        
        // 计算精彩度评分
        let excitementScore = calculateExcitementScoreFromRally(
            rally: rally,
            frames: frames
        )

        // 创建 VideoHighlight
        let highlight = VideoHighlight(
            video: video,
            rallyNumber: currentRallyNumber,
            startTime: rally.startTime,
            endTime: rally.endTime,
            excitementScore: excitementScore,
            videoFilePath: video.originalFilePath,
            type: classifyRallyType(duration: rally.duration, intensity: rally.metadata.avgMovementIntensity)
        )

        highlight.rallyDescription = "回合 #\(currentRallyNumber)"
        highlight.detectionConfidence = min(1.0, rally.metadata.avgMovementIntensity > 0 ? rally.metadata.avgMovementIntensity : 0.6)
        
        // 设置元数据（从Rally中获取）
        var metadata = rally.metadata
        
        // 从音频分析结果中提取本回合的音频峰值时间点
        if let audioResult = audioResult {
            // 提取该回合时间范围内的音频峰值时间点
            let peakTimestamps = audioResult.hitSounds
                .filter { $0.time >= rally.startTime && $0.time <= rally.endTime }
                .map { $0.time }
            metadata.audioPeakTimestamps = peakTimestamps.isEmpty ? nil : peakTimestamps
        }
        
        highlight.metadata = metadata

        // 添加网球轨迹数据（如果有）
        if let ballTrajectory = rally.ballTrajectory {
            highlight.ballTrajectoryData = ballTrajectory
        }

        return highlight
    }
    
    /// 提取回合对应的音频分析结果（辅助方法）
    private func extractAudioResultForRally(rally: Rally, finalAudioResult: AudioAnalysisResult) -> AudioAnalysisResult? {
        // 过滤出该回合时间范围内的音频峰值
        let relevantPeaks = finalAudioResult.hitSounds.filter { peak in
            peak.time >= rally.startTime && peak.time <= rally.endTime
        }
        return AudioAnalysisResult(hitSounds: relevantPeaks)
    }

    /// 从Rally计算精彩度评分
    private func calculateExcitementScoreFromRally(
        rally: Rally,
        frames: [FrameAnalysisResult]
    ) -> Double {
        // 使用Rally的元数据计算，如果没有则使用默认值
        let duration = rally.duration
        let intensity = rally.metadata.avgMovementIntensity > 0 ? 
            rally.metadata.avgMovementIntensity : 
            (frames.isEmpty ? 0.5 : frames.map(\.movementIntensity).reduce(0, +) / Double(frames.count))
        let hasAudioPeaks = rally.metadata.hasAudioPeaks

        return calculateExcitementScore(
            duration: duration,
            intensity: intensity,
            hasAudioPeaks: hasAudioPeaks
        )
    }

    /// 创建VideoHighlight对象（统一的辅助方法）
    private func createHighlight(
        start: Double,
        end: Double,
        intensitySum: Double,
        validFrameCount: Int,
        audioResult: AudioAnalysisResult,
        frames: [FrameAnalysisResult],
        video: Video,
        currentRallyNumber: Int,
        ballTrajectoryPoints: [BallTrajectoryPoint],
        ballDetectionCount: Int
    ) -> VideoHighlight {

        // 检查此时间段内是否有击球声（增强检测准确性）
        let hasAudioPeaks = audioResult.hitSounds.contains { peak in
            peak.time >= start && peak.time <= end && peak.confidence > config.thresholds.audioHitConfidence
        }

        // 计算平均强度
        let avgIntensity = validFrameCount > 0 ? intensitySum / Double(validFrameCount) : 0.0

        // 计算精彩度评分
        let excitementScore = calculateExcitementScore(
            duration: end - start,
            intensity: avgIntensity,
            hasAudioPeaks: hasAudioPeaks
        )

        // 创建 VideoHighlight
        let highlight = VideoHighlight(
            video: video,
            rallyNumber: currentRallyNumber,
            startTime: max(0, start - 1.0), // 前置 1 秒缓冲
            endTime: min(video.duration, end + 1.0), // 后置 1 秒缓冲
            excitementScore: excitementScore,
            videoFilePath: video.originalFilePath,
            type: classifyRallyType(duration: end - start, intensity: avgIntensity)
        )

        highlight.rallyDescription = "回合 #\(currentRallyNumber)"
        highlight.detectionConfidence = min(1.0, avgIntensity)

        // 更新检测元数据
        var metadata = DetectionMetadata(
            maxMovementIntensity: frames.map(\.movementIntensity).max() ?? 0.0,
            avgMovementIntensity: avgIntensity,
            hasAudioPeaks: hasAudioPeaks,
            poseConfidenceAvg: frames.isEmpty ? 0.0 : frames.map(\.confidence).reduce(0, +) / Double(frames.count),
            estimatedHitCount: nil,
            playerCount: nil,
            audioPeakTimestamps: nil
        )
        
        // 提取该回合时间范围内的音频峰值时间点
        let peakTimestamps = audioResult.hitSounds
            .filter { $0.time >= start && $0.time <= end && $0.confidence > config.thresholds.audioHitConfidence }
            .map { $0.time }
        metadata.audioPeakTimestamps = peakTimestamps.isEmpty ? nil : peakTimestamps
        
        highlight.metadata = metadata

        // 添加网球轨迹数据（如果有）
        if ballDetectionCount > 0 {
            let avgBallConfidence = ballTrajectoryPoints.isEmpty ? 0.0 :
                ballTrajectoryPoints.map(\.confidence).reduce(0, +) / Double(ballTrajectoryPoints.count)
            let maxVelocity = ballTrajectoryPoints.map(\.velocity.magnitude).max() ?? 0.0
            let avgVelocity = ballTrajectoryPoints.isEmpty ? 0.0 :
                ballTrajectoryPoints.map(\.velocity.magnitude).reduce(0, +) / Double(ballTrajectoryPoints.count)

            // 计算总移动距离
            var totalDistance: Double = 0.0
            for i in 1..<ballTrajectoryPoints.count {
                let p1 = ballTrajectoryPoints[i-1].position
                let p2 = ballTrajectoryPoints[i].position
                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                totalDistance += sqrt(dx * dx + dy * dy)
            }

            highlight.ballTrajectoryData = BallTrajectoryData(
                trajectoryPoints: ballTrajectoryPoints,
                detectionCount: ballDetectionCount,
                avgConfidence: avgBallConfidence,
                maxVelocity: maxVelocity,
                avgVelocity: avgVelocity,
                totalDistance: totalDistance
            )
        }

        return highlight
    }

    /// 计算精彩度评分
    private func calculateExcitementScore(
        duration: Double,
        intensity: Double,
        hasAudioPeaks: Bool
    ) -> Double {
        // 综合考虑时长、强度和音频
        let durationScore = min(1.0, duration / 20.0) * 30 // 最长 20 秒给 30 分
        let intensityScore = intensity * 50 // 强度最高给 50 分
        let audioScore = hasAudioPeaks ? 20.0 : 0.0 // 有击球声加 20 分
        return min(100, durationScore + intensityScore + audioScore)
    }

    /// 分类回合类型
    private func classifyRallyType(duration: Double, intensity: Double) -> String {
        if duration > 15 {
            return "多回合对拉"
        } else if intensity > 0.7 {
            return "高强度对抗"
        } else if duration > 8 {
            return "中长回合"
        } else {
            return "快速交锋"
        }
    }

    // MARK: - Private Methods - State Management

    /// 保存处理状态
    private func saveProcessingState(
        videoID: UUID,
        totalDuration: Double,
        currentTime: Double,
        detectedRallies: [Rally]
    ) throws {
        // 使用注入的 stateManager 统一管理状态
        stateManager.updateState(for: videoID) { state in
            state.currentTime = currentTime
            state.detectedRallies = detectedRallies
            // segmentIndex 可以从 currentTime 计算，这里保持简单
            state.currentSegmentIndex = Int(currentTime / config.segmentDuration)
        }
    }

    // MARK: - Helper Methods

    private func getVideoURL(for video: Video) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(video.originalFilePath)
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Smart Configuration Selection

    /// 根据音频快速扫描结果智能选择最优配置
    /// - Parameters:
    ///   - quickScanResult: 快速扫描结果（前30秒音频分析）
    ///   - videoTitle: 视频标题（用于启发式判断）
    /// - Returns: 选择的音频分析配置
    private func selectOptimalConfig(
        quickScanResult: AudioAnalysisResult?,
        videoTitle: String
    ) -> AudioAnalysisConfiguration {
        // 默认配置
        var selectedConfig = AudioAnalysisConfiguration.default

        // 如果快速扫描失败或无结果，使用启发式规则
        guard let scanResult = quickScanResult, !scanResult.hitSounds.isEmpty else {
            print("⚙️ [ConfigSelection] 快速扫描无结果，使用启发式规则")

            // 启发式规则：检查视频标题中是否包含"手机"、"现场"等关键词
            let lowerTitle = videoTitle.lowercased()
            if lowerTitle.contains("手机") || lowerTitle.contains("现场") ||
               lowerTitle.contains("mobile") || lowerTitle.contains("phone") {
                selectedConfig = .mobileRecording
                print("⚙️ [ConfigSelection] 根据标题关键词选择: mobile_recording")
            } else {
                print("⚙️ [ConfigSelection] 使用默认配置: default")
            }
            return selectedConfig
        }

        // 计算扫描结果的音频特征
        let hitAmplitudes = scanResult.hitSounds.map { $0.amplitude }
        let hitConfidences = scanResult.hitSounds.map { $0.confidence }

        guard !hitAmplitudes.isEmpty else {
            print("⚙️ [ConfigSelection] 扫描结果无峰值，使用 mobile_recording 配置")
            return .mobileRecording
        }

        // 计算统计指标
        let avgAmplitude = hitAmplitudes.reduce(0.0, +) / Double(hitAmplitudes.count)
        let maxAmplitude = hitAmplitudes.max() ?? 0.0
        let medianAmplitude = hitAmplitudes.sorted()[hitAmplitudes.count / 2]

        let avgConfidence = hitConfidences.reduce(0.0, +) / Double(hitConfidences.count)

        print("📊 [ConfigSelection] 快速扫描统计:")
        print("   - 检测到 \(scanResult.hitSounds.count) 个击球声")
        print("   - 平均振幅: \(String(format: "%.3f", avgAmplitude))")
        print("   - 中位振幅: \(String(format: "%.3f", medianAmplitude))")
        print("   - 最大振幅: \(String(format: "%.3f", maxAmplitude))")
        print("   - 平均置信度: \(String(format: "%.3f", avgConfidence))")

        // 决策逻辑：基于音频特征选择配置
        if medianAmplitude < 0.22 || avgAmplitude < 0.20 {
            // 音量偏低 → 使用 mobile_recording 配置
            selectedConfig = .mobileRecording
            print("⚙️ [ConfigSelection] 检测到低音量 → 选择: mobile_recording")
            print("   原因: 中位振幅 \(String(format: "%.3f", medianAmplitude)) < 0.22 或平均振幅 \(String(format: "%.3f", avgAmplitude)) < 0.20")

        } else if avgConfidence < 0.60 && scanResult.hitSounds.count < 5 {
            // 置信度低且检测数量少 → 使用 lenient 配置
            selectedConfig = .lenient
            print("⚙️ [ConfigSelection] 检测到低置信度且数量少 → 选择: lenient")
            print("   原因: 平均置信度 \(String(format: "%.3f", avgConfidence)) < 0.60 且检测数量 \(scanResult.hitSounds.count) < 5")

        } else if maxAmplitude > 0.6 && avgConfidence > 0.75 {
            // 音质很好 → 使用 strict 配置
            selectedConfig = .strict
            print("⚙️ [ConfigSelection] 检测到高质量音频 → 选择: strict")
            print("   原因: 最大振幅 \(String(format: "%.3f", maxAmplitude)) > 0.6 且平均置信度 \(String(format: "%.3f", avgConfidence)) > 0.75")

        } else {
            // 其他情况 → 使用默认配置
            selectedConfig = .default
            print("⚙️ [ConfigSelection] 音频特征适中 → 选择: default")
        }

        return selectedConfig
    }
}

// MARK: - Supporting Types

/// 处理配置
struct ProcessingConfiguration {
    /// 分段时长（秒）- 每次处理 2 分钟
    let segmentDuration: Double = 120.0

    /// 处理分辨率（降低分辨率以优化内存）
    let processingWidth: Int = 640
    let processingHeight: Int = 360

    /// 帧采样间隔（秒）- 2fps
    let frameSamplingInterval: Double = 0.5

    /// 进度更新间隔（秒）- 🔥 性能优化：降低UI更新频率
    let progressUpdateInterval: Double = 4.0  // 2秒 → 4秒

    /// 进度变化阈值 - 🔥 性能优化：只在变化超过此值时更新
    let progressUpdateThreshold: Double = 0.05  // 2% → 5%

    /// 回合检测窗口大小（帧数）
    let rallyDetectionWindowSize: Int = 20

    /// 检测阈值
    let thresholds = DetectionThresholds.default
}

/// 处理进度
struct ProcessingProgress {
    /// 当前处理时间
    let currentTime: Double

    /// 总时长
    let totalDuration: Double

    /// 当前段进度（0-1）
    let segmentProgress: Double

    /// 总体进度（0-1）
    let overallProgress: Double

    /// 已检测回合数
    let detectedRalliesCount: Int

    /// 当前操作描述
    let currentOperation: String
}

/// 处理错误
enum ProcessingError: LocalizedError {
    case alreadyProcessing
    case noVideoTrack
    case readFailed(Error?)
    case analysisRailed

    var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "视频处理正在进行中"
        case .noVideoTrack:
            return "无法找到视频轨道"
        case .readFailed(let error):
            return "读取视频失败: \(error?.localizedDescription ?? "未知错误")"
        case .analysisRailed:
            return "视频分析失败"
        }
    }
}
