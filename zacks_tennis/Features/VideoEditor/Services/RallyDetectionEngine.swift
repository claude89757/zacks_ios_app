//
//  RallyDetectionEngine.swift
//  zacks_tennis
//
//  回合检测引擎 - 复杂规则引擎
//  使用状态机模式和多特征融合进行精确的回合检测
//

import Foundation

/// 回合检测引擎 - 负责综合多种特征进行回合检测
actor RallyDetectionEngine {

    // MARK: - Properties

    /// 检测配置
    private let config: RallyDetectionConfiguration

    /// 当前检测状态
    private var currentState: DetectionState = .idle

    /// 当前正在构建的回合
    private var currentRally: RallyBuilder?

    /// 最后检测时间（用于检测间隔）
    private var lastActivityTime: Double = 0

    // MARK: - Initialization

    init(config: RallyDetectionConfiguration = .default) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 处理单帧分析结果，增量式更新检测状态
    /// - Parameters:
    ///   - frame: 帧分析结果
    ///   - audioResult: 音频分析结果（整个时间段）
    /// - Returns: 如果检测到完整回合，返回 Rally；否则返回 nil
    func processFrame(
        _ frame: FrameAnalysisResult,
        audioResult: AudioAnalysisResult
    ) -> Rally? {

        // 1. 根据当前状态和帧特征，决定状态转移
        let previousState = currentState
        updateState(with: frame)

        // 2. 根据状态转移处理逻辑
        switch (previousState, currentState) {

        case (.idle, .rallying):
            // 开始新回合
            startNewRally(at: frame.timestamp)

        case (.rallying, .rallying):
            // 回合进行中，累积特征
            updateCurrentRally(with: frame)

        case (.rallying, .pausing):
            // 回合暂停（短暂低强度）
            break

        case (.pausing, .rallying):
            // 从暂停恢复到回合
            updateCurrentRally(with: frame)

        case (.rallying, .idle), (.pausing, .idle):
            // 回合结束
            if let rally = finishCurrentRally(audioResult: audioResult) {
                return rally
            }

        default:
            break
        }

        // 3. 检查超时（长时间暂停自动结束回合）
        if currentState == .pausing,
           frame.timestamp - lastActivityTime > config.maxPauseDuration {
            currentState = .idle
            if let rally = finishCurrentRally(audioResult: audioResult) {
                return rally
            }
        }

        return nil
    }

    /// 批量处理多帧，返回检测到的所有回合
    /// - Parameters:
    ///   - frames: 帧分析结果数组
    ///   - audioResult: 音频分析结果
    /// - Returns: 检测到的回合数组
    func processFrames(
        _ frames: [FrameAnalysisResult],
        audioResult: AudioAnalysisResult
    ) -> [Rally] {
        var rallies: [Rally] = []

        for frame in frames {
            if let rally = processFrame(frame, audioResult: audioResult) {
                rallies.append(rally)
            }
        }

        // 处理完所有帧后，如果还有未完成的回合，强制完成
        if let lastRally = forceFinishCurrentRally(audioResult: audioResult) {
            rallies.append(lastRally)
        }

        return rallies
    }

    /// 重置检测引擎状态（用于处理新视频）
    func reset() {
        currentState = .idle
        currentRally = nil
        lastActivityTime = 0
    }

    // MARK: - Private Methods - State Management

    /// 根据帧特征更新状态机
    private func updateState(with frame: FrameAnalysisResult) {

        let isActive = isFrameActive(frame)

        switch currentState {
        case .idle:
            if isActive {
                currentState = .rallying
                lastActivityTime = frame.timestamp
            }

        case .rallying:
            if isActive {
                lastActivityTime = frame.timestamp
            } else {
                // 检测到低强度帧，进入暂停状态
                currentState = .pausing
            }

        case .pausing:
            if isActive {
                // 从暂停恢复
                currentState = .rallying
                lastActivityTime = frame.timestamp
            } else if frame.timestamp - lastActivityTime > config.maxPauseDuration {
                // 暂停时间过长，结束回合
                currentState = .idle
            }
        }
    }

    /// 判断帧是否为活跃帧（运动强度足够高）
    private func isFrameActive(_ frame: FrameAnalysisResult) -> Bool {
        // 多条件判断
        let hasMovement = frame.movementIntensity > config.movementThreshold
        let hasPerson = frame.hasPerson && frame.confidence > config.confidenceThreshold

        return hasMovement && hasPerson
    }

    // MARK: - Private Methods - Rally Building

    /// 开始构建新回合
    private func startNewRally(at timestamp: Double) {
        currentRally = RallyBuilder(startTime: timestamp)
    }

    /// 更新当前回合的特征
    private func updateCurrentRally(with frame: FrameAnalysisResult) {
        guard let builder = currentRally else { return }

        builder.addFrame(frame)
        currentRally = builder
    }

    /// 完成当前回合
    private func finishCurrentRally(audioResult: AudioAnalysisResult) -> Rally? {
        guard let builder = currentRally else { return nil }

        // 检查回合是否有效（时长足够）
        guard builder.duration >= config.minRallyDuration else {
            currentRally = nil
            return nil
        }

        // 构建 Rally 对象
        let rally = builder.build(audioResult: audioResult, config: config)

        // 重置
        currentRally = nil

        return rally
    }

    /// 强制完成当前回合（用于批处理结束时）
    private func forceFinishCurrentRally(audioResult: AudioAnalysisResult) -> Rally? {
        guard currentRally != nil else { return nil }

        return finishCurrentRally(audioResult: audioResult)
    }
}

