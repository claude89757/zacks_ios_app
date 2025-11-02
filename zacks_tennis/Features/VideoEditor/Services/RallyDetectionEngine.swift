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

    // MARK: - Legacy Visual State (temporarily disabled)
    // private var currentState: DetectionState = .idle
    // private var currentRally: RallyBuilder?
    // private var lastActivityTime: Double = 0

    // MARK: - Initialization

    init(config: RallyDetectionConfiguration = .default) {
        self.config = config
        // 临时启用调试日志以便排查问题
        if config.enableDebugLogging {
            print("🔍 [RallyDetection] 初始化，配置: 置信度阈值=\(config.audioConfidenceThreshold), 最小击球数=\(config.minHitCount), 最大间隔=\(config.maxHitInterval)s")
        }
    }

    // MARK: - Public Methods

    /// 处理单帧分析结果，增量式更新检测状态
    /// - Parameters:
    ///   - frame: 帧分析结果
    ///   - audioResult: 音频分析结果（整个时间段）
    ///   - ballResult: 网球分析结果（可选，优先使用）
    /// - Returns: 如果检测到完整回合，返回 Rally；否则返回 nil
    func processFrame(
        _ frame: FrameAnalysisResult,
        audioResult: AudioAnalysisResult,
        ballResult: BallAnalysisResult? = nil
    ) -> Rally? {
        // 视觉检测管线暂时停用，增量回合同步输出不再支持
        // 仅依赖音频峰值聚类的方案请使用 processFrames 或 detectRalliesUsingAudio(audioResult:)
        return nil
    }

    /// 批量处理多帧，返回检测到的所有回合
    /// - Parameters:
    ///   - frames: 帧分析结果数组
    ///   - audioResult: 音频分析结果
    ///   - ballResults: 网球分析结果数组（可选，与frames一一对应）
    /// - Returns: 检测到的回合数组
    func processFrames(
        _ frames: [FrameAnalysisResult],
        audioResult: AudioAnalysisResult,
        ballResults: [BallAnalysisResult]? = nil
    ) -> [Rally] {
        // 视觉检测暂时下线，直接根据音频击球声聚类生成回合
        return detectRalliesUsingAudio(audioResult: audioResult)
    }

    /// 基于音频分析结果直接生成回合（批处理场景）
    func detectRallies(audioResult: AudioAnalysisResult) -> [Rally] {
        return detectRalliesUsingAudio(audioResult: audioResult)
    }

    /// 重置检测引擎状态（用于处理新视频）
    func reset() {
        // 音频模式无需重置视觉状态
    }

    // MARK: - Audio-Only Detection

    private func detectRalliesUsingAudio(audioResult: AudioAnalysisResult) -> [Rally] {
        // 临时启用调试日志（仅在峰值数量较少时输出详细信息）
        let debugLogging = true
        let detailedLogging = audioResult.hitSounds.count < 100 // 峰值少时才详细日志
        
        let peaks = audioResult.hitSounds
            .filter { $0.confidence >= config.audioConfidenceThreshold }
            .sorted { $0.time < $1.time }

        guard !peaks.isEmpty else {
            if debugLogging {
                print("🔍 [RallyDetection] 未检测到音频峰值（原始峰值数: \(audioResult.hitSounds.count), 阈值: \(config.audioConfidenceThreshold)）")
                if !audioResult.hitSounds.isEmpty && detailedLogging {
                    let confidences = audioResult.hitSounds.map { $0.confidence }
                    print("🔍 [RallyDetection] 原始峰值置信度范围: \(String(format: "%.2f", confidences.min() ?? 0)) - \(String(format: "%.2f", confidences.max() ?? 0))")
                }
            }
            return []
        }

        if debugLogging {
            print("🔍 [RallyDetection] 检测到 \(peaks.count) 个音频峰值（置信度 >= \(config.audioConfidenceThreshold)）")
            if detailedLogging {
                print("🔍 [RallyDetection] 峰值时间范围: \(String(format: "%.2f", peaks.first!.time))s - \(String(format: "%.2f", peaks.last!.time))s")
            }
        }

        // 自适应阈值：根据音频质量调整
        let adaptiveThreshold = calculateAdaptiveThreshold(peaks: peaks)
        let filteredPeaks = peaks.filter { $0.confidence >= adaptiveThreshold }

        if debugLogging {
            print("🔍 [RallyDetection] 自适应阈值: \(String(format: "%.2f", adaptiveThreshold)), 过滤后: \(filteredPeaks.count) 个峰值")
        }

        guard !filteredPeaks.isEmpty else {
            // 如果自适应阈值过滤后没有峰值，使用原始阈值
            if debugLogging {
                print("🔍 [RallyDetection] 自适应阈值过滤后无峰值，使用简单聚类（降级方案）")
            }
            return detectRalliesWithSimpleClustering(peaks: peaks)
        }

        // 使用改进的时序聚类
        let clusters = performImprovedTemporalClustering(peaks: filteredPeaks)
        
        if debugLogging {
            print("🔍 [RallyDetection] 时序聚类结果: \(clusters.count) 个簇")
            if detailedLogging {
                for (index, cluster) in clusters.enumerated() {
                    print("🔍 [RallyDetection] 簇 #\(index + 1): \(cluster.count) 个峰值，时间: \(String(format: "%.2f", cluster.first!.time))s - \(String(format: "%.2f", cluster.last!.time))s")
                }
            }
        }

        // 构建回合并过滤误报
        var rallies: [Rally] = []
        for (index, cluster) in clusters.enumerated() {
            if let rally = buildAudioRally(from: cluster) {
                if debugLogging && detailedLogging {
                    print("🔍 [RallyDetection] 簇 #\(index + 1) 构建回合成功: \(String(format: "%.2f", rally.startTime))s - \(String(format: "%.2f", rally.endTime))s, 时长: \(String(format: "%.2f", rally.duration))s")
                }
                // 验证回合合理性
                if isValidRally(rally: rally, cluster: cluster) {
                    if debugLogging {
                        print("✅ [RallyDetection] 回合 #\(index + 1): \(String(format: "%.2f", rally.startTime))s - \(String(format: "%.2f", rally.endTime))s (\(cluster.count) 次击球)")
                    }
                    rallies.append(rally)
                } else {
                    if debugLogging && detailedLogging {
                        let intervals = cluster.count > 1 ? zip(cluster.dropFirst(), cluster).map { $0.time - $1.time } : []
                        let avgInterval = intervals.isEmpty ? 0.0 : intervals.reduce(0, +) / Double(intervals.count)
                        let hitDensity = Double(cluster.count) / rally.duration
                        print("❌ [RallyDetection] 回合 #\(index + 1) 未通过验证:")
                        print("   - 时长: \(String(format: "%.2f", rally.duration))s (要求: >= \(config.minRallyDuration)s)")
                        print("   - 击球数: \(cluster.count) (要求: >= \(config.minHitCount))")
                        if !intervals.isEmpty {
                            print("   - 平均间隔: \(String(format: "%.2f", avgInterval))s (要求: 0.2-3.0s)")
                            print("   - 最大间隔: \(String(format: "%.2f", intervals.max() ?? 0))s")
                        }
                        print("   - 击球密度: \(String(format: "%.2f", hitDensity)) (要求: >= 0.33)")
                    }
                }
            } else {
                if debugLogging && detailedLogging {
                    print("❌ [RallyDetection] 簇 #\(index + 1) 构建回合失败")
                }
            }
        }

        if debugLogging {
            print("🎾 [RallyDetection] 最终检测到 \(rallies.count) 个有效回合")
        }

        return rallies
    }

    /// 计算自适应阈值（根据音频质量动态调整）
    private func calculateAdaptiveThreshold(peaks: [AudioPeak]) -> Double {
        guard !peaks.isEmpty else { return config.audioConfidenceThreshold }
        
        // 计算峰值置信度的统计信息
        let confidences = peaks.map { $0.confidence }
        let avgConfidence = confidences.reduce(0, +) / Double(confidences.count)
        let maxConfidence = confidences.max() ?? 0.0
        
        // 如果平均置信度较低，降低阈值以提高召回率
        // 如果平均置信度较高，提高阈值以减少误报
        if avgConfidence < 0.5 {
            // 音频质量较差，使用更宽松的阈值
            return max(config.audioConfidenceThreshold * 0.8, 0.4)
        } else if avgConfidence > 0.7 && maxConfidence > 0.8 {
            // 音频质量很好，可以使用更严格的阈值
            return min(config.audioConfidenceThreshold * 1.2, 0.8)
        }
        
        return config.audioConfidenceThreshold
    }

    /// 改进的时序聚类（考虑峰值间隔和密度）
    private func performImprovedTemporalClustering(peaks: [AudioPeak]) -> [[AudioPeak]] {
        guard !peaks.isEmpty else { return [] }
        
        var clusters: [[AudioPeak]] = []
        var currentCluster: [AudioPeak] = [peaks[0]]
        
        for i in 1..<peaks.count {
            let currentPeak = peaks[i]
            let previousPeak = peaks[i-1]
            let timeInterval = currentPeak.time - previousPeak.time
            
            // 动态间隔判断：根据击球间隔是否合理
            let shouldCluster = shouldClusterPeaks(
                previous: previousPeak,
                current: currentPeak,
                defaultInterval: config.maxHitInterval
            )
            
            if shouldCluster {
                currentCluster.append(currentPeak)
            } else {
                // 保存当前簇，开始新簇
                if currentCluster.count >= config.minHitCount {
                    clusters.append(currentCluster)
                }
                currentCluster = [currentPeak]
            }
        }
        
        // 保存最后一个簇
        if currentCluster.count >= config.minHitCount {
            clusters.append(currentCluster)
        }
        
        return clusters
    }

    /// 判断两个峰值是否应该聚为一簇
    private func shouldClusterPeaks(
        previous: AudioPeak,
        current: AudioPeak,
        defaultInterval: Double
    ) -> Bool {
        let timeInterval = current.time - previous.time
        
        // 基本间隔检查
        if timeInterval > defaultInterval {
            return false
        }
        
        // 如果间隔很短（<0.3秒），可能是同一击球的不同峰值，应该合并
        if timeInterval < 0.3 {
            return true
        }
        
        // 如果两个峰值置信度都很高，且间隔合理，应该聚为一簇
        if previous.confidence > 0.7 && current.confidence > 0.7 {
            return timeInterval <= defaultInterval * 1.2
        }
        
        // 默认使用配置的间隔
        return timeInterval <= defaultInterval
    }

    /// 简单聚类（降级方案）
    private func detectRalliesWithSimpleClustering(peaks: [AudioPeak]) -> [Rally] {
        var rallies: [Rally] = []
        var currentCluster: [AudioPeak] = []

        for peak in peaks {
            if let last = currentCluster.last, peak.time - last.time <= config.maxHitInterval {
                currentCluster.append(peak)
            } else {
                if let rally = buildAudioRally(from: currentCluster) {
                    rallies.append(rally)
                }
                currentCluster = [peak]
            }
        }

        if let rally = buildAudioRally(from: currentCluster) {
            rallies.append(rally)
        }

        return rallies
    }

    /// 验证回合合理性（过滤误报）
    private func isValidRally(rally: Rally, cluster: [AudioPeak]) -> Bool {
        // 1. 时长检查
        guard rally.duration >= config.minRallyDuration else { return false }
        
        // 2. 击球次数检查
        guard cluster.count >= config.minHitCount else { return false }
        
        // 3. 击球间隔合理性检查
        if cluster.count > 1 {
            let intervals = zip(cluster.dropFirst(), cluster).map { $0.time - $1.time }
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            
            // 平均击球间隔应该在合理范围内（0.2秒到3.0秒，放宽范围）
            guard avgInterval >= 0.2 && avgInterval <= 3.0 else { return false }
            
            // 检查是否有异常长的间隔（可能是误检）
            // 放宽条件：允许有1个间隔超过阈值（可能是回合中的暂停）
            let longIntervals = intervals.filter { $0 > config.maxHitInterval * 2 }
            if longIntervals.count > 1 {
                return false
            }
        }
        
        // 4. 击球密度检查（回合内击球应该相对密集）
        // 放宽条件：至少每3秒一次击球（而不是每2秒）
        let hitDensity = Double(cluster.count) / rally.duration
        guard hitDensity >= 0.33 else { return false } // 至少每3秒一次击球
        
        return true
    }

    private func buildAudioRally(from cluster: [AudioPeak]) -> Rally? {
        guard let first = cluster.first, let last = cluster.last else { return nil }
        guard cluster.count >= config.minHitCount else { return nil }

        let startTime = max(0.0, first.time - config.preHitPadding)
        let endTime = last.time + config.postHitPadding

        guard endTime - startTime >= config.minRallyDuration else { return nil }

        // 计算平均置信度
        let avgConfidence = cluster.map { $0.confidence }.reduce(0, +) / Double(cluster.count)
        
        // 计算击球间隔统计
        var intervals: [Double] = []
        if cluster.count > 1 {
            intervals = zip(cluster.dropFirst(), cluster).map { $0.time - $1.time }
        }
        let avgInterval = intervals.isEmpty ? 0.0 : intervals.reduce(0, +) / Double(intervals.count)

        var rally = Rally(startTime: startTime)
        rally.endTime = endTime
        rally.metadata = DetectionMetadata(
            maxMovementIntensity: 0.0,
            avgMovementIntensity: 0.0,
            hasAudioPeaks: true,
            poseConfidenceAvg: avgConfidence,
            estimatedHitCount: cluster.count,
            playerCount: nil,
            audioPeakTimestamps: cluster.map { $0.time }  // 保存音频峰值时间点
        )

        return rally
    }
}

    // MARK: - Legacy Visual Pipeline (temporarily disabled)
    /*
    // MARK: - Private Methods - State Management

    /// 根据帧特征更新状态机
    private func updateState(with frame: FrameAnalysisResult, ballResult: BallAnalysisResult?) {

        let isActive = isFrameActive(frame, ballResult: ballResult)

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
    /// 优先使用网球检测，降级使用人体姿态检测
    private func isFrameActive(_ frame: FrameAnalysisResult, ballResult: BallAnalysisResult?) -> Bool {

        var ballIndicatesActivity = false

        if let ballResult = ballResult {
            // 网球检测逻辑：
            // 1. 检测到网球
            // 2. 网球置信度足够高
            // 3. 网球在移动（速度超过阈值）
            if let primaryBall = ballResult.primaryBall {
                let hasBall = ballResult.hasBall
                let ballConfidenceOK = primaryBall.confidence > config.confidenceThreshold
                let ballIsMoving = primaryBall.isMoving(threshold: config.ballVelocityThreshold)

                ballIndicatesActivity = hasBall && ballConfidenceOK && ballIsMoving
            }

            // 如果主要网球不满足条件，检查其他检测结果是否有移动
            if !ballIndicatesActivity && ballResult.hasBall {
                ballIndicatesActivity = ballResult.detections.contains { detection in
                    detection.confidence > config.confidenceThreshold &&
                    detection.isMoving(threshold: config.ballVelocityThreshold)
                }
            }
        }

        // 降级策略：使用人体姿态检测（兼容旧逻辑）
        let poseIndicatesActivity = frame.movementIntensity > config.movementThreshold &&
            frame.hasPerson && frame.confidence > config.confidenceThreshold

        return ballIndicatesActivity || poseIndicatesActivity
    }

    // MARK: - Private Methods - Rally Building

    /// 开始构建新回合
    private func startNewRally(at timestamp: Double) {
        currentRally = RallyBuilder(startTime: timestamp)
    }

    /// 更新当前回合的特征
    private func updateCurrentRally(with frame: FrameAnalysisResult, ballResult: BallAnalysisResult?) {
        guard let builder = currentRally else { return }

        builder.addFrame(frame, ballResult: ballResult)
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
enum DetectionState: Sendable {
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

    // 网球轨迹数据
    var ballTrajectoryPoints: [BallTrajectoryPoint] = []
    var ballDetectionCount: Int = 0
    var ballConfidenceSum: Double = 0
    var maxBallVelocity: Double = 0
    var totalBallDistance: Double = 0
    var lastBallPosition: CGPoint?

    init(startTime: Double) {
        self.startTime = startTime
        self.endTime = startTime
    }

    /// 添加帧
    func addFrame(_ frame: FrameAnalysisResult, ballResult: BallAnalysisResult? = nil) {
        endTime = frame.timestamp
        frameCount += 1
        intensitySum += frame.movementIntensity
        maxIntensity = max(maxIntensity, frame.movementIntensity)
        confidenceSum += frame.confidence
        frameTimestamps.append(frame.timestamp)

        // 添加网球轨迹数据
        if let ballResult = ballResult, let primaryBall = ballResult.primaryBall {
            ballDetectionCount += 1
            ballConfidenceSum += primaryBall.confidence

            // 记录轨迹点
            let trajectoryPoint = BallTrajectoryPoint(
                timestamp: primaryBall.timestamp,
                position: CodablePoint(primaryBall.center),
                velocity: CodableVector(primaryBall.velocity),
                confidence: primaryBall.confidence
            )
            ballTrajectoryPoints.append(trajectoryPoint)

            // 更新最大速度
            maxBallVelocity = max(maxBallVelocity, primaryBall.movementMagnitude)

            // 计算累积距离
            if let lastPos = lastBallPosition {
                let dx = primaryBall.center.x - lastPos.x
                let dy = primaryBall.center.y - lastPos.y
                totalBallDistance += sqrt(dx * dx + dy * dy)
            }
            lastBallPosition = primaryBall.center
        }
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

    /// 平均网球检测置信度
    var avgBallConfidence: Double {
        ballDetectionCount > 0 ? ballConfidenceSum / Double(ballDetectionCount) : 0
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

        // 创建网球轨迹数据（如果有）
        let ballTrajectory: BallTrajectoryData? = ballDetectionCount > 0 ? BallTrajectoryData(
            trajectoryPoints: ballTrajectoryPoints,
            detectionCount: ballDetectionCount,
            avgConfidence: avgBallConfidence,
            maxVelocity: maxBallVelocity,
            avgVelocity: ballDetectionCount > 0 ? ballTrajectoryPoints.map { $0.velocity.magnitude }.reduce(0, +) / Double(ballDetectionCount) : 0,
            totalDistance: totalBallDistance
        ) : nil

        // 创建 Rally 并设置属性
        var rally = Rally(startTime: startTime)
        rally.endTime = endTime
        rally.metadata = metadata
        rally.ballTrajectory = ballTrajectory

        return rally
    }
}

    */
