//
//  AudioEventClassifier.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-04.
//  音频事件分类器 - GMM训练和半监督自举
//

import Foundation

/// 音频事件分类器（使用GMM + 半监督学习）
actor AudioEventClassifier {

    // MARK: - Configuration

    struct Config {
        /// 高置信度阈值（>= 此值视为可靠的正样本）
        let highConfidenceThreshold: Double

        /// 低置信度阈值（<= 此值视为可靠的负样本）
        let lowConfidenceThreshold: Double

        /// 最小训练样本数
        let minTrainingSamples: Int

        /// 自动重训练间隔（检测的峰值数）
        let retrainingInterval: Int

        /// 是否启用GMM分类
        let enableGMMClassification: Bool

        /// 调试日志
        let debugLogging: Bool

        static let `default` = Config(
            highConfidenceThreshold: 0.75,
            lowConfidenceThreshold: 0.35,
            minTrainingSamples: 30,
            retrainingInterval: 100,
            enableGMMClassification: true,
            debugLogging: false
        )
    }

    // MARK: - Properties

    private let config: Config
    private var gmmClassifier: GMMClassifier?

    /// 训练样本缓存（半监督自举）
    private var highConfidenceSamples: [AudioFeatureVector] = []
    private var lowConfidenceSamples: [AudioFeatureVector] = []
    private var processedPeakCount: Int = 0

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
        if config.enableGMMClassification {
            self.gmmClassifier = GMMClassifier(config: .default)
        }
    }

    // MARK: - Public Methods

    /// 处理音频峰值（收集训练样本并可选地进行分类）
    /// - Parameters:
    ///   - peak: 音频峰值
    ///   - spectralAnalysis: 频谱分析结果
    ///   - attackTime: 起音时间
    ///   - eventDuration: 事件持续时间
    ///   - crestFactor: 峰值因子
    /// - Returns: 分类结果（如果GMM已训练）
    func processPeak(
        peak: AudioPeak,
        spectralAnalysis: SpectralAnalysis,
        attackTime: Double,
        eventDuration: Double,
        crestFactor: Double
    ) -> ClassificationResult? {
        // 1. 提取特征向量
        let feature = extractFeatureVector(
            spectralAnalysis: spectralAnalysis,
            attackTime: attackTime,
            eventDuration: eventDuration,
            crestFactor: crestFactor
        )

        // 2. 半监督样本收集
        collectTrainingSample(feature: feature, confidence: peak.confidence)

        // 3. 自动触发重训练
        processedPeakCount += 1
        if processedPeakCount % config.retrainingInterval == 0 {
            Task {
                await performRetraining()
            }
        }

        // 4. 如果GMM已训练，进行分类
        if let classifier = gmmClassifier {
            return classifier.predict(feature: feature)
        }

        return nil
    }

    /// 手动触发训练
    func train() async {
        await performRetraining()
    }

    /// 获取训练统计信息
    func getTrainingStats() -> (highConfidence: Int, lowConfidence: Int, isTrained: Bool) {
        return (
            highConfidenceSamples.count,
            lowConfidenceSamples.count,
            gmmClassifier != nil
        )
    }

    // MARK: - Private Methods

    /// 提取特征向量
    private func extractFeatureVector(
        spectralAnalysis: SpectralAnalysis,
        attackTime: Double,
        eventDuration: Double,
        crestFactor: Double
    ) -> AudioFeatureVector {
        return AudioFeatureVector(
            mfccCoefficients: spectralAnalysis.mfccCoefficients,
            spectralCentroid: spectralAnalysis.spectralCentroid,
            spectralRolloff: spectralAnalysis.spectralRolloff,
            spectralContrast: spectralAnalysis.spectralContrast,
            spectralFlux: spectralAnalysis.spectralFlux,
            zeroCrossingRate: 0.0,  // TODO: 如果需要可以添加
            energyRatio: spectralAnalysis.highFreqEnergyRatio,
            primaryFrequency: spectralAnalysis.dominantFrequency,
            attackTime: attackTime,
            eventDuration: eventDuration,
            crestFactor: crestFactor
        )
    }

    /// 收集训练样本（半监督）
    private func collectTrainingSample(feature: AudioFeatureVector, confidence: Double) {
        if confidence >= config.highConfidenceThreshold {
            // 高置信度 → 可能是真实击球声
            highConfidenceSamples.append(feature)
            if config.debugLogging && highConfidenceSamples.count % 10 == 0 {
                print("📊 [AudioClassifier] 收集到 \(highConfidenceSamples.count) 个高置信度样本")
            }
        } else if confidence <= config.lowConfidenceThreshold {
            // 低置信度 → 可能是噪音
            lowConfidenceSamples.append(feature)
            if config.debugLogging && lowConfidenceSamples.count % 10 == 0 {
                print("📊 [AudioClassifier] 收集到 \(lowConfidenceSamples.count) 个低置信度样本")
            }
        }
    }

    /// 执行重训练
    private func performRetraining() async {
        let totalSamples = highConfidenceSamples.count + lowConfidenceSamples.count

        guard totalSamples >= config.minTrainingSamples else {
            if config.debugLogging {
                print("📊 [AudioClassifier] 样本不足，跳过训练: \(totalSamples)/\(config.minTrainingSamples)")
            }
            return
        }

        if config.debugLogging {
            print("🔧 [AudioClassifier] 开始重训练，高置信度=\(highConfidenceSamples.count), 低置信度=\(lowConfidenceSamples.count)")
        }

        // 合并训练样本
        var trainingData = highConfidenceSamples
        trainingData.append(contentsOf: lowConfidenceSamples)

        // 训练GMM
        let classifier = GMMClassifier(config: GMMClassifier.Config(
            numComponents: 3,
            maxIterations: 50,
            convergenceThreshold: 1e-4,
            regularizationTerm: 1e-6,
            debugLogging: config.debugLogging
        ))

        classifier.train(features: trainingData)
        self.gmmClassifier = classifier

        if config.debugLogging {
            print("✅ [AudioClassifier] 重训练完成")
        }
    }
}

/// SpectralAnalysis 扩展（从AudioAnalyzer）
/// 这里声明是为了让AudioEventClassifier可以独立编译
extension AudioEventClassifier {
    struct SpectralAnalysis {
        let dominantFrequency: Double
        let energyInHitRange: Double
        let energyInPrimaryRange: Double
        let energyInLowFreq: Double
        let spectralCentroid: Double
        let spectralRolloff: Double
        let spectralContrast: Double
        let spectralFlux: Double
        let highFreqEnergyRatio: Double
        let mfccCoefficients: [Double]
        let mfccVariance: Double
    }
}
