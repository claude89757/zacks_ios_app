//
//  GMMClassifier.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-04.
//  高斯混合模型（GMM）分类器 - 区分击球、弹跳、噪音
//

import Foundation
import Accelerate

/// 音频事件类型
enum AudioEventType: String {
    case hit        // 击球声
    case bounce     // 弹跳声
    case noise      // 背景噪音
    case unknown    // 未知
}

/// 分类结果
struct ClassificationResult {
    let eventType: AudioEventType       // 事件类型
    let confidence: Double              // 分类置信度 [0, 1]
    let probabilities: [Double]         // 每个类别的概率分布
}

/// 音频特征向量（23维）
struct AudioFeatureVector {
    let mfccCoefficients: [Double]      // MFCC系数（13维）
    let spectralCentroid: Double        // 频谱质心
    let spectralRolloff: Double         // 频谱滚降点
    let spectralContrast: Double        // 频谱对比度
    let spectralFlux: Double            // 频谱通量
    let zeroCrossingRate: Double        // 过零率
    let energyRatio: Double             // 能量比
    let primaryFrequency: Double        // 主频率
    let attackTime: Double              // 起音时间
    let eventDuration: Double           // 事件持续时间
    let crestFactor: Double             // 峰值因子

    /// 转换为23维数组
    var asArray: [Double] {
        var features: [Double] = []
        features.append(contentsOf: mfccCoefficients)  // 13维
        features.append(spectralCentroid)
        features.append(spectralRolloff)
        features.append(spectralContrast)
        features.append(spectralFlux)
        features.append(zeroCrossingRate)
        features.append(energyRatio)
        features.append(primaryFrequency)
        features.append(attackTime)
        features.append(eventDuration)
        features.append(crestFactor)
        return features
    }

    /// 特征维度
    static let dimension = 23
}

/// 高斯分量
struct GaussianComponent {
    var weight: Double                  // 权重（混合系数）
    var mean: [Double]                  // 均值向量（23维）
    var covariance: [[Double]]          // 协方差矩阵（23x23）

    /// 计算概率密度
    func pdf(_ x: [Double]) -> Double {
        guard x.count == mean.count else { return 0.0 }

        let dim = x.count
        let diff = zip(x, mean).map { $0 - $1 }

        // 计算马氏距离: (x - μ)ᵀ Σ⁻¹ (x - μ)
        // 简化：使用对角协方差矩阵（降低计算复杂度）
        var mahalanobisDistance: Double = 0.0
        for i in 0..<dim {
            let variance = covariance[i][i]
            if variance > 0 {
                mahalanobisDistance += (diff[i] * diff[i]) / variance
            }
        }

        // 归一化常数
        var determinant: Double = 1.0
        for i in 0..<dim {
            determinant *= covariance[i][i]
        }

        let normalizationFactor = 1.0 / sqrt(pow(2.0 * .pi, Double(dim)) * determinant)

        return normalizationFactor * exp(-0.5 * mahalanobisDistance)
    }
}

/// GMM分类器（使用EM算法训练）
class GMMClassifier {

    // MARK: - Configuration

    struct Config {
        let numComponents: Int              // 高斯分量数（3-4）
        let maxIterations: Int              // EM最大迭代次数
        let convergenceThreshold: Double    // 收敛阈值
        let regularizationTerm: Double      // 协方差正则化项（防止奇异）
        let debugLogging: Bool

        static let `default` = Config(
            numComponents: 3,               // hit, bounce, noise
            maxIterations: 50,
            convergenceThreshold: 1e-4,
            regularizationTerm: 1e-6,
            debugLogging: false
        )
    }

    // MARK: - Properties

    private let config: Config
    private var components: [GaussianComponent] = []
    private var isTrained: Bool = false

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Training

    /// 使用EM算法训练GMM
    /// - Parameter features: 特征向量数组
    func train(features: [AudioFeatureVector]) {
        guard features.count >= config.numComponents * 3 else {
            if config.debugLogging {
                print("⚠️ [GMM] 训练样本不足: \(features.count)，需要至少 \(config.numComponents * 3)")
            }
            return
        }

        if config.debugLogging {
            print("🔧 [GMM] 开始训练，样本数=\(features.count), 分量数=\(config.numComponents)")
        }

        let data = features.map { $0.asArray }
        let dim = AudioFeatureVector.dimension

        // 1. 初始化：使用K-means++初始化
        components = initializeComponents(data: data, k: config.numComponents, dim: dim)

        // 2. EM迭代
        var prevLogLikelihood = -Double.infinity

        for iteration in 0..<config.maxIterations {
            // E-step: 计算后验概率
            let responsibilities = calculateResponsibilities(data: data)

            // M-step: 更新参数
            updateComponents(data: data, responsibilities: responsibilities, dim: dim)

            // 计算对数似然
            let logLikelihood = calculateLogLikelihood(data: data)

            // 检查收敛
            let improvement = logLikelihood - prevLogLikelihood
            if config.debugLogging && iteration % 10 == 0 {
                print("🔧 [GMM] 迭代 \(iteration): Log-Likelihood=\(String(format: "%.2f", logLikelihood)), 改进=\(String(format: "%.4f", improvement))")
            }

            if abs(improvement) < config.convergenceThreshold {
                if config.debugLogging {
                    print("✅ [GMM] 训练收敛，迭代次数=\(iteration)")
                }
                break
            }

            prevLogLikelihood = logLikelihood
        }

        isTrained = true
    }

    // MARK: - Prediction

