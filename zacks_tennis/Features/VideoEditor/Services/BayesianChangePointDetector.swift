//
//  BayesianChangePointDetector.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-04.
//  无监督贝叶斯变化点检测 - 用于优化回合边界识别
//

import Foundation

/// 贝叶斯变化点检测结果
struct ChangePointResult {
    let time: Double                    // 时间点
    let probability: Double             // 变化点概率 [0, 1]
    let runLength: Int                  // 当前运行长度（回合内峰值数）
    let isChangePoint: Bool             // 是否为变化点（概率 > 阈值）

    /// 置信度阈值（概率超过此值认为是变化点）
    /// 🔧 统一为中间值0.55（原0.65）
    static let confidenceThreshold: Double = 0.55
}

/// 贝叶斯变化点检测器
/// 使用在线贝叶斯推断检测时序数据中的变化点（回合边界）
/// 参考文献: Adams & MacKay (2007) "Bayesian Online Changepoint Detection"
class BayesianChangePointDetector {

    // MARK: - Configuration

    /// 检测配置
    struct Config {
        /// 先验变化点概率（hazard function）
        /// 表示在任意时刻发生变化点的先验概率
        /// 值越大，算法越敏感（更容易检测到变化点）
        let hazardRate: Double

        /// 回合内间隔分布参数（正态分布）
        let withinRallyMean: Double      // 回合内平均间隔（秒）
        let withinRallyStdDev: Double    // 回合内间隔标准差

        /// 回合间间隔分布参数（正态分布）
        let betweenRallyMean: Double     // 回合间平均间隔（秒）
        let betweenRallyStdDev: Double   // 回合间间隔标准差

        /// 最小回合长度（峰值数）
        let minRallyLength: Int

        /// 调试输出开关
        let debugLogging: Bool

        /// 默认配置
        /// 🔧 统一参数为中间值，与RallyDetectionEngine协调
        static let `default` = Config(
            hazardRate: 0.05,              // 5% 先验变化概率（适度敏感）
            withinRallyMean: 2.5,          // 回合内平均 2.5s（统一中间值，原1.5s）
            withinRallyStdDev: 0.8,        // 标准差 0.8s
            betweenRallyMean: 10.0,        // 回合间平均 10s
            betweenRallyStdDev: 3.0,       // 标准差 3s
            minRallyLength: 3,             // 最少 3 个峰值（统一为3，原配置一致）
            debugLogging: false
        )

        /// 自适应配置（基于数据统计）
        /// 🔧 添加保护上下限，防止极端数据导致参数异常
        static func adaptive(intervalStats: IntervalStatistics) -> Config {
            // 使用 P75 作为回合内间隔上限，添加保护范围：0.4-3.0秒
            // Critical Bug修复：降低下限从0.8→0.4，适应快节奏视频（0.5-0.7秒间隔）
            let withinMean = max(0.4, min(intervalStats.mean, intervalStats.percentile75, 3.0))
            let withinStdDev = max(0.3, min(intervalStats.stdDev * 0.8, 1.5))

            // 使用 P90-P95 作为回合间间隔，添加保护范围：8-20秒
            let betweenMean = max(8.0, min((intervalStats.percentile90 + intervalStats.percentile95) / 2.0, 20.0))
            let betweenStdDev = max(2.0, min(intervalStats.stdDev * 1.5, 5.0))

            return Config(
                hazardRate: 0.05,
                withinRallyMean: withinMean,        // 范围：0.8-3.0s
                withinRallyStdDev: withinStdDev,    // 范围：0.4-1.2s
                betweenRallyMean: betweenMean,      // 范围：8-20s
                betweenRallyStdDev: betweenStdDev,  // 范围：2-5s
                minRallyLength: 3,
                debugLogging: false
            )
        }
    }

    // MARK: - Properties

