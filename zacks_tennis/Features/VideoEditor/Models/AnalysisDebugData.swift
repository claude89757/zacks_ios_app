//
//  AnalysisDebugData.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  视频分析调试数据模型 - 用于算法优化和问题排查
//

import Foundation

/// 完整的分析调试数据
struct AnalysisDebugData: Codable {
    let videoInfo: VideoInfo
    let rallies: [RallyDebugData]
    let hitEvents: [HitEventData]
    let intervalStatistics: IntervalStatisticsData?
    let bayesianChangePoints: [BayesianChangePointData]?
    let configuration: ConfigurationData
    let analysisTimestamp: Date

    enum CodingKeys: String, CodingKey {
        case videoInfo = "video_info"
        case rallies
        case hitEvents = "hit_events"
        case intervalStatistics = "interval_statistics"
        case bayesianChangePoints = "bayesian_change_points"
        case configuration
        case analysisTimestamp = "analysis_timestamp"
    }
}

// MARK: - Video Info

struct VideoInfo: Codable {
    let fileName: String
    let duration: Double
    let rallyCount: Int
    let totalHitCount: Int
    let resolution: String
    let fileSize: Int64
    let averageRallyDuration: Double
    let longestRallyDuration: Double
    let excitingRallyCount: Int
    let excitementRate: Int

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case duration
        case rallyCount = "rally_count"
        case totalHitCount = "total_hit_count"
        case resolution
        case fileSize = "file_size"
        case averageRallyDuration = "average_rally_duration"
        case longestRallyDuration = "longest_rally_duration"
        case excitingRallyCount = "exciting_rally_count"
        case excitementRate = "excitement_rate"
    }
}

// MARK: - Rally Debug Data

struct RallyDebugData: Codable {
    let index: Int
    let startTime: Double
    let endTime: Double
    let duration: Double
    let hitCount: Int
    let excitementScore: Double
    let detectionConfidence: Double
    let type: String
    let hitTimestamps: [Double]
    let metadata: RallyMetadata?

    enum CodingKeys: String, CodingKey {
        case index
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
        case hitCount = "hit_count"
        case excitementScore = "excitement_score"
        case detectionConfidence = "detection_confidence"
        case type
        case hitTimestamps = "hit_timestamps"
        case metadata
    }
}

struct RallyMetadata: Codable {
    let maxMovementIntensity: Double
    let avgMovementIntensity: Double
    let hasAudioPeaks: Bool
    let poseConfidenceAvg: Double
    let playerCount: Int?

    enum CodingKeys: String, CodingKey {
        case maxMovementIntensity = "max_movement_intensity"
        case avgMovementIntensity = "avg_movement_intensity"
        case hasAudioPeaks = "has_audio_peaks"
        case poseConfidenceAvg = "pose_confidence_avg"
        case playerCount = "player_count"
    }
}

// MARK: - Hit Event Data

struct HitEventData: Codable {
    let time: Double
    let confidence: Double
    let audioFeatures: AudioFeatures

    enum CodingKeys: String, CodingKey {
        case time
        case confidence
        case audioFeatures = "audio_features"
    }
}

struct AudioFeatures: Codable {
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

// MARK: - Interval Statistics

struct IntervalStatisticsData: Codable {
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

// MARK: - Bayesian Change Point Data

struct BayesianChangePointData: Codable {
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

// MARK: - Configuration Data

struct ConfigurationData: Codable {
    let audioAnalysis: AudioAnalysisConfig
    let rallyDetection: RallyDetectionConfig
    let bayesianCPD: BayesianCPDConfig?

    enum CodingKeys: String, CodingKey {
        case audioAnalysis = "audio_analysis"
        case rallyDetection = "rally_detection"
        case bayesianCPD = "bayesian_cpd"
    }
}

struct AudioAnalysisConfig: Codable {
    let peakThreshold: Double
    let minimumConfidence: Double
    let minimumPeakInterval: Double

    enum CodingKeys: String, CodingKey {
        case peakThreshold = "peak_threshold"
        case minimumConfidence = "minimum_confidence"
        case minimumPeakInterval = "minimum_peak_interval"
    }
}

struct RallyDetectionConfig: Codable {
    let minRallyDuration: Double
    let audioConfidenceThreshold: Double
    let maxHitInterval: Double
    let minHitCount: Int
    let preHitPadding: Double
    let postHitPadding: Double

    enum CodingKeys: String, CodingKey {
        case minRallyDuration = "min_rally_duration"
        case audioConfidenceThreshold = "audio_confidence_threshold"
        case maxHitInterval = "max_hit_interval"
        case minHitCount = "min_hit_count"
        case preHitPadding = "pre_hit_padding"
        case postHitPadding = "post_hit_padding"
    }
}

struct BayesianCPDConfig: Codable {
    let hazardRate: Double
    let withinRallyMean: Double
    let withinRallyStdDev: Double
    let betweenRallyMean: Double
    let betweenRallyStdDev: Double
    let minRallyLength: Int
    let confidenceThreshold: Double

    enum CodingKeys: String, CodingKey {
        case hazardRate = "hazard_rate"
        case withinRallyMean = "within_rally_mean"
        case withinRallyStdDev = "within_rally_std_dev"
        case betweenRallyMean = "between_rally_mean"
        case betweenRallyStdDev = "between_rally_std_dev"
        case minRallyLength = "min_rally_length"
        case confidenceThreshold = "confidence_threshold"
    }
}