// MARK: - Supporting Types

/// 检测状态机
enum DetectionState {
    case idle       // 空闲状态（无活动）
    case rallying   // 回合进行中
    case pausing    // 短暂暂停（回合内的短暂低强度）
}

/// 回合构建器 - 累积回合特征
class RallyBuilder {
    /// 开始时间
    let startTime: Double

    /// 结束时间（不断更新）
    var endTime: Double

    /// 累积的帧数
    var frameCount: Int = 0

    /// 运动强度总和
    var intensitySum: Double = 0

    /// 最大运动强度
    var maxIntensity: Double = 0

    /// 姿态检测置信度总和
    var confidenceSum: Double = 0

    /// 所有帧的时间戳（用于检测连续性）
    var frameTimestamps: [Double] = []

    init(startTime: Double) {
        self.startTime = startTime
        self.endTime = startTime
    }

    /// 添加帧
    func addFrame(_ frame: FrameAnalysisResult) {
        endTime = frame.timestamp
        frameCount += 1
        intensitySum += frame.movementIntensity
        maxIntensity = max(maxIntensity, frame.movementIntensity)
        confidenceSum += frame.confidence
        frameTimestamps.append(frame.timestamp)
    }

    /// 时长
    var duration: Double {
        endTime - startTime
    }

    /// 平均运动强度
    var avgIntensity: Double {
        frameCount > 0 ? intensitySum / Double(frameCount) : 0
    }

    /// 平均置信度
    var avgConfidence: Double {
        frameCount > 0 ? confidenceSum / Double(frameCount) : 0
    }

    /// 构建 Rally 对象
    func build(audioResult: AudioAnalysisResult, config: RallyDetectionConfiguration) -> Rally {

        // 检查音频峰值
        let hasAudioPeaks = audioResult.hitSounds.contains { peak in
            peak.time >= startTime && peak.time <= endTime && peak.confidence > config.audioConfidenceThreshold
        }

        // 估计击球次数（基于音频峰值数量）
        let hitCount = audioResult.hitSounds.filter { peak in
            peak.time >= startTime && peak.time <= endTime && peak.confidence > config.audioConfidenceThreshold
        }.count

        // 创建元数据
        let metadata = DetectionMetadata(
            maxMovementIntensity: maxIntensity,
            avgMovementIntensity: avgIntensity,
            hasAudioPeaks: hasAudioPeaks,
            poseConfidenceAvg: avgConfidence,
            estimatedHitCount: hitCount > 0 ? hitCount : nil,
            playerCount: nil // TODO: 后续可以基于姿态检测数量估计
        )

        // 创建 Rally 并设置属性
        var rally = Rally(startTime: startTime)
        rally.endTime = endTime
        rally.metadata = metadata

        return rally
    }
}

/// 回合检测配置
struct RallyDetectionConfiguration {
    /// 运动强度阈值
    let movementThreshold: Double

    /// 姿态检测置信度阈值
    let confidenceThreshold: Double

    /// 最小回合时长（秒）
    let minRallyDuration: Double

    /// 最大暂停时长（秒）- 超过此时长回合结束
    let maxPauseDuration: Double

    /// 音频击球声置信度阈值
    let audioConfidenceThreshold: Double

    /// 默认配置
    static let `default` = RallyDetectionConfiguration(
        movementThreshold: 0.4,
        confidenceThreshold: 0.5,
        minRallyDuration: 3.0,
        maxPauseDuration: 2.0,
        audioConfidenceThreshold: 0.6
    )

    /// 严格配置（减少误报，适用于嘈杂环境）
    static let strict = RallyDetectionConfiguration(
        movementThreshold: 0.5,
        confidenceThreshold: 0.6,
        minRallyDuration: 4.0,
        maxPauseDuration: 1.5,
        audioConfidenceThreshold: 0.7
    )

    /// 宽松配置（提高召回率，适用于低质量视频）
    static let lenient = RallyDetectionConfiguration(
        movementThreshold: 0.3,
        confidenceThreshold: 0.4,
        minRallyDuration: 2.0,
        maxPauseDuration: 2.5,
        audioConfidenceThreshold: 0.5
    )
}

/// 检测引擎错误
enum RallyDetectionError: LocalizedError {
    case invalidConfiguration
    case noFramesProvided

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "检测配置无效"
        case .noFramesProvided:
            return "未提供帧数据"
        }
    }
}
