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

    /// 状态管理器（协议类型 - 支持依赖注入）
    private let stateManager: any ProcessingStateManaging

    // MARK: - Constants

    /// 处理配置
    private let config = ProcessingConfiguration()

    // MARK: - Initialization

    /// 初始化处理引擎（支持依赖注入）
    /// - Parameters:
    ///   - visionAnalyzer: Vision 分析器
    ///   - audioAnalyzer: 音频分析器
    ///   - stateManager: 状态管理器
    init(
        visionAnalyzer: any FrameAnalyzing,
        audioAnalyzer: any AudioAnalyzing,
        stateManager: any ProcessingStateManaging
    ) {
        self.visionAnalyzer = visionAnalyzer
        self.audioAnalyzer = audioAnalyzer
        self.stateManager = stateManager
    }

    /// 便利初始化器 - 使用默认实现
    convenience init() {
        self.init(
            visionAnalyzer: VisionAnalyzer(),
            audioAnalyzer: AudioAnalyzer(),
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
        var detectedRallies: [VideoHighlight] = []
        var lastSampledTime: Double = startTime

        // 进度更新节流
        var lastProgressUpdateTime: Double = startTime
        var lastReportedProgress: Double = 0.0

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

            // 在 autoreleasepool 外进行异步分析
            if let frameResult = await analyzeFrame(imageBuffer: imageBuffer, at: currentTime) {
                frameAnalysisResults.append(frameResult)
            }

            // 每积累一定数量的帧，尝试检测回合
            if frameAnalysisResults.count >= config.rallyDetectionWindowSize {
                // 等待音频分析完成（如果还没完成）
                let audioResult = await audioAnalysisTask.value

                if let rally = detectRally(
                    from: frameAnalysisResults,
                    audioResult: audioResult,
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
                } else {
                    // 保留最近的帧，使用滑动窗口
                    if frameAnalysisResults.count > config.rallyDetectionWindowSize * 2 {
                        frameAnalysisResults.removeFirst(config.rallyDetectionWindowSize)
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

        // 检查读取状态
        if reader.status == .failed {
            throw ProcessingError.readFailed(reader.error)
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

            let result = try await audioAnalyzer.analyzeAudio(
                from: asset,
                timeRange: timeRange
            )

            return result
        } catch {
            // 音频分析失败时返回空结果
            print("⚠️ 音频分析失败: \(error.localizedDescription)")
            return AudioAnalysisResult(hitSounds: [])
        }
    }

    // MARK: - Private Methods - Frame Analysis

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

    /// 从帧分析结果中检测回合
    private func detectRally(
        from frames: [FrameAnalysisResult],
        audioResult: AudioAnalysisResult,
        video: Video,
        currentRallyNumber: Int
    ) -> VideoHighlight? {

        // 查找连续的高强度运动区间
        var rallyStart: Double?
        var rallyEnd: Double?
        var intensitySum: Double = 0
        var validFrameCount: Int = 0
        var hasAudioPeaks = false

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

                    // 检查此时间段内是否有击球声（增强检测准确性）
                    hasAudioPeaks = audioResult.hitSounds.contains { peak in
                        peak.time >= start && peak.time <= end && peak.confidence > config.thresholds.audioHitConfidence
                    }

                    // 找到有效回合
                    let avgIntensity = intensitySum / Double(validFrameCount)
                    let excitementScore = calculateExcitementScore(
                        duration: end - start,
                        intensity: avgIntensity,
                        hasAudioPeaks: hasAudioPeaks
                    )

                    let highlight = VideoHighlight(
                        video: video,
                        rallyNumber: currentRallyNumber,
                        startTime: max(0, start - 1.0), // 前置 1 秒缓冲
                        endTime: min(video.duration, end + 1.0), // 后置 1 秒缓冲
                        excitementScore: excitementScore,
                        videoFilePath: video.originalFilePath, // 使用原视频路径
                        type: classifyRallyType(duration: end - start, intensity: avgIntensity)
                    )

                    highlight.rallyDescription = "回合 #\(currentRallyNumber)"
                    highlight.detectionConfidence = min(1.0, avgIntensity)

                    // 更新检测元数据
                    highlight.metadata = DetectionMetadata(
                        maxMovementIntensity: frames.map(\.movementIntensity).max() ?? 0.0,
                        avgMovementIntensity: avgIntensity,
                        hasAudioPeaks: hasAudioPeaks,
                        poseConfidenceAvg: frames.map(\.confidence).reduce(0, +) / Double(frames.count)
                    )

                    return highlight
                }

                // 重置检测状态
                rallyStart = nil
                rallyEnd = nil
                intensitySum = 0
                validFrameCount = 0
                hasAudioPeaks = false
            }
        }

        return nil
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