    /// 预测单个样本的类别
    /// - Parameter feature: 特征向量
    /// - Returns: 分类结果
    func predict(feature: AudioFeatureVector) -> ClassificationResult {
        guard isTrained, !components.isEmpty else {
            return ClassificationResult(
                eventType: .unknown,
                confidence: 0.0,
                probabilities: []
            )
        }

        let x = feature.asArray

        // 计算每个分量的加权概率
        var probabilities: [Double] = []
        for component in components {
            let prob = component.weight * component.pdf(x)
            probabilities.append(prob)
        }

        // 归一化
        let sum = probabilities.reduce(0, +)
        if sum > 0 {
            probabilities = probabilities.map { $0 / sum }
        }

        // 找到最大概率的分量
        guard let maxIndex = probabilities.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return ClassificationResult(
                eventType: .unknown,
                confidence: 0.0,
                probabilities: probabilities
            )
        }

        let maxProb = probabilities[maxIndex]

        // 根据索引映射到事件类型（假设：0=hit, 1=bounce, 2=noise）
        let eventType = mapComponentToEventType(componentIndex: maxIndex, probability: maxProb)

        return ClassificationResult(
            eventType: eventType,
            confidence: maxProb,
            probabilities: probabilities
        )
    }

    // MARK: - Private Methods

    /// 使用K-means++初始化高斯分量
    private func initializeComponents(data: [[Double]], k: Int, dim: Int) -> [GaussianComponent] {
        var components: [GaussianComponent] = []
        var centers: [[Double]] = []

        // K-means++：第一个中心随机选择
        centers.append(data.randomElement()!)

        // 选择剩余的k-1个中心
        for _ in 1..<k {
            var distances: [Double] = []
            for point in data {
                let minDist = centers.map { euclideanDistance(point, $0) }.min()!
                distances.append(minDist * minDist)
            }

            // 概率选择（距离越远概率越大）
            let sumDist = distances.reduce(0, +)
            let rand = Double.random(in: 0..<sumDist)
            var cumulative: Double = 0
            for (index, dist) in distances.enumerated() {
                cumulative += dist
                if cumulative >= rand {
                    centers.append(data[index])
                    break
                }
            }
        }

        // 为每个中心创建高斯分量
        for center in centers {
            let weight = 1.0 / Double(k)
            let mean = center

            // 初始协方差为单位矩阵（对角）
            var covariance = Array(repeating: Array(repeating: 0.0, count: dim), count: dim)
            for i in 0..<dim {
                covariance[i][i] = 1.0
            }

            components.append(GaussianComponent(
                weight: weight,
                mean: mean,
                covariance: covariance
            ))
        }

        return components
    }

    /// E-step: 计算责任度（后验概率）
    private func calculateResponsibilities(data: [[Double]]) -> [[Double]] {
        var responsibilities: [[Double]] = []

        for x in data {
            var probs: [Double] = []
            for component in components {
                let prob = component.weight * component.pdf(x)
                probs.append(prob)
            }

            // 归一化
            let sum = probs.reduce(0, +)
            if sum > 0 {
                probs = probs.map { $0 / sum }
            }

            responsibilities.append(probs)
        }

        return responsibilities
    }

    /// M-step: 更新模型参数
    private func updateComponents(data: [[Double]], responsibilities: [[Double]], dim: Int) {
        let n = data.count

        for k in 0..<components.count {
            // 计算有效样本数
            var nk: Double = 0
            for i in 0..<n {
                nk += responsibilities[i][k]
            }

            guard nk > 0 else { continue }

            // 更新权重
            components[k].weight = nk / Double(n)

            // 更新均值
            var newMean = Array(repeating: 0.0, count: dim)
            for i in 0..<n {
                let r = responsibilities[i][k]
                for j in 0..<dim {
                    newMean[j] += r * data[i][j]
                }
            }
            for j in 0..<dim {
                newMean[j] /= nk
            }
            components[k].mean = newMean

            // 更新协方差（对角矩阵简化）
            var newCovariance = Array(repeating: Array(repeating: 0.0, count: dim), count: dim)
            for i in 0..<n {
                let r = responsibilities[i][k]
                for j in 0..<dim {
                    let diff = data[i][j] - newMean[j]
                    newCovariance[j][j] += r * diff * diff
                }
            }
            for j in 0..<dim {
                newCovariance[j][j] = newCovariance[j][j] / nk + config.regularizationTerm
            }
            components[k].covariance = newCovariance
        }
    }

    /// 计算对数似然
    private func calculateLogLikelihood(data: [[Double]]) -> Double {
        var logLikelihood: Double = 0

        for x in data {
            var prob: Double = 0
            for component in components {
                prob += component.weight * component.pdf(x)
            }
            if prob > 0 {
                logLikelihood += log(prob)
            }
        }

        return logLikelihood
    }

    /// 映射分量索引到事件类型
    private func mapComponentToEventType(componentIndex: Int, probability: Double) -> AudioEventType {
        // 简单映射（可根据训练结果调整）
        // 假设训练后：分量0=hit（高能量，短duration），分量1=bounce，分量2=noise
        if probability < 0.4 {
            return .unknown
        }

        switch componentIndex {
        case 0:
            return .hit
        case 1:
            return .bounce
        case 2:
            return .noise
        default:
            return .unknown
        }
    }

    /// 欧氏距离
    private func euclideanDistance(_ a: [Double], _ b: [Double]) -> Double {
        return sqrt(zip(a, b).map { pow($0 - $1, 2) }.reduce(0, +))
    }
}
