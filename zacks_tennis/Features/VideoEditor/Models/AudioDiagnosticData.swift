//
//  AudioDiagnosticData.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  音频诊断数据模型 - 用于排查音频峰值检测问题
//

import Foundation

// MARK: - 主诊断数据结构

/// 完整的音频诊断数据
struct AudioDiagnosticData: Codable {
    /// 视频基本信息
    let videoInfo: VideoDiagnosticInfo

    /// 音频基本特征
    let audioFeatures: AudioGlobalFeatures

    /// 所有候选峰值（未过滤前）
    let allCandidatePeaks: [CandidatePeakData]

    /// 最终保留的峰值
    let finalPeaks: [CandidatePeakData]

    /// 过滤统计信息
    let filteringStats: FilteringStatistics

    /// RMS 时间序列（采样）
    let rmsTimeSeries: [RMSDataPoint]

    /// 频谱分析采样
    let spectralSamples: [SpectralDataPoint]?

    /// 分析配置
    let configuration: AudioConfigSnapshot

    /// 诊断时间戳
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case videoInfo = "video_info"
        case audioFeatures = "audio_features"
        case allCandidatePeaks = "all_candidate_peaks"
        case finalPeaks = "final_peaks"
        case filteringStats = "filtering_stats"
        case rmsTimeSeries = "rms_time_series"
        case spectralSamples = "spectral_samples"
        case configuration
        case timestamp
    }
}

// MARK: - 视频基本信息

struct VideoDiagnosticInfo: Codable {
    let fileName: String
    let duration: Double
    let sampleRate: Double
    let channelCount: Int

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case duration
        case sampleRate = "sample_rate"
        case channelCount = "channel_count"
    }
}

// MARK: - 音频全局特征

struct AudioGlobalFeatures: Codable {
    /// 整体 RMS 均值
    let overallRMSMean: Double

    /// RMS 标准差
    let overallRMSStdDev: Double

    /// RMS 最大值
    let overallRMSMax: Double

    /// RMS 中位数
    let overallRMSMedian: Double

    /// RMS 90 分位数
    let overallRMSP90: Double

    /// 峰值振幅最大值
    let maxPeakAmplitude: Double

    /// 峰值振幅中位数
    let medianPeakAmplitude: Double

    /// 主导频率范围 (Hz)
    let dominantFrequencyRange: String

    /// 信噪比估计 (dB)
    let estimatedSNR: Double?

    enum CodingKeys: String, CodingKey {
        case overallRMSMean = "overall_rms_mean"
        case overallRMSStdDev = "overall_rms_std_dev"
        case overallRMSMax = "overall_rms_max"
        case overallRMSMedian = "overall_rms_median"
        case overallRMSP90 = "overall_rms_p90"
        case maxPeakAmplitude = "max_peak_amplitude"
        case medianPeakAmplitude = "median_peak_amplitude"
        case dominantFrequencyRange = "dominant_frequency_range"
        case estimatedSNR = "estimated_snr"
    }
}

// MARK: - 候选峰值数据

struct CandidatePeakData: Codable, Identifiable {
    var id: String { "\(time)_\(amplitude)" }

    /// 时间位置（秒）
    let time: Double

    /// 峰值振幅 (归一化 0-1)
    let amplitude: Double

    /// RMS 功率
    let rms: Double

    /// 事件持续时间（秒）
    let duration: Double

    /// 综合置信度 (0-1)
    let confidence: Double

    /// 置信度特征分解
    let confidenceBreakdown: ConfidenceBreakdown

    /// 频谱特征
    let spectralFeatures: SpectralFeatures

    /// 是否通过最终过滤
    let passedFiltering: Bool

    /// 被拒绝的原因（如果有）
    let rejectionReason: String?

    /// 在哪个阶段被拒绝
    let rejectionStage: String?

    enum CodingKeys: String, CodingKey {
        case time
        case amplitude
        case rms
        case duration
        case confidence
        case confidenceBreakdown = "confidence_breakdown"
        case spectralFeatures = "spectral_features"
        case passedFiltering = "passed_filtering"
        case rejectionReason = "rejection_reason"
        case rejectionStage = "rejection_stage"
    }
}

// MARK: - 置信度分解

struct ConfidenceBreakdown: Codable {
    /// 峰值振幅贡献 (权重 33%)
    let amplitudeScore: Double

    /// 峰度因子贡献 (权重 23%)
    let crestFactorScore: Double

    /// 能量集中度贡献 (权重 14%)
    let energyConcentrationScore: Double

    /// 频率范围匹配贡献 (权重 14%)
    let frequencyRangeScore: Double

    /// 高频能量比例贡献 (权重 14%)
    let highFreqEnergyScore: Double

    /// 其他特征贡献总和
    let otherFeaturesScore: Double

    enum CodingKeys: String, CodingKey {
        case amplitudeScore = "amplitude_score"
        case crestFactorScore = "crest_factor_score"
        case energyConcentrationScore = "energy_concentration_score"
        case frequencyRangeScore = "frequency_range_score"
        case highFreqEnergyScore = "high_freq_energy_score"
        case otherFeaturesScore = "other_features_score"
    }
}

// MARK: - 频谱特征

struct SpectralFeatures: Codable {
    /// 主导频率 (Hz)
    let dominantFrequency: Double

    /// 频谱质心 (Hz)
    let spectralCentroid: Double