/// 回合检测配置
struct RallyDetectionConfiguration {
    // MARK: - 音频密集度判断参数

    /// 最小回合时长（秒）
    let minRallyDuration: Double

    /// 音频击球声置信度阈值
    let audioConfidenceThreshold: Double

    /// 判定为同一回合的最大相邻击球间隔（秒）
    let maxHitInterval: Double

    /// 构成有效回合所需的最少击球次数
    let minHitCount: Int

    /// 截取回合片段时在首个击球前保留的缓冲时长（秒）
    let preHitPadding: Double

    /// 截取回合片段时在末个击球后保留的缓冲时长（秒）
    let postHitPadding: Double

    /// 是否启用调试模式（输出详细日志）
    let enableDebugLogging: Bool

    // MARK: - 视觉检测相关阈值（暂时停用，保留备份）
    // let movementThreshold: Double
    // let confidenceThreshold: Double
    // let maxPauseDuration: Double
    // let ballVelocityThreshold: Double

    /// 默认配置：综合场景下的折中方案
    static let `default` = RallyDetectionConfiguration(
        minRallyDuration: 3.0,
        audioConfidenceThreshold: 0.6,
        maxHitInterval: 1.8,
        minHitCount: 4,
        preHitPadding: 0.6,
        postHitPadding: 1.0,
        enableDebugLogging: false
    )

    /// 严格配置：适合噪声较多、需降低误报
    static let strict = RallyDetectionConfiguration(
        minRallyDuration: 3.5,
        audioConfidenceThreshold: 0.7,
        maxHitInterval: 1.3,
        minHitCount: 5,
        preHitPadding: 0.5,
        postHitPadding: 0.8,
        enableDebugLogging: false
    )

    /// 宽松配置：适合音频质量一般、希望提高召回率
    static let lenient = RallyDetectionConfiguration(
        minRallyDuration: 2.0,
        audioConfidenceThreshold: 0.5,
        maxHitInterval: 2.2,
        minHitCount: 3,
        preHitPadding: 0.7,
        postHitPadding: 1.2,
        enableDebugLogging: false
    )

    /// 调试配置：启用详细日志
    static let debug = RallyDetectionConfiguration(
        minRallyDuration: 3.0,
        audioConfidenceThreshold: 0.6,
        maxHitInterval: 1.8,
        minHitCount: 4,
        preHitPadding: 0.6,
        postHitPadding: 1.0,
        enableDebugLogging: true
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

// MARK: - Helper Extensions

extension Array {
    /// 安全下标访问
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
