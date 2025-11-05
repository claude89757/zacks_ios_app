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

    /// 最近一次分析的调试数据（用于导出）
    private(set) var lastAnalysisDebugData: RuntimeDebugData?

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

    /// 峰值间隔统计量
    struct IntervalStatistics {
        let mean: Double              // 平均间隔
        let stdDev: Double           // 标准差
        let median: Double           // 中位数
        let percentile75: Double     // 75分位数
        let percentile90: Double     // 90分位数
        let percentile95: Double     // 95分位数
        let rallyBoundaryThreshold: Double  // 动态回合边界阈值
        let maxHitInterval: Double          // 动态最大击球间隔
    }

    /// 计算峰值间隔的统计量，用于动态确定聚类阈值
    private func calculateIntervalStatistics(peaks: [AudioPeak]) -> IntervalStatistics {
        guard peaks.count >= 2 else {
            // 峰值太少，返回默认值
            return IntervalStatistics(
                mean: 2.0,
                stdDev: 1.0,
                median: 2.0,
                percentile75: 3.0,
                percentile90: 5.0,
                percentile95: 8.0,
                rallyBoundaryThreshold: 12.0,
                maxHitInterval: 5.5
            )
        }

        // 计算所有相邻峰值的时间间隔
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            let interval = peaks[i].time - peaks[i-1].time
            intervals.append(interval)
        }

        // 排序以便计算分位数
        let sortedIntervals = intervals.sorted()

        // 计算均值
        let mean = intervals.reduce(0, +) / Double(intervals.count)

        // 计算标准差
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)

        // 计算中位数
        let medianIndex = sortedIntervals.count / 2
        let median = sortedIntervals.count % 2 == 0 ?
            (sortedIntervals[medianIndex - 1] + sortedIntervals[medianIndex]) / 2.0 :
            sortedIntervals[medianIndex]

        // 计算分位数
        func percentile(_ p: Double) -> Double {
            let index = Int(Double(sortedIntervals.count) * p)
            return sortedIntervals[min(index, sortedIntervals.count - 1)]
        }

        let p75 = percentile(0.75)
        let p90 = percentile(0.90)
        let p95 = percentile(0.95)

        // 动态确定回合边界阈值
        // 使用 95 分位数或均值 + 3×标准差，取较小值，但不小于 8 秒
        let statisticalBoundary = min(p95, mean + 3.0 * stdDev)
        let rallyBoundaryThreshold = max(8.0, min(statisticalBoundary, 15.0))  // 8-15秒范围

        // 动态确定最大击球间隔
        // 使用 75 分位数或均值 + 1.5×标准差，取较小值，但不小于 4 秒
        let statisticalMaxHit = min(p75, mean + 1.5 * stdDev)
        let maxHitInterval = max(4.0, min(statisticalMaxHit, 7.0))  // 4-7秒范围

        return IntervalStatistics(
            mean: mean,
            stdDev: stdDev,
            median: median,
            percentile75: p75,
            percentile90: p90,
            percentile95: p95,
            rallyBoundaryThreshold: rallyBoundaryThreshold,
            maxHitInterval: maxHitInterval
        )
    }

    private func detectRalliesUsingAudio(audioResult: AudioAnalysisResult) -> [Rally] {
        // 临时启用调试日志（仅在峰值数量较少时输出详细信息）
        let debugLogging = true
        let detailedLogging = audioResult.hitSounds.count < 100 // 峰值少时才详细日志
        
        // 只进行一次置信度过滤，使用统一的阈值0.55
        // 移除了重复的自适应阈值过滤，减少累积损失
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

        // 计算峰值间隔统计量，用于动态确定聚类阈值
        let intervalStats = calculateIntervalStatistics(peaks: peaks)

        if debugLogging && detailedLogging {
            print("📊 [RallyDetection] 间隔统计: 均值=\(String(format: "%.2f", intervalStats.mean))s, 标准差=\(String(format: "%.2f", intervalStats.stdDev))s")
            print("📊 [RallyDetection] 中位数=\(String(format: "%.2f", intervalStats.median))s, P75=\(String(format: "%.2f", intervalStats.percentile75))s, P95=\(String(format: "%.2f", intervalStats.percentile95))s")
            print("🎯 [RallyDetection] 动态阈值: 回合边界=\(String(format: "%.2f", intervalStats.rallyBoundaryThreshold))s, 最大击球间隔=\(String(format: "%.2f", intervalStats.maxHitInterval))s")
        }

        // 使用贝叶斯引导的时序聚类（Phase 2: 无监督ML）
        // 结合贝叶斯变化点检测和统计阈值，优化回合边界准确率
        let clusters = performBayesianGuidedClustering(peaks: peaks, intervalStats: intervalStats)
        
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
                            print("   - 平均间隔: \(String(format: "%.2f", avgInterval))s (要求: 0.2-7.0s)")
                            print("   - 最大间隔: \(String(format: "%.2f", intervals.max() ?? 0))s")
                        }
                        print("   - 击球密度: \(String(format: "%.2f", hitDensity)) (要求: >= 0.20)")
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

        // 合并相邻的短回合
        let mergedRallies = mergeAdjacentRallies(rallies)

        if debugLogging && mergedRallies.count != rallies.count {
            print("🔗 [RallyDetection] 合并后: \(mergedRallies.count) 个回合（合并了 \(rallies.count - mergedRallies.count) 个相邻回合）")
        }

        // 保存调试数据（用于导出）
        // 转换间隔统计数据
        let statsData = IntervalStats(
            mean: intervalStats.mean,
            stdDev: intervalStats.stdDev,
            median: intervalStats.median,
            percentile75: intervalStats.percentile75,
            percentile90: intervalStats.percentile90,
            percentile95: intervalStats.percentile95,
            rallyBoundaryThreshold: intervalStats.rallyBoundaryThreshold,
            maxHitInterval: intervalStats.maxHitInterval,
            totalIntervals: peaks.count - 1
        )

        // 重新计算贝叶斯变化点（用于调试数据）
        let bayesianIntervalStats = BayesianChangePointDetector.IntervalStatistics(
            mean: intervalStats.mean,
            stdDev: intervalStats.stdDev,
            median: intervalStats.median,
            percentile75: intervalStats.percentile75,
            percentile90: intervalStats.percentile90,
            percentile95: intervalStats.percentile95,
            rallyBoundaryThreshold: intervalStats.rallyBoundaryThreshold,
            maxHitInterval: intervalStats.maxHitInterval
        )
        let bayesianConfig = BayesianChangePointDetector.Config.adaptive(intervalStats: bayesianIntervalStats)
        let detector = BayesianChangePointDetector(config: bayesianConfig)
        let changePoints = detector.detectChangePoints(peaks: peaks)

        // 转换贝叶斯变化点数据
        let bayesianData = changePoints.map { cp in
            BayesianChangePoint(
                time: cp.time,
                probability: cp.probability,
                runLength: cp.runLength,
                isChangePoint: cp.isChangePoint
            )
        }

        // 保存到实例变量
        lastAnalysisDebugData = RuntimeDebugData(
            intervalStatistics: statsData,
            bayesianChangePoints: bayesianData,
            peakDetails: nil,  // 峰值详细数据需要从 AudioAnalyzer 获取
            timestamp: Date()
        )

        return mergedRallies
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

    /// 改进的时序聚类（考虑峰值间隔和密度，使用动态统计阈值）
    private func performImprovedTemporalClustering(
        peaks: [AudioPeak],
        intervalStats: IntervalStatistics
    ) -> [[AudioPeak]] {
        guard !peaks.isEmpty else { return [] }

        var clusters: [[AudioPeak]] = []
        var currentCluster: [AudioPeak] = [peaks[0]]

        for i in 1..<peaks.count {
            let currentPeak = peaks[i]
            let previousPeak = peaks[i-1]
            let timeInterval = currentPeak.time - previousPeak.time

            // 动态间隔判断：根据当前簇的状态、击球间隔和统计阈值
            let shouldCluster = shouldClusterPeaks(
                previous: previousPeak,
                current: currentPeak,
                currentCluster: currentCluster,
                intervalStats: intervalStats
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

        // 回溯合并：检查相邻簇是否可以合并
        return mergeAdjacentClusters(clusters)
    }

    /// 判断两个峰值是否应该聚为一簇（使用动态统计阈值）
    /// - Parameters:
    ///   - previous: 前一个峰值
    ///   - current: 当前峰值
    ///   - currentCluster: 当前簇中的所有峰值（用于判断簇的状态）
    ///   - intervalStats: 峰值间隔统计量（动态阈值）
    private func shouldClusterPeaks(
        previous: AudioPeak,
        current: AudioPeak,
        currentCluster: [AudioPeak],
        intervalStats: IntervalStatistics
    ) -> Bool {
        let timeInterval = current.time - previous.time

        // 如果间隔很短（<0.3秒），可能是同一击球的不同峰值，应该合并
        if timeInterval < 0.3 {
            return true
        }

        // 回合边界判断：使用动态统计阈值（替代固定的 12 秒）
        // 根据视频特性自动调整，回合之间的间隔通常远大于回合内击球间隔
        if timeInterval > intervalStats.rallyBoundaryThreshold {
            return false
        }

        // 动态间隔判断：根据当前簇的状态和统计阈值调整
        let clusterHitCount = currentCluster.count
        let clusterDuration = currentCluster.isEmpty ? 0.0 :
            (currentCluster.last!.time - currentCluster.first!.time)

        // 使用动态最大击球间隔（基于统计分析）
        let baseInterval = intervalStats.maxHitInterval

        // 如果当前簇已经有足够的击球（>= 4个），说明回合在进行中
        // 允许稍长的间隔（适应发球准备、换边等）
        if clusterHitCount >= 4 {
            // 回合进行中，允许更长的间隔，但不超过动态阈值的 1.3 倍
            let rallyInProgressInterval = min(baseInterval * 1.3, intervalStats.percentile90)
            if timeInterval <= rallyInProgressInterval {
                return true
            }
        } else {
            // 簇刚开始形成，使用标准间隔阈值
            // 允许稍微长一点的间隔以适应发球准备
            let startInterval = min(baseInterval * 1.2, intervalStats.percentile75)
            if timeInterval <= startInterval {
                return true
            }
        }

        // 如果两个峰值置信度都很高，且间隔在合理范围内，应该聚为一簇
        if previous.confidence > 0.7 && current.confidence > 0.7 {
            return timeInterval <= baseInterval * 1.2
        }

        // 默认使用统计的最大击球间隔
        return timeInterval <= baseInterval
    }

    /// 使用贝叶斯变化点检测进行聚类（混合方法）
    /// 结合贝叶斯CPD的概率判断和统计阈值，提高回合边界准确率
    /// - Parameters:
    ///   - peaks: 音频峰值数组
    ///   - intervalStats: 间隔统计量
    /// - Returns: 峰值簇数组
    private func performBayesianGuidedClustering(
        peaks: [AudioPeak],
        intervalStats: IntervalStatistics
    ) -> [[AudioPeak]] {
        guard !peaks.isEmpty else { return [] }

        // 1. 使用自适应配置创建贝叶斯检测器
        let adaptiveConfig = BayesianChangePointDetector.Config.adaptive(
            intervalStats: convertIntervalStatistics(intervalStats)
        )
        let detector = BayesianChangePointDetector(config: adaptiveConfig)

        // 2. 检测变化点
        let changePoints = detector.detectChangePoints(peaks: peaks)

        if config.enableDebugLogging {
            let detectedPoints = changePoints.filter { $0.isChangePoint }
            print("🎯 [BayesianClustering] 贝叶斯CPD检测到 \(detectedPoints.count) 个变化点")
        }

        // 3. 基于变化点进行分段
        var clusters: [[AudioPeak]] = []
        var currentCluster: [AudioPeak] = [peaks[0]]

        for i in 1..<peaks.count {
            let currentPeak = peaks[i]
            let previousPeak = peaks[i-1]

            // 获取当前位置的变化点概率（如果存在）
            let changePointProb = i-1 < changePoints.count ? changePoints[i-1].probability : 0.0
            let isHighProbChangePoint = changePointProb >= ChangePointResult.confidenceThreshold

            // 统计方法判断
            let shouldClusterStatistically = shouldClusterPeaks(
                previous: previousPeak,
                current: currentPeak,
                currentCluster: currentCluster,
                intervalStats: intervalStats
            )
            let statisticalShouldSplit = !shouldClusterStatistically

            // 🔧 修复混合决策逻辑（Critical Bug修复）
            // 策略：统计方法为主（基于固定阈值更可靠），贝叶斯辅助修正
            // 1. 统计认为分割 + 贝叶斯不强烈反对（>0.3） → 分割
            // 2. 贝叶斯高度确定（>0.7） → 分割
            let shouldSplit = (statisticalShouldSplit && changePointProb > 0.3) ||
                              (changePointProb > 0.7)

            if shouldSplit {
                // 保存当前簇，开始新簇
                if currentCluster.count >= config.minHitCount {
                    clusters.append(currentCluster)
                }
                currentCluster = [currentPeak]
            } else {
                currentCluster.append(currentPeak)
            }
        }

        // 保存最后一个簇
        if currentCluster.count >= config.minHitCount {
            clusters.append(currentCluster)
        }

        // 回溯合并（使用更保守的策略，因为贝叶斯已经优化了边界）
        return mergeAdjacentClusters(clusters)
    }

    /// 转换 IntervalStatistics 为 BayesianChangePointDetector.IntervalStatistics
    private func convertIntervalStatistics(_ stats: IntervalStatistics) -> BayesianChangePointDetector.IntervalStatistics {
        return BayesianChangePointDetector.IntervalStatistics(
            mean: stats.mean,
            stdDev: stats.stdDev,
            median: stats.median,
            percentile75: stats.percentile75,
            percentile90: stats.percentile90,
            percentile95: stats.percentile95,
            rallyBoundaryThreshold: stats.rallyBoundaryThreshold,
            maxHitInterval: stats.maxHitInterval
        )
    }

    /// 合并相邻的回合（如果它们实际上属于同一个回合）
    private func mergeAdjacentRallies(_ rallies: [Rally]) -> [Rally] {
        guard rallies.count > 1 else { return rallies }
        
        var mergedRallies: [Rally] = []
        var i = 0
        
        while i < rallies.count {
            var currentRally = rallies[i]
            
            // 检查是否可以与下一个回合合并
            while i + 1 < rallies.count {
                let nextRally = rallies[i + 1]
                
                // 检查两个回合之间的间隔
                let gapInterval = nextRally.startTime - currentRally.endTime
                
                // 更严格的合并条件：间隔很短（< 2秒），且其中一个回合很短（< 5秒）
                // 避免过度合并导致回合过长
                let shouldMerge = gapInterval < 2.0 && 
                                 (currentRally.duration < 5.0 || nextRally.duration < 5.0)
                
                if shouldMerge {
                    // 合并回合：使用更早的开始时间和更晚的结束时间
                    let mergedStartTime = min(currentRally.startTime, nextRally.startTime)
                    let mergedEndTime = max(currentRally.endTime, nextRally.endTime)
                    
                    // 创建合并后的回合
                    var mergedRally = Rally(startTime: mergedStartTime)
                    mergedRally.endTime = mergedEndTime
                    
                    // 合并元数据（使用平均值或更优值）
                    let mergedMetadata = DetectionMetadata(
                        maxMovementIntensity: max(currentRally.metadata.maxMovementIntensity, nextRally.metadata.maxMovementIntensity),
                        avgMovementIntensity: (currentRally.metadata.avgMovementIntensity + nextRally.metadata.avgMovementIntensity) / 2.0,
                        hasAudioPeaks: currentRally.metadata.hasAudioPeaks || nextRally.metadata.hasAudioPeaks,
                        poseConfidenceAvg: (currentRally.metadata.poseConfidenceAvg + nextRally.metadata.poseConfidenceAvg) / 2.0,
                        estimatedHitCount: (currentRally.metadata.estimatedHitCount ?? 0) + (nextRally.metadata.estimatedHitCount ?? 0),
                        playerCount: currentRally.metadata.playerCount ?? nextRally.metadata.playerCount,
                        audioPeakTimestamps: (currentRally.metadata.audioPeakTimestamps ?? []) + (nextRally.metadata.audioPeakTimestamps ?? [])
                    )
                    mergedRally.metadata = mergedMetadata
                    
                    currentRally = mergedRally
                    i += 1
                    continue
                }
                
                break
            }
            
            mergedRallies.append(currentRally)
            i += 1
        }
        
        return mergedRallies
    }

    /// 合并相邻的簇（如果它们实际上属于同一个回合）
    private func mergeAdjacentClusters(_ clusters: [[AudioPeak]]) -> [[AudioPeak]] {
        guard clusters.count > 1 else { return clusters }
        
        var mergedClusters: [[AudioPeak]] = []
        var i = 0
        
        while i < clusters.count {
            var currentCluster = clusters[i]
            
            // 检查是否可以与下一个簇合并
            while i + 1 < clusters.count {
                let nextCluster = clusters[i + 1]
                
                // 检查两个簇之间的间隔
                if let lastPeak = currentCluster.last, let firstPeak = nextCluster.first {
                    let gapInterval = firstPeak.time - lastPeak.time
                    
                    // 更严格的合并条件：间隔很短（< 8秒），且其中一个簇很短（< 4个击球）
                    // 避免过度合并导致回合过长
                    let shouldMerge = gapInterval < 8.0 && 
                                     (currentCluster.count < 4 || nextCluster.count < 4) &&
                                     gapInterval < 12.0  // 确保不会合并间隔过长的簇
                    
                    if shouldMerge {
                        // 合并簇
                        currentCluster.append(contentsOf: nextCluster)
                        i += 1
                        continue
                    }
                }
                
                break
            }
            
            mergedClusters.append(currentCluster)
            i += 1
        }
        
        return mergedClusters
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
    /// 🔧 修改为OR逻辑：支持标准回合、短快回合、长慢回合
    private func isValidRally(rally: Rally, cluster: [AudioPeak]) -> Bool {
        // 计算击球密度（用于判断回合类型）
        let hitDensity = Double(cluster.count) / rally.duration

        // 定义四种有效的回合模式（满足任一即可）
        // 慢节奏优化：支持业余/慢节奏比赛（平均间隔5-8秒）
        let standardRally = cluster.count >= 2 && rally.duration >= 2.0  // 标准回合：>= 2击，>= 2.0秒（降低要求）
        let shortFastRally = cluster.count >= 2 && hitDensity >= 0.25    // 快速回合：>= 2击，密度≥0.25（降低密度要求）
        let longSlowRally = cluster.count >= 2 && rally.duration >= 3.5  // 长慢回合：>= 2击，>= 3.5秒（降低要求）
        let casualRally = cluster.count >= 2 && rally.duration <= 60.0   // 业余回合：>= 2击，时长合理（新增慢节奏模式）

        // 至少满足一种回合模式
        guard standardRally || shortFastRally || longSlowRally || casualRally else {
            return false
        }

        // 击球间隔合理性检查（所有类型回合都需要通过）
        if cluster.count > 1 {
            let intervals = zip(cluster.dropFirst(), cluster).map { $0.time - $1.time }
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)

            // 平均击球间隔应该在合理范围内（0.2秒到10秒）
            // 放宽上限：支持慢节奏比赛（发球准备、场地切换等）
            guard avgInterval >= 0.2 && avgInterval <= 10.0 else { return false }

            // 检查是否有异常长的间隔（可能是误检）
            // 进一步放宽条件：允许有更多长间隔（慢节奏比赛常见）
            let longIntervals = intervals.filter { $0 > config.maxHitInterval * 1.5 }  // 1.3 → 1.5
            if longIntervals.count > 3 {  // 2 → 3
                return false
            }
        }

        return true
    }

    private func buildAudioRally(from cluster: [AudioPeak]) -> Rally? {
        guard let first = cluster.first, let last = cluster.last else { return nil }
        guard cluster.count >= config.minHitCount else { return nil }

        // 计算回合的实际时长（从第一个击球到最后一个击球）
        let rallyDuration = last.time - first.time
        
        // 根据回合时长动态调整padding
        let (prePadding, postPadding): (Double, Double)
        
        if rallyDuration < 5.0 {
            // 短回合（< 5秒）：使用较小的padding
            prePadding = config.preHitPadding * 0.9  // 1.35秒
            postPadding = config.postHitPadding * 0.9  // 1.62秒
        } else if rallyDuration > 12.0 {
            // 长回合（> 12秒）：使用较大的padding以保留更多内容
            prePadding = config.preHitPadding * 1.1  // 1.65秒
            postPadding = config.postHitPadding * 1.1  // 1.98秒
        } else {
            // 中等回合（5-12秒）：使用标准padding
            prePadding = config.preHitPadding  // 1.5秒
            postPadding = config.postHitPadding  // 1.8秒
        }
        
        let startTime = max(0.0, first.time - prePadding)
        let endTime = last.time + postPadding

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

// MARK: - Configuration

/// 回合检测配置
///
/// 提供三种预设配置，针对不同比赛节奏优化：
///
/// **1. `.default` - 默认配置（推荐）**
/// - 适用场景：业余/中等水平比赛
/// - 比赛特征：平均击球间隔 3-8 秒
/// - 使用示例：
///   ```swift
///   let engine = RallyDetectionEngine(config: .default)
///   ```
///
/// **2. `.lenient` - 宽松配置**
/// - 适用场景：初学者、慢节奏业余比赛
/// - 比赛特征：平均击球间隔 5-10 秒
/// - 特点：最大召回率，允许更长间隔和更少击球
/// - 使用示例：
///   ```swift
///   let engine = RallyDetectionEngine(config: .lenient)
///   ```
///
/// **3. `.strict` - 严格配置**
/// - 适用场景：专业/高水平比赛，噪声环境
/// - 比赛特征：平均击球间隔 1.5-3 秒
/// - 特点：降低误报，提高精确度
/// - 使用示例：
///   ```swift
///   let engine = RallyDetectionEngine(config: .strict)
///   ```
///
/// **配置选择指南：**
/// - 如果检测到 0 个回合 → 使用 `.lenient`
/// - 如果检测到过多误报回合 → 使用 `.strict`
/// - 一般情况 → 使用 `.default`
///
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

    /// 默认配置：综合场景下的平衡方案（支持慢节奏比赛）
    /// 适用场景：业余/中等水平比赛，平均击球间隔3-6秒
    static let `default` = RallyDetectionConfiguration(
        minRallyDuration: 2.5,  // 3.0 → 2.5：降低最小回合时长
        audioConfidenceThreshold: 0.50,  // Critical修复：与AudioAnalyzer统一为0.50（原0.55）
        maxHitInterval: 8.0,  // 5.5 → 8.0：提高间隔上限，适应慢节奏比赛
        minHitCount: 2,  // 3 → 2：降低最小击球数，提高召回率
        preHitPadding: 1.5,   // 保留发球/准备动作（1.5秒）
        postHitPadding: 1.8,  // 保留击球后的完整动作（1.8秒）
        enableDebugLogging: false
    )

    /// 严格配置：适合噪声较多、需降低误报
    static let strict = RallyDetectionConfiguration(
        minRallyDuration: 3.5,
        audioConfidenceThreshold: 0.7,
        maxHitInterval: 4.5,  // 更严格的间隔
        minHitCount: 5,
        preHitPadding: 1.3,
        postHitPadding: 1.5,
        enableDebugLogging: false
    )

    /// 宽松配置：专门针对慢节奏/业余比赛优化
    /// 适用场景：初学者、业余比赛，平均击球间隔5-10秒
    /// 特点：最大程度提高召回率，允许更长的击球间隔和更少的击球次数
    static let lenient = RallyDetectionConfiguration(
        minRallyDuration: 2.0,  // 保持较低的时长要求
        audioConfidenceThreshold: 0.45,  // 0.5 → 0.45：进一步降低置信度要求
        maxHitInterval: 10.0,  // 7.0 → 10.0：大幅提高间隔上限，适应慢节奏比赛
        minHitCount: 2,  // 3 → 2：降低最小击球数
        preHitPadding: 1.8,  // 保留更多上下文
        postHitPadding: 2.2,
        enableDebugLogging: true  // 默认开启调试日志，便于优化
    )

    /// 调试配置：启用详细日志
    static let debug = RallyDetectionConfiguration(
        minRallyDuration: 3.0,
        audioConfidenceThreshold: 0.65,  // 与default保持一致
        maxHitInterval: 5.5,  // 与default保持一致
        minHitCount: 4,
        preHitPadding: 1.5,
        postHitPadding: 1.8,
        enableDebugLogging: true
    )
}

// MARK: - RallyDetectionError

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
