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
    static let confidenceThreshold: Double = 0.65
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
        static let `default` = Config(
            hazardRate: 0.05,              // 5% 先验变化概率（适度敏感）
            withinRallyMean: 1.5,          // 回合内平均 1.5s
            withinRallyStdDev: 0.8,        // 标准差 0.8s
            betweenRallyMean: 10.0,        // 回合间平均 10s
            betweenRallyStdDev: 3.0,       // 标准差 3s
            minRallyLength: 3,             // 最少 3 个峰值
            debugLogging: false
        )

        /// 自适应配置（基于数据统计）
        static func adaptive(intervalStats: IntervalStatistics) -> Config {
            // 使用 P75 作为回合内间隔上限
            let withinMean = min(intervalStats.mean, intervalStats.percentile75)
            let withinStdDev = max(0.5, intervalStats.stdDev * 0.8)

            // 使用 P90-P95 作为回合间间隔
            let betweenMean = (intervalStats.percentile90 + intervalStats.percentile95) / 2.0
            let betweenStdDev = max(2.0, intervalStats.stdDev * 1.5)

            return Config(
                hazardRate: 0.05,
                withinRallyMean: withinMean,
                withinRallyStdDev: withinStdDev,
                betweenRallyMean: betweenMean,
                betweenRallyStdDev: betweenStdDev,
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