    private let config: Config

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 检测变化点（回合边界）
    /// - Parameter peaks: 音频峰值数组（按时间排序）
    /// - Returns: 变化点检测结果数组
    func detectChangePoints(peaks: [AudioPeak]) -> [ChangePointResult] {
        guard peaks.count >= 2 else { return [] }

        // 计算峰值间隔
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            intervals.append(peaks[i].time - peaks[i-1].time)
        }

        if config.debugLogging {
            print("🔍 [BayesianCPD] 开始变化点检测，峰值数=\(peaks.count), 间隔数=\(intervals.count)")
        }

        // 运行长度概率矩阵
        // runLengthProbs[t][r] = P(运行长度=r | 观测到时刻t)
        var runLengthProbs: [[Double]] = Array(repeating: [1.0], count: intervals.count + 1)

        var results: [ChangePointResult] = []

        // 在线贝叶斯更新
        for t in 0..<intervals.count {
            let interval = intervals[t]

            // 当前时刻可能的运行长度：[0, 1, 2, ..., t]
            let maxRunLength = t + 1
            var newProbs: [Double] = Array(repeating: 0.0, count: maxRunLength + 1)

            // 对每个可能的运行长度，计算后验概率
            for r in 0..<maxRunLength {
                let currentProb = runLengthProbs[t][r]

                // 计算观测似然 P(interval | 运行长度=r)
                let likelihood = calculateLikelihood(interval: interval, runLength: r)

                // 增长概率：运行长度从 r 增长到 r+1（没有变化点）
                let growthProb = (1.0 - config.hazardRate) * currentProb * likelihood
                newProbs[r + 1] += growthProb

                // 变化点概率：运行长度归零（发生变化点）
                let changePointProb = config.hazardRate * currentProb * likelihood
                newProbs[0] += changePointProb
            }

            // 归一化概率
            let sum = newProbs.reduce(0, +)
            if sum > 0 {
                newProbs = newProbs.map { $0 / sum }
            }

            runLengthProbs[t + 1] = newProbs

            // 计算变化点概率（运行长度=0的概率）
            let changePointProbability = newProbs[0]

            // 计算期望运行长度（加权平均）
            var expectedRunLength: Double = 0
            for r in 0..<newProbs.count {
                expectedRunLength += Double(r) * newProbs[r]
            }
            let runLength = Int(round(expectedRunLength))

            // 判断是否为变化点
            let isChangePoint = changePointProbability >= ChangePointResult.confidenceThreshold
                && runLength >= config.minRallyLength

            let result = ChangePointResult(
                time: peaks[t + 1].time,
                probability: changePointProbability,
                runLength: runLength,
                isChangePoint: isChangePoint
            )

            results.append(result)

            if config.debugLogging && isChangePoint {
                print("🎯 [BayesianCPD] 检测到变化点: t=\(String(format: "%.2f", result.time))s, P=\(String(format: "%.3f", changePointProbability)), RL=\(runLength)")
            }
        }

        if config.debugLogging {
            let detectedCount = results.filter { $0.isChangePoint }.count
            print("✅ [BayesianCPD] 检测完成，共发现 \(detectedCount) 个变化点")
        }

        return results
    }

    // MARK: - Private Methods

    /// 计算观测间隔的似然概率
    /// - Parameters:
    ///   - interval: 观测到的时间间隔
    ///   - runLength: 当前运行长度
    /// - Returns: 似然概率 P(interval | runLength)
    private func calculateLikelihood(interval: Double, runLength: Int) -> Double {
        // 如果运行长度较小（回合刚开始或刚结束），使用混合分布
        // 否则使用回合内分布

        if runLength == 0 {
            // 刚发生变化点，可能是回合间间隔
            return normalPDF(
                x: interval,
                mean: config.betweenRallyMean,
                stdDev: config.betweenRallyStdDev
            )
        } else if runLength < config.minRallyLength {
            // 回合可能刚开始，使用混合分布
            let withinProb = normalPDF(
                x: interval,
                mean: config.withinRallyMean,
                stdDev: config.withinRallyStdDev
            )
            let betweenProb = normalPDF(
                x: interval,
                mean: config.betweenRallyMean,
                stdDev: config.betweenRallyStdDev
            )
            // 60% 回合内，40% 回合间
            return 0.6 * withinProb + 0.4 * betweenProb
        } else {
            // 回合进行中，使用回合内分布
            return normalPDF(
                x: interval,
                mean: config.withinRallyMean,
                stdDev: config.withinRallyStdDev
            )
        }
    }

    /// 正态分布概率密度函数
    /// - Parameters:
    ///   - x: 观测值
    ///   - mean: 均值
    ///   - stdDev: 标准差
    /// - Returns: 概率密度 P(x)
    private func normalPDF(x: Double, mean: Double, stdDev: Double) -> Double {
        let coefficient = 1.0 / (stdDev * sqrt(2.0 * .pi))
        let exponent = -pow(x - mean, 2) / (2.0 * pow(stdDev, 2))
        return coefficient * exp(exponent)
    }
}

