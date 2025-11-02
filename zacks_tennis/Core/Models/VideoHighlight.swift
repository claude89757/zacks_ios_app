//
//  VideoHighlight.swift
//  zacks_tennis
//
//  回合视频片段模型 - 存储每个检测到的网球回合
//

import Foundation
import SwiftData

@Model
final class VideoHighlight {
    /// 唯一标识符
    var id: UUID

    /// 所属视频（关系）
    var video: Video?

    /// 回合序号
    var rallyNumber: Int

    /// 开始时间（秒）
    var startTime: Double

    /// 结束时间（秒）
    var endTime: Double

    /// 精彩度评分 (0-100)
    var excitementScore: Double

    /// 是否收藏
    var isFavorite: Bool

    /// 缩略图路径（本地文件路径）
    var thumbnailPath: String?

    /// 视频文件路径（切片后的回合视频）
    var videoFilePath: String

    /// 检测置信度 (0-1)
    var detectionConfidence: Double

    /// 回合类型（rally/ace/winner 等）
    var type: String

    /// 回合描述/备注
    var rallyDescription: String

    /// 检测元数据（JSON 字符串）
    var metadataJSON: String?

    /// 网球轨迹数据（JSON 字符串）
    var ballTrajectoryDataJSON: String?

    /// 创建时间
    var createdAt: Date

    init(
        video: Video?,
        rallyNumber: Int,
        startTime: Double,
        endTime: Double,
        excitementScore: Double = 0.0,
        videoFilePath: String,
        type: String = "rally"
    ) {
        self.id = UUID()
        self.video = video
        self.rallyNumber = rallyNumber
        self.startTime = startTime
        self.endTime = endTime
        self.excitementScore = excitementScore
        self.isFavorite = false
        self.videoFilePath = videoFilePath
        self.detectionConfidence = 0.0
        self.type = type
        self.rallyDescription = ""
        self.createdAt = Date()
    }
}

// MARK: - 计算属性

extension VideoHighlight {
    /// 回合时长（秒）
    var duration: Double {
        endTime - startTime
    }

    /// 时长文本格式
    var durationText: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 是否为精彩回合（评分 > 70）
    var isExciting: Bool {
        excitementScore > 70
    }

    /// 缩略图 URL
    var thumbnailURL: URL? {
        guard let thumbnailPath = thumbnailPath else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }

    /// 视频 URL
    var videoURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(videoFilePath)
    }
}

// MARK: - 检测元数据

struct DetectionMetadata: Codable {
    /// 最大运动强度
    var maxMovementIntensity: Double

    /// 平均运动强度
    var avgMovementIntensity: Double

    /// 是否有音频峰值（击球声）
    var hasAudioPeaks: Bool

    /// 姿态检测平均置信度
    var poseConfidenceAvg: Double

    /// 击球次数估计
    var estimatedHitCount: Int?

    /// 检测到的球员数量
    var playerCount: Int?
    
    /// 音频峰值时间点列表（击球声的时间戳，相对于视频开始时间）
    var audioPeakTimestamps: [Double]?
    
    init(
        maxMovementIntensity: Double = 0.0,
        avgMovementIntensity: Double = 0.0,
        hasAudioPeaks: Bool = false,
        poseConfidenceAvg: Double = 0.0,
        estimatedHitCount: Int? = nil,
        playerCount: Int? = nil,
        audioPeakTimestamps: [Double]? = nil
    ) {
        self.maxMovementIntensity = maxMovementIntensity
        self.avgMovementIntensity = avgMovementIntensity
        self.hasAudioPeaks = hasAudioPeaks
        self.poseConfidenceAvg = poseConfidenceAvg
        self.estimatedHitCount = estimatedHitCount
        self.playerCount = playerCount
        self.audioPeakTimestamps = audioPeakTimestamps
    }
}

extension VideoHighlight {
    /// 获取音频峰值时间点（相对于回合开始时间）
    var audioPeakTimestamps: [Double] {
        guard let metadata = self.metadata,
              let timestamps = metadata.audioPeakTimestamps else {
            return []
        }
        // 返回相对于回合开始时间的时间戳
        return timestamps.map { $0 - self.startTime }
    }
    
    /// 获取检测元数据
    var metadata: DetectionMetadata? {
        get {
            guard let json = metadataJSON,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(DetectionMetadata.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                metadataJSON = json
            }
        }
    }

    /// 获取网球轨迹数据
    var ballTrajectoryData: BallTrajectoryData? {
        get {
            guard let json = ballTrajectoryDataJSON,
                  let data = json.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(BallTrajectoryData.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                ballTrajectoryDataJSON = json
            }
        }
    }

    /// 转换为 Rally 结构（用于状态保存）
    func toRally() -> Rally {
        var rally = Rally(startTime: self.startTime)
        rally.endTime = self.endTime

        // 使用现有的 metadata 或创建默认值
        if let metadata = self.metadata {
            rally.metadata = metadata
        }

        // 添加网球轨迹数据
        if let ballTrajectory = self.ballTrajectoryData {
            rally.ballTrajectory = ballTrajectory
        }

        return rally
    }
}