    /// 频谱滚降点 (Hz)
    let spectralRolloff: Double

    /// 200-500 Hz 能量占比
    let lowFreqEnergy: Double

    /// 1000-3000 Hz 能量占比（关键网球击球范围）
    let primaryHitRangeEnergy: Double

    /// 3000-8000 Hz 能量占比
    let highFreqEnergy: Double

    /// MFCC 均值（前 5 个系数）
    let mfccMean: [Double]?

    enum CodingKeys: String, CodingKey {
        case dominantFrequency = "dominant_frequency"
        case spectralCentroid = "spectral_centroid"
        case spectralRolloff = "spectral_rolloff"
        case lowFreqEnergy = "low_freq_energy"
        case primaryHitRangeEnergy = "primary_hit_range_energy"
        case highFreqEnergy = "high_freq_energy"
        case mfccMean = "mfcc_mean"
    }
}

// MARK: - 过滤统计

struct FilteringStatistics: Codable {
    /// 总候选峰值数
    let totalCandidates: Int

    /// 通过振幅阈值的数量
    let passedAmplitudeThreshold: Int

    /// 通过持续时间验证的数量
    let passedDurationCheck: Int

    /// 通过置信度阈值的数量
    let passedConfidenceThreshold: Int

    /// 通过自适应过滤的数量
    let passedAdaptiveFiltering: Int

    /// 经过后处理合并后的数量
    let afterPostProcessing: Int

    /// 最终保留的数量
    let finalCount: Int

    /// 各阶段拒绝原因统计
    let rejectionReasons: [String: Int]

    /// 平均置信度
    let averageConfidence: Double

    /// 置信度中位数
    let medianConfidence: Double

    enum CodingKeys: String, CodingKey {
        case totalCandidates = "total_candidates"
        case passedAmplitudeThreshold = "passed_amplitude_threshold"
        case passedDurationCheck = "passed_duration_check"
        case passedConfidenceThreshold = "passed_confidence_threshold"
        case passedAdaptiveFiltering = "passed_adaptive_filtering"
        case afterPostProcessing = "after_post_processing"
        case finalCount = "final_count"
        case rejectionReasons = "rejection_reasons"
        case averageConfidence = "average_confidence"
        case medianConfidence = "median_confidence"
    }
}

// MARK: - RMS 数据点

struct RMSDataPoint: Codable {
    /// 时间位置（秒）
    let time: Double

    /// RMS 值
    let rms: Double

    /// 峰值振幅（如果有）
    let peakAmplitude: Double?
}

// MARK: - 频谱数据点

struct SpectralDataPoint: Codable {
    /// 时间位置（秒）
    let time: Double

    /// 频率箱（Hz）
    let frequencyBins: [Double]

    /// 各频率的幅度（dB）
    let magnitudes: [Double]
}

// MARK: - 配置快照

struct AudioConfigSnapshot: Codable {
    let peakThreshold: Double
    let minimumConfidence: Double
    let minimumPeakInterval: Double

    /// 配置预设名称
    let presetName: String

    enum CodingKeys: String, CodingKey {
        case peakThreshold = "peak_threshold"
        case minimumConfidence = "minimum_confidence"
        case minimumPeakInterval = "minimum_peak_interval"
        case presetName = "preset_name"
    }
}

// MARK: - 拒绝原因枚举

enum PeakRejectionReason: String, Codable {
    case amplitudeTooLow = "振幅低于阈值"
    case rmsTooLow = "RMS 功率过低"
    case durationInvalid = "持续时间不符合范围"
    case confidenceTooLow = "综合置信度过低"
    case adaptiveFiltering = "自适应统计过滤"
    case mergedInPostProcessing = "后处理合并"
    case tooCloseToOtherPeak = "与其他峰值过近"
    case spectralMismatch = "频谱特征不匹配"
}

// MARK: - 过滤阶段枚举

enum FilteringStage: String, Codable {
    case initialDetection = "初始检测"
    case amplitudeFilter = "振幅过滤"
    case durationFilter = "持续时间过滤"
    case confidenceFilter = "置信度过滤"
    case adaptiveFilter = "自适应过滤"
    case postProcessing = "后处理"
}

// MARK: - 辅助扩展

extension AudioDiagnosticData {
    /// 获取被拒绝的峰值
    var rejectedPeaks: [CandidatePeakData] {
        allCandidatePeaks.filter { !$0.passedFiltering }
    }

    /// 获取各阶段通过率
    var stagePassRates: [String: Double] {
        guard filteringStats.totalCandidates > 0 else { return [:] }

        let total = Double(filteringStats.totalCandidates)
        return [
            "振幅阈值": Double(filteringStats.passedAmplitudeThreshold) / total,
            "持续时间": Double(filteringStats.passedDurationCheck) / total,
            "置信度": Double(filteringStats.passedConfidenceThreshold) / total,
            "自适应过滤": Double(filteringStats.passedAdaptiveFiltering) / total,
            "后处理": Double(filteringStats.afterPostProcessing) / total,
            "最终保留": Double(filteringStats.finalCount) / total
        ]
    }

    /// 整体通过率
    var overallPassRate: Double {
        guard filteringStats.totalCandidates > 0 else { return 0 }
        return Double(filteringStats.finalCount) / Double(filteringStats.totalCandidates)
    }
}
