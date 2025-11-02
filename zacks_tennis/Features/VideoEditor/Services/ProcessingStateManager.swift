//
//  ProcessingStateManager.swift
//  zacks_tennis
//
//  处理状态管理器 - 保存和恢复视频处理状态，支持断点续传
//

import Foundation
import SwiftData
import Combine

/// 处理状态管理器 - 单例模式
@MainActor
final class ProcessingStateManager: ObservableObject, ProcessingStateManaging {

    // MARK: - Singleton

    static let shared = ProcessingStateManager()

    // MARK: - Properties

    /// 当前正在处理的状态（videoID -> ProcessingState）
    @Published private(set) var activeStates: [UUID: ProcessingState] = [:]

    /// UserDefaults 存储 key
    private let statesKey = "com.zacks_tennis.processing_states"

    /// 最大并发处理数
    private let maxConcurrentProcessing = 2

    // MARK: - Initialization

    private init() {
        loadStates()
    }

    // MARK: - Public Methods

    /// 创建新的处理状态
    /// - Parameters:
    ///   - videoID: 视频 ID
    ///   - totalDuration: 视频总时长
    /// - Returns: 新创建的处理状态
    func createState(for videoID: UUID, totalDuration: Double) -> ProcessingState {
        let state = ProcessingState(
            videoID: videoID,
            totalDuration: totalDuration,
            currentSegmentIndex: 0,
            currentTime: 0.0,
            detectedRallies: []
        )

        activeStates[videoID] = state
        saveStates()

        return state
    }

    /// 更新处理状态
    /// - Parameters:
    ///   - videoID: 视频 ID
    ///   - update: 更新闭包
    func updateState(for videoID: UUID, update: (inout ProcessingState) -> Void) {
        guard var state = activeStates[videoID] else { return }

        update(&state)
        state.lastUpdated = Date()

        activeStates[videoID] = state
        saveStates()
    }

    /// 获取处理状态
    /// - Parameter videoID: 视频 ID
    /// - Returns: 处理状态（如果存在）
    func getState(for videoID: UUID) -> ProcessingState? {
        return activeStates[videoID]
    }

    /// 删除处理状态（处理完成或取消时）
    /// - Parameter videoID: 视频 ID
    func removeState(for videoID: UUID) {
        activeStates.removeValue(forKey: videoID)
        saveStates()
    }

    /// 清理所有状态
    func clearAllStates() {
        activeStates.removeAll()
        saveStates()
    }

    /// 清理过期状态（超过 7 天未更新）
    func cleanupExpiredStates() {
        let expirationDate = Date().addingTimeInterval(-7 * 24 * 3600)

        let expiredIDs = activeStates.filter { _, state in
            state.lastUpdated < expirationDate
        }.map { $0.key }

        for id in expiredIDs {
            activeStates.removeValue(forKey: id)
        }

        if !expiredIDs.isEmpty {
            saveStates()
        }
    }

    /// 获取可恢复的状态列表
    /// - Returns: 未完成的处理状态列表
    func getRecoverableStates() -> [ProcessingState] {
        return Array(activeStates.values).filter { state in
            state.currentTime < state.totalDuration
        }
    }

    /// 检查是否可以开始新的处理任务
    /// - Returns: 是否可以开始
    func canStartNewProcessing() -> Bool {
        let activeCount = activeStates.values.filter { state in
            state.currentTime < state.totalDuration
        }.count

        return activeCount < maxConcurrentProcessing
    }

    /// 更新进度
    /// - Parameters:
    ///   - videoID: 视频 ID
    ///   - currentTime: 当前处理时间
    ///   - segmentIndex: 当前段索引
    func updateProgress(for videoID: UUID, currentTime: Double, segmentIndex: Int) {
        updateState(for: videoID) { state in
            state.currentTime = currentTime
            state.currentSegmentIndex = segmentIndex
        }
    }

    /// 添加检测到的回合
    /// - Parameters:
    ///   - videoID: 视频 ID
    ///   - rally: 回合数据
    func addDetectedRally(for videoID: UUID, rally: Rally) {
        updateState(for: videoID) { state in
            state.detectedRallies.append(rally)
        }
    }

    /// 标记处理完成
    /// - Parameter videoID: 视频 ID
    func markCompleted(for videoID: UUID) {
        updateState(for: videoID) { state in
            state.currentTime = state.totalDuration
        }

        // 延迟删除（给 UI 时间更新）
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2秒
            await removeState(for: videoID)
        }
    }

    /// 标记处理失败
    /// - Parameters:
    ///   - videoID: 视频 ID
    ///   - error: 错误信息
    func markFailed(for videoID: UUID, error: String) {
        updateState(for: videoID) { state in
            state.error = error
        }
    }

    // MARK: - Persistence

    /// 保存状态到 UserDefaults
    private func saveStates() {
        let statesArray = Array(activeStates.values)

        do {
            let data = try JSONEncoder().encode(statesArray)
            UserDefaults.standard.set(data, forKey: statesKey)
        } catch {
            print("⚠️ 保存处理状态失败: \(error)")
        }
    }

    /// 从 UserDefaults 加载状态
    private func loadStates() {
        guard let data = UserDefaults.standard.data(forKey: statesKey) else {
            return
        }

        do {
            let statesArray = try JSONDecoder().decode([ProcessingState].self, from: data)

            // 转换为字典
            activeStates = Dictionary(
                uniqueKeysWithValues: statesArray.map { ($0.videoID, $0) }
            )

            // 清理过期状态
            cleanupExpiredStates()

        } catch {
            print("⚠️ 加载处理状态失败: \(error)")
        }
    }

    // MARK: - Statistics

    /// 获取活跃处理任务数量
    var activeProcessingCount: Int {
        activeStates.values.filter { state in
            state.currentTime < state.totalDuration && state.error == nil
        }.count
    }

    /// 获取总处理进度
    /// - Returns: 平均进度（0-1）
    func getOverallProgress() -> Double {
        guard !activeStates.isEmpty else { return 0 }

        let totalProgress = activeStates.values.reduce(0.0) { sum, state in
            sum + (state.currentTime / state.totalDuration)
        }

        return totalProgress / Double(activeStates.count)
    }
}

// MARK: - Supporting Types

/// 处理进度通知
struct ProcessingProgressNotification {
    let videoID: UUID
    let currentTime: Double
    let totalDuration: Double
    let detectedRalliesCount: Int
    let currentOperation: String

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return currentTime / totalDuration
    }
}

/// 回合检测通知
struct RallyDetectedNotification {
    let videoID: UUID
    let rally: Rally
    let totalDetected: Int
}