// MARK: - IntervalStatistics Extension

/// 间隔统计（来自 RallyDetectionEngine）
/// 这里声明是为了让 BayesianChangePointDetector 可以独立编译
/// 实际定义在 RallyDetectionEngine.swift
extension BayesianChangePointDetector {
    struct IntervalStatistics {
        let mean: Double
        let stdDev: Double
        let median: Double
        let percentile75: Double
        let percentile90: Double
        let percentile95: Double
        let rallyBoundaryThreshold: Double
        let maxHitInterval: Double
    }
}

// MARK: - Phase 3 优化：自适应先验更新

extension BayesianChangePointDetector {

    /// 🚀 检测结果（用于先验更新）
    struct DetectionResult {
        let rallyStartTime: Double
        let rallyEndTime: Double
        let hitTimestamps: [Double]
        let wasCorrect: Bool?  // 可选：用户反馈
    }

    /// 🚀 基于历史检测结果更新先验参数
    /// 使用 MLE（最大似然估计）更新分布参数
    /// - Parameter history: 历史检测结果
    /// - Returns: 更新后的配置
    static func updatePriors(from history: [DetectionResult]) -> Config {
        guard history.count >= 3 else {
            return .default  // 样本太少，使用默认配置
        }

        // 1. 提取回合内间隔
        var withinRallyIntervals: [Double] = []
        for result in history {
            let timestamps = result.hitTimestamps.sorted()
            for i in 1..<timestamps.count {
                let interval = timestamps[i] - timestamps[i-1]
                if interval > 0.1 && interval < 8.0 {  // 合理范围
                    withinRallyIntervals.append(interval)
                }
            }
        }

        // 2. 提取回合间间隔
        var betweenRallyIntervals: [Double] = []
        let sortedResults = history.sorted { $0.rallyStartTime < $1.rallyStartTime }
        for i in 1..<sortedResults.count {
            let interval = sortedResults[i].rallyStartTime - sortedResults[i-1].rallyEndTime
            if interval > 2.0 && interval < 60.0 {  // 合理范围
                betweenRallyIntervals.append(interval)
            }
        }

        // 3. MLE 估计回合内参数
        let (withinMean, withinStdDev) = mleNormalParameters(withinRallyIntervals)

        // 4. MLE 估计回合间参数
        let (betweenMean, betweenStdDev) = mleNormalParameters(betweenRallyIntervals)

        // 5. 应用保护边界
        let safeWithinMean = max(0.4, min(withinMean, 4.0))
        let safeWithinStdDev = max(0.2, min(withinStdDev, 2.0))
        let safeBetweenMean = max(5.0, min(betweenMean, 30.0))
        let safeBetweenStdDev = max(1.5, min(betweenStdDev, 10.0))

        return Config(
            hazardRate: 0.05,
            withinRallyMean: safeWithinMean,
            withinRallyStdDev: safeWithinStdDev,
            betweenRallyMean: safeBetweenMean,
            betweenRallyStdDev: safeBetweenStdDev,
            minRallyLength: 3,
            debugLogging: false
        )
    }

