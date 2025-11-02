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

    /// 网球轨迹数据（可选，用于调试和可视化）
    var ballTrajectory: BallTrajectoryData?

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
            poseConfidenceAvg: 0.0,
            estimatedHitCount: nil,
            playerCount: nil,
            audioPeakTimestamps: nil
        )
        self.ballTrajectory = nil
    }

    // Codable keys (exclude computed property 'duration')
    enum CodingKeys: String, CodingKey {
        case startTime
        case endTime
        case metadata
        case ballTrajectory
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

// MARK: - 网球轨迹数据

/// 网球轨迹数据 - 用于调试和分析
struct BallTrajectoryData: Codable {
    /// 轨迹点列表（时间戳 -> 网球位置）
    var trajectoryPoints: [BallTrajectoryPoint]

    /// 网球检测次数
    var detectionCount: Int

    /// 平均检测置信度
    var avgConfidence: Double

    /// 最大速度（归一化单位/秒）
    var maxVelocity: Double

    /// 平均速度
    var avgVelocity: Double

    /// 网球移动总距离（归一化单位）
    var totalDistance: Double

    init(
        trajectoryPoints: [BallTrajectoryPoint] = [],
        detectionCount: Int = 0,
        avgConfidence: Double = 0.0,
        maxVelocity: Double = 0.0,
        avgVelocity: Double = 0.0,
        totalDistance: Double = 0.0
    ) {
        self.trajectoryPoints = trajectoryPoints
        self.detectionCount = detectionCount
        self.avgConfidence = avgConfidence
        self.maxVelocity = maxVelocity
        self.avgVelocity = avgVelocity
        self.totalDistance = totalDistance
    }
}

/// 网球轨迹点
struct BallTrajectoryPoint: Codable {
    /// 时间戳（秒）
    let timestamp: Double

    /// 网球中心位置（归一化坐标 0-1）
    let position: CodablePoint

    /// 移动速度（归一化单位/秒）
    let velocity: CodableVector

    /// 检测置信度
    let confidence: Double
}

/// 可编码的 CGPoint（用于 Codable）
struct CodablePoint: Codable {
    let x: Double
    let y: Double

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cgPoint: CGPoint {
        return CGPoint(x: x, y: y)
    }
}

/// 可编码的 CGVector（用于 Codable）
struct CodableVector: Codable {
    let dx: Double
    let dy: Double

    init(_ vector: CGVector) {
        self.dx = Double(vector.dx)
        self.dy = Double(vector.dy)
    }

    var cgVector: CGVector {
        return CGVector(dx: dx, dy: dy)
    }

    var magnitude: Double {
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - 精彩度评分（增强版）

extension Rally {
    /// 计算精彩度评分 (0-100) - 包含网球追踪数据
    func calculateExcitementScore() -> Double {
        var score: Double = 0.0

        // 1. 时长得分（25%）- 越长越精彩，上限30秒
        let durationScore = min(duration / 30.0, 1.0) * 25

        // 2. 运动强度得分（30%）
        let intensityScore = metadata.avgMovementIntensity * 30

        // 3. 音频得分（20%）- 有击球声
        let audioScore = metadata.hasAudioPeaks ? 20.0 : 0.0

        // 4. 持续性得分（10%）- 姿态检测置信度高
        let continuityScore = (metadata.poseConfidenceAvg > 0.7) ? 10.0 : 5.0

        // 5. 网球活跃度得分（15%）- 如果有网球轨迹数据
        let ballScore: Double
        if let ballData = ballTrajectory {
            // 基于网球速度和移动距离
            let velocityScore = min(ballData.avgVelocity / 0.3, 1.0) * 0.5  // 速度贡献50%
            let distanceScore = min(ballData.totalDistance / 2.0, 1.0) * 0.5  // 距离贡献50%
            ballScore = (velocityScore + distanceScore) * 15
        } else {
            ballScore = 0.0
        }

        score = durationScore + intensityScore + audioScore + continuityScore + ballScore

        return min(score, 100.0)
    }
}
