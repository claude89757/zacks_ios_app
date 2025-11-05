//
//  VideoAnalysisProtocols.swift
//  zacks_tennis
//
//  协议抽象 - 支持依赖注入和单元测试
//  Created for Phase 3 Quality Improvements
//

import Foundation
import AVFoundation
import CoreVideo

// MARK: - Vision Analysis Protocol

/// 帧分析协议 - 抽象 Vision Framework 实现
protocol FrameAnalyzing: Actor {
    /// 分析单帧图像
    /// - Parameters:
    ///   - pixelBuffer: 像素缓冲区
    ///   - timestamp: 时间戳（秒）
    /// - Returns: 帧分析结果
    func analyzeFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) async throws -> FrameAnalysisResult

    /// 重置分析器状态
    func reset() async
}

// MARK: - Ball Tracking Protocol

/// 网球追踪协议 - 抽象网球检测和追踪实现
protocol BallTracking: Actor {
    /// 分析单帧图像，检测网球
    /// - Parameters:
    ///   - pixelBuffer: 像素缓冲区
    ///   - timestamp: 时间戳（秒）
    /// - Returns: 网球分析结果
    func analyze(pixelBuffer: CVPixelBuffer, timestamp: Double) async -> BallAnalysisResult

    /// 批量分析多帧（优化性能）
    /// - Parameter frames: 帧数组（pixel buffer 和时间戳）
    /// - Returns: 批量分析结果
    func analyzeBatch(frames: [(CVPixelBuffer, Double)]) async -> [BallAnalysisResult]

    /// 获取性能统计信息
    /// - Returns: (已处理帧数, 总检测次数, 平均每帧检测数)
    func getStatistics() async -> (framesProcessed: Int, totalDetections: Int, avgDetectionsPerFrame: Double)

    /// 重置统计信息
    func resetStatistics()
}

// MARK: - Audio Analysis Protocol

/// 音频分析协议 - 抽象音频处理实现
protocol AudioAnalyzing: Actor {
    /// 分析音频轨道
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - timeRange: 时间范围
    /// - Returns: 音频分析结果
    func analyzeAudio(from asset: AVAsset, timeRange: CMTimeRange) async throws -> AudioAnalysisResult

    /// 更新音频分析配置
    /// - Parameter newConfig: 新配置
    func updateConfig(_ newConfig: AudioAnalysisConfiguration) async

    /// 启用音频诊断模式
    /// - Parameter videoInfo: 视频诊断信息
    func enableDiagnosticMode(videoInfo: VideoDiagnosticInfo) async

    /// 禁用音频诊断模式
    func disableDiagnosticMode() async

    /// 获取诊断数据
    /// - Returns: 音频诊断数据，如果未启用诊断模式则返回 nil
    func getDiagnosticData() async -> AudioDiagnosticData?
}

// MARK: - Ball Visualization Protocol

/// 网球可视化协议 - 抽象可视化绘制实现
protocol BallVisualizing: Actor {
    /// 在视频帧上绘制网球检测结果
    /// - Parameters:
    ///   - pixelBuffer: 原始视频帧
    ///   - result: 网球分析结果
    ///   - audioEvents: 可选的音频事件时间点
    /// - Returns: 带标注的新 pixel buffer
    func visualize(
        pixelBuffer: CVPixelBuffer,
        result: BallAnalysisResult,
        audioEvents: [Double]?
    ) async -> CVPixelBuffer?

    /// 批量可视化多帧
    /// - Parameters:
    ///   - frames: 帧数组（pixel buffer 和分析结果）
    ///   - audioEvents: 可选的音频事件时间点
    /// - Returns: 带标注的帧数组
    func visualizeBatch(
        frames: [(CVPixelBuffer, BallAnalysisResult)],
        audioEvents: [Double]?
    ) async -> [CVPixelBuffer]

    /// 获取统计信息
    /// - Returns: 已可视化的帧数
    func getStatistics() async -> Int
}

// MARK: - Rally Detection Protocol

/// 回合检测协议 - 抽象回合检测逻辑
protocol RallyDetecting: Actor {
    /// 处理单个帧的分析结果
    /// - Parameters:
    ///   - frame: 帧分析结果
    ///   - audioResult: 音频分析结果
    /// - Returns: 如果检测到完整回合则返回，否则返回 nil
    func processFrame(_ frame: FrameAnalysisResult, audioResult: AudioAnalysisResult) async -> VideoHighlight?

    /// 完成处理并返回所有回合
    /// - Returns: 所有检测到的回合
    func finalize() async -> [VideoHighlight]

    /// 重置检测器状态
    func reset() async
}

// MARK: - Processing State Management Protocol

/// 处理状态管理协议 - 抽象状态持久化
protocol ProcessingStateManaging: AnyObject {
    /// 创建新的处理状态
    /// - Parameters:
    ///   - videoID: 视频ID
    ///   - totalDuration: 总时长
    /// - Returns: 新创建的状态
    func createState(for videoID: UUID, totalDuration: Double) -> ProcessingState

    /// 更新处理状态
    /// - Parameters:
    ///   - videoID: 视频ID
    ///   - update: 更新闭包
    func updateState(for videoID: UUID, update: (inout ProcessingState) -> Void)

    /// 获取处理状态
    /// - Parameter videoID: 视频ID
    /// - Returns: 处理状态，如果不存在则返回 nil
    func getState(for videoID: UUID) -> ProcessingState?

    /// 移除处理状态
    /// - Parameter videoID: 视频ID
    func removeState(for videoID: UUID)

    /// 清理过期状态
    func cleanupExpiredStates()
}

// MARK: - Memory Monitoring Protocol

/// 内存监控协议 - 抽象内存监控实现
protocol MemoryMonitoring: AnyObject {
    /// 当前内存使用（MB）
    var currentMemoryUsage: Double { get }

    /// 内存压力级别
    var pressureLevel: MemoryPressureLevel { get }

    /// 开始监控
    func startMonitoring()

    /// 停止监控
    func stopMonitoring()

    /// 触发清理
    func triggerCleanup()
}

// MARK: - Video Processing Protocol

/// 视频处理引擎协议 - 抽象完整处理流程
@MainActor
protocol VideoProcessing: AnyObject {
    /// 进度更新回调
    var onProgressUpdate: ((ProcessingProgress) -> Void)? { get set }

    /// 回合检测回调（实时流式）
    var onRallyDetected: ((VideoHighlight) -> Void)? { get set }

    /// 处理视频
    /// - Parameter video: 视频对象
    /// - Returns: 检测到的所有回合
    func processVideo(_ video: Video) async throws -> [VideoHighlight]

    /// 取消处理
    func cancelProcessing() async
}

// MARK: - Default Implementations

extension ProcessingStateManaging {
    /// 默认实现：清理过期状态（委托给 ProcessingStateManager）
    func cleanupExpiredStates() {
        // 子类可以覆盖此实现
    }
}

// MARK: - 注意
// ProcessingProgress 已在 VideoProcessingEngine.swift 中定义
// MemoryPressureLevel 已在 MemoryMonitor.swift 中定义