    /// MLE 估计正态分布参数
    private static func mleNormalParameters(_ samples: [Double]) -> (mean: Double, stdDev: Double) {
        guard !samples.isEmpty else {
            return (2.5, 0.8)  // 默认值
        }

        let mean = samples.reduce(0, +) / Double(samples.count)

        guard samples.count > 1 else {
            return (mean, 0.8)
        }

        let variance = samples.map { pow($0 - mean, 2) }.reduce(0, +) / Double(samples.count - 1)
        let stdDev = sqrt(variance)

        return (mean, max(stdDev, 0.1))  // 最小标准差 0.1
    }

    /// 🚀 计算检测置信度评分
    /// 用于评估当前配置的效果
    /// - Parameter results: 变化点检测结果
    /// - Returns: 置信度评分 [0, 1]
    static func evaluateDetectionConfidence(_ results: [ChangePointResult]) -> Double {
        guard !results.isEmpty else { return 0 }

        // 指标1：变化点概率的一致性（方差越小越好）
        let probabilities = results.map { $0.probability }
        let meanProb = probabilities.reduce(0, +) / Double(probabilities.count)
        let variance = probabilities.map { pow($0 - meanProb, 2) }.reduce(0, +) / Double(probabilities.count)
        let consistencyScore = max(0, 1.0 - sqrt(variance) * 2)

        // 指标2：运行长度的合理性（大多数回合应该有 3-15 个击球）
        let runLengths = results.filter { $0.isChangePoint }.map { $0.runLength }
        let reasonableRuns = runLengths.filter { $0 >= 3 && $0 <= 15 }.count
        let reasonabilityScore = runLengths.isEmpty ? 0.5 :
            Double(reasonableRuns) / Double(runLengths.count)

        // 指标3：变化点间隔的规律性
        let changePoints = results.filter { $0.isChangePoint }
        var intervalScores: [Double] = []
        for i in 1..<changePoints.count {
            let interval = changePoints[i].time - changePoints[i-1].time
            // 合理的回合间隔应该在 5-30 秒
            if interval >= 5 && interval <= 30 {
                intervalScores.append(1.0)
            } else if interval >= 3 && interval <= 45 {
                intervalScores.append(0.5)
            } else {
                intervalScores.append(0.2)
            }
        }
        let intervalScore = intervalScores.isEmpty ? 0.5 :
            intervalScores.reduce(0, +) / Double(intervalScores.count)

        // 综合评分
        return consistencyScore * 0.3 + reasonabilityScore * 0.4 + intervalScore * 0.3
    }

    /// 🚀 自动选择最优配置
    /// 尝试多个配置，选择效果最好的
    /// - Parameter peaks: 音频峰值
    /// - Returns: 最优配置和对应的检测结果
    func autoSelectConfig(peaks: [AudioPeak]) -> (config: Config, results: [ChangePointResult], score: Double) {
        let configs: [Config] = [
            .default,
            Config(
                hazardRate: 0.03,
                withinRallyMean: 2.0,
                withinRallyStdDev: 0.6,
                betweenRallyMean: 8.0,
                betweenRallyStdDev: 2.5,
                minRallyLength: 3,
                debugLogging: false
            ),
            Config(
                hazardRate: 0.08,
                withinRallyMean: 3.0,
                withinRallyStdDev: 1.0,
                betweenRallyMean: 12.0,
                betweenRallyStdDev: 4.0,
                minRallyLength: 3,
                debugLogging: false
            )
        ]

        var bestConfig = Config.default
        var bestResults: [ChangePointResult] = []
        var bestScore: Double = 0

        for config in configs {
            let detector = BayesianChangePointDetector(config: config)
            let results = detector.detectChangePoints(peaks: peaks)
            let score = BayesianChangePointDetector.evaluateDetectionConfidence(results)

            if score > bestScore {
                bestScore = score
                bestConfig = config
                bestResults = results
            }
        }

        return (bestConfig, bestResults, bestScore)
    }
}
