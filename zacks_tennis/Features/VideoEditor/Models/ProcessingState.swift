//
//  ProcessingState.swift
//  zacks_tennis
//
//  视频处理状态 - 用于后台任务恢复
//

import Foundation

/// 视频处理状态（用于持久化和恢复）
struct ProcessingState: Codable {
    /// 视频 ID
    let videoID: UUID

    /// 视频总时长（秒）
    let totalDuration: Double

    /// 当前处理到的时间（秒）
    var currentTime: Double

    /// 当前段索引
    var currentSegmentIndex: Int

    /// 已检测到的回合数据
    var detectedRallies: [Rally]

    /// 处理进度 (0.0 - 1.0)
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return currentTime / totalDuration
    }

    /// 错误信息（如果处理失败）
    var error: String?

    /// 创建时间
    let createdAt: Date

    /// 最后更新时间
    var lastUpdated: Date

    init(
        videoID: UUID,
        totalDuration: Double,
        currentSegmentIndex: Int = 0,
        currentTime: Double = 0.0,
        detectedRallies: [Rally] = [],
        error: String? = nil,
        createdAt: Date = Date(),
        lastUpdated: Date = Date()
    ) {
        self.videoID = videoID
        self.totalDuration = totalDuration
        self.currentTime = currentTime
        self.currentSegmentIndex = currentSegmentIndex
        self.detectedRallies = detectedRallies
        self.error = error
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
}

// MARK: - 持久化

extension ProcessingState {
    /// 保存状态到 UserDefaults
    func save() throws {
        let key = "processing_state_\(videoID.uuidString)"
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 从 UserDefaults 加载状态
    static func load(for videoID: UUID) -> ProcessingState? {
        let key = "processing_state_\(videoID.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(ProcessingState.self, from: data)
    }

    /// 删除保存的状态
    static func remove(for videoID: UUID) {
        let key = "processing_state_\(videoID.uuidString)"
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 获取所有未完成的处理状态
    static func loadAllUnfinished() -> [ProcessingState] {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("processing_state_") }

        return keys.compactMap { key in
            guard let data = defaults.data(forKey: key) else { return nil }
            guard let state = try? JSONDecoder().decode(ProcessingState.self, from: data) else {
                return nil
            }
            // 只返回未完成的
            return state.currentTime < state.totalDuration ? state : nil
        }
    }
}

// MARK: - Codable

extension ProcessingState {
    enum CodingKeys: String, CodingKey {
        case videoID
        case totalDuration
        case currentTime
        case currentSegmentIndex
        case detectedRallies
        case error
        case createdAt
        case lastUpdated
        // progress 是计算属性，不需要编码
    }
}
