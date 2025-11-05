//
//  RuntimeDebugData.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  运行时调试数据 - 保存分析引擎的中间计算结果
//

import Foundation

/// 运行时调试数据容器
struct RuntimeDebugData: Codable {
    let intervalStatistics: IntervalStats?
    let bayesianChangePoints: [BayesianChangePoint]?
    let peakDetails: [PeakDetail]?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case intervalStatistics = "interval_statistics"
        case bayesianChangePoints = "bayesian_change_points"
        case peakDetails = "peak_details"
        case timestamp
    }
}

/// 间隔统计数据
struct IntervalStats: Codable {
    let mean: Double
    let stdDev: Double
    let median: Double
    let percentile75: Double
    let percentile90: Double
    let percentile95: Double
    let rallyBoundaryThreshold: Double
    let maxHitInterval: Double
    let totalIntervals: Int

    enum CodingKeys: String, CodingKey {
        case mean
        case stdDev = "std_dev"
        case median
        case percentile75 = "p75"
        case percentile90 = "p90"
        case percentile95 = "p95"
        case rallyBoundaryThreshold = "rally_boundary_threshold"
        case maxHitInterval = "max_hit_interval"
        case totalIntervals = "total_intervals"
    }
}

/// 贝叶斯变化点数据
struct BayesianChangePoint: Codable {
    let time: Double
    let probability: Double
    let runLength: Int
    let isChangePoint: Bool

    enum CodingKeys: String, CodingKey {
        case time
        case probability
        case runLength = "run_length"
        case isChangePoint = "is_change_point"
    }
}

/// 峰值详细数据
struct PeakDetail: Codable {
    let time: Double
    let confidence: Double
    let amplitude: Double
    let frequency: Double
    let spectralCentroid: Double
    let spectralRolloff: Double
    let spectralContrast: Double
    let spectralFlux: Double
    let highFreqEnergyRatio: Double
    let energyInHitRange: Double
    let crestFactor: Double
    let attackTime: Double
    let eventDuration: Double
    let mfccCoefficients: [Double]?
    let mfccVariance: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case confidence
        case amplitude
        case frequency
        case spectralCentroid = "spectral_centroid"
        case spectralRolloff = "spectral_rolloff"
        case spectralContrast = "spectral_contrast"
        case spectralFlux = "spectral_flux"
        case highFreqEnergyRatio = "high_freq_energy_ratio"
        case energyInHitRange = "energy_in_hit_range"
        case crestFactor = "crest_factor"
        case attackTime = "attack_time"
        case eventDuration = "event_duration"
        case mfccCoefficients = "mfcc_coefficients"
        case mfccVariance = "mfcc_variance"
    }
}
