//
//  RallyDetectionResult.swift
//  zacks_tennis
//
//  回合检测结果数据结构
//

import Foundation

/// 单帧分析结果
struct FrameAnalysisResult {
    /// 是否检测到人
    var hasPerson: Bool

    /// 检测置信度
    var confidence: Double

    /// 运动强度 (0-1)
    var movementIntensity: Double

    /// 关键点数据（可选）
    var keyPoints: [String: CGPoint]?

    /// 帧时间戳
    var timestamp: Double

    init(
        hasPerson: Bool = false,
        confidence: Double = 0.0,
        movementIntensity: Double = 0.0,
        keyPoints: [String: CGPoint]? = nil,
        timestamp: Double = 0.0
    ) {
        self.hasPerson = hasPerson
        self.confidence = confidence
        self.movementIntensity = movementIntensity
        self.keyPoints = keyPoints
        self.timestamp = timestamp
    }
}

/// 音频分析结果
struct AudioAnalysisResult {
    /// 音频峰值列表（击球声可能的时间点）
    var hitSounds: [AudioPeak]

    init(hitSounds: [AudioPeak] = []) {
        self.hitSounds = hitSounds
    }

    /// 检查指定时间附近是否有击球声
    func hasHitSound(at time: Double, confidence: Double, tolerance: Double = 0.5) -> Bool {
        return hitSounds.contains { peak in
            abs(peak.time - time) < tolerance && peak.confidence > confidence
        }
    }
}

/// 音频峰值
struct AudioPeak {
    /// 时间点（秒）
    let time: Double

    /// 峰值强度
    let amplitude: Double

    /// 置信度（是击球声的概率）
    let confidence: Double
}

/// 回合检测结果
struct Rally: Codable {
    /// 开始时间
    var startTime: Double

    /// 结束时间
    var endTime: Double

    /// 检测元数据
    var metadata: DetectionMetadata

    /// 时长
    var duration: Double {
        endTime - startTime
    }

    init(startTime: Double) {
        self.startTime = startTime
        self.endTime = startTime
        self.metadata = DetectionMetadata(
            maxMovementIntensity: 0.0,
            avgMovementIntensity: 0.0,
            hasAudioPeaks: false,
            poseConfidenceAvg: 0.0
        )
    }

    // Codable keys (exclude computed property 'duration')
    enum CodingKeys: String, CodingKey {
        case startTime
        case endTime
        case metadata
    }
}

/// 检测阈值配置
struct DetectionThresholds {
    /// 运动强度阈值
    let movementIntensityThreshold: Double

    /// 最小回合时长（秒）
    let minimumRallyDuration: Double

    /// 最大暂停时长（秒）
    let maximumPauseDuration: Double

    /// 音频击球声置信度阈值
    let audioHitConfidence: Double

    /// 姿态检测置信度阈值
    let poseConfidence: Double

    static let `default` = DetectionThresholds(
        movementIntensityThreshold: 0.4,
        minimumRallyDuration: 3.0,
        maximumPauseDuration: 2.0,
        audioHitConfidence: 0.6,
        poseConfidence: 0.5
    )
}

// MARK: - 精彩度评分

extension Rally {
    /// 计算精彩度评分 (0-100)
    func calculateExcitementScore() -> Double {
        var score: Double = 0.0

        // 1. 时长得分（30%）- 越长越精彩，上限30秒
        let durationScore = min(duration / 30.0, 1.0) * 30

        // 2. 运动强度得分（40%）
        let intensityScore = metadata.avgMovementIntensity * 40

        // 3. 音频得分（20%）- 有击球声
        let audioScore = metadata.hasAudioPeaks ? 20.0 : 0.0

        // 4. 持续性得分（10%）- 姿态检测置信度高
        let continuityScore = (metadata.poseConfidenceAvg > 0.7) ? 10.0 : 5.0

        score = durationScore + intensityScore + audioScore + continuityScore

        return min(score, 100.0)
    }
}
