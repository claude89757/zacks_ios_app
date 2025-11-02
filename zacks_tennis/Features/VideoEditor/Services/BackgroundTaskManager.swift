//
//  BackgroundTaskManager.swift
//  zacks_tennis
//
//  后台任务管理器 - 管理视频处理的后台任务
//

import Foundation
import BackgroundTasks
import UIKit
import Combine

/// 后台任务管理器 - 单例模式
@MainActor
final class BackgroundTaskManager: ObservableObject {

    // MARK: - Singleton

    static let shared = BackgroundTaskManager()

    // MARK: - Constants

    /// 后台处理任务标识符（需要在 Info.plist 中注册）
    private let processingTaskID = "com.zacks_tennis.video_processing"

    /// 后台刷新任务标识符
    private let refreshTaskID = "com.zacks_tennis.video_refresh"

    // MARK: - Properties

    /// 当前后台任务
    @Published private(set) var currentTask: BGTask?

    /// 后台任务是否已调度
    @Published private(set) var isTaskScheduled = false

    /// 处理状态管理器
    private let stateManager = ProcessingStateManager.shared

    // MARK: - Initialization

    private init() {
        registerBackgroundTasks()
        setupNotifications()
    }

    // MARK: - Registration

    /// 注册后台任务
    private func registerBackgroundTasks() {
        // 注册后台处理任务
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskID,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleProcessingTask(task as! BGProcessingTask)
            }
        }

        // 注册后台刷新任务
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskID,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleRefreshTask(task as! BGAppRefreshTask)
            }
        }

        print("✅ 后台任务已注册")
    }

    /// 设置通知监听
    private func setupNotifications() {
        // 监听应用进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // 监听应用即将终止
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Public Methods

    /// 调度后台处理任务
    /// - Parameter videoID: 要处理的视频 ID（可选，如果为 nil 则处理所有待恢复的任务）
    func scheduleProcessingTask(for videoID: UUID? = nil) {
        let request = BGProcessingTaskRequest(identifier: processingTaskID)

        // 需要外部电源
        request.requiresExternalPower = false

        // 需要网络连接（如果需要上传结果）
        request.requiresNetworkConnectivity = false

        // 最早开始时间（15分钟后）
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            isTaskScheduled = true
            print("✅ 后台处理任务已调度: \(processingTaskID)")
        } catch {
            print("⚠️ 调度后台任务失败: \(error)")
        }
    }

    /// 取消后台任务
    func cancelBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingTaskID)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        isTaskScheduled = false
        print("❌ 后台任务已取消")
    }

    /// 检查后台任务权限
    /// - Returns: 是否有权限
    func checkBackgroundTaskPermission() -> Bool {
        // 这里可以添加更详细的权限检查
        // 目前简单返回 true，实际应该检查系统设置
        return true
    }

    // MARK: - Task Handlers

    /// 处理后台处理任务
    /// - Parameter task: BGProcessingTask
    private func handleProcessingTask(_ task: BGProcessingTask) async {
        print("📱 开始后台处理任务")
        currentTask = task

        // 设置过期处理
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                print("⏰ 后台任务即将过期")
                self?.handleTaskExpiration()
            }
        }

        // 获取待恢复的状态
        let recoverableStates = stateManager.getRecoverableStates()

        guard !recoverableStates.isEmpty else {
            print("ℹ️ 没有待恢复的处理任务")
            task.setTaskCompleted(success: true)
            currentTask = nil
            return
        }

        // 处理第一个待恢复的任务（后台时间有限）
        let state = recoverableStates[0]

        do {
            // TODO: 集成 VideoProcessingEngine 进行实际处理
            // let engine = VideoProcessingEngine()
            // try await engine.resumeProcessing(from: state)

            // 模拟处理
            await simulateBackgroundProcessing(state: state)

            print("✅ 后台处理任务完成")
            task.setTaskCompleted(success: true)

            // 如果还有更多任务，重新调度
            if recoverableStates.count > 1 {
                scheduleProcessingTask()
            }

        } catch {
            print("❌ 后台处理任务失败: \(error)")
            task.setTaskCompleted(success: false)
        }

        currentTask = nil
    }

    /// 处理后台刷新任务
    /// - Parameter task: BGAppRefreshTask
    private func handleRefreshTask(_ task: BGAppRefreshTask) async {
        print("🔄 开始后台刷新任务")

        // 清理过期状态
        stateManager.cleanupExpiredStates()

        // 检查是否有待处理的任务
        if !stateManager.getRecoverableStates().isEmpty {
            scheduleProcessingTask()
        }

        task.setTaskCompleted(success: true)
    }

    /// 处理任务过期
    private func handleTaskExpiration() {
        print("⚠️ 后台任务过期，保存当前状态")

        // 保存当前状态会自动完成（ProcessingStateManager 自动保存）
        // 这里只需要标记任务为未完成
        currentTask?.setTaskCompleted(success: false)
        currentTask = nil

        // 重新调度
        scheduleProcessingTask()
    }

    // MARK: - Notifications

    /// 应用进入后台
    @objc private func appDidEnterBackground() {
        print("📱 应用进入后台")

        // 如果有正在进行的处理任务，调度后台任务
        if stateManager.activeProcessingCount > 0 {
            scheduleProcessingTask()
        }
    }

    /// 应用即将终止
    @objc private func appWillTerminate() {
        print("💀 应用即将终止")

        // 保存所有状态（已自动完成）
        // 调度后台任务以便下次启动时恢复
        if stateManager.activeProcessingCount > 0 {
            scheduleProcessingTask()
        }
    }

    // MARK: - Simulation (用于测试)

    /// 模拟后台处理（用于测试）
    private func simulateBackgroundProcessing(state: ProcessingState) async {
        print("🎬 模拟后台处理: videoID=\(state.videoID)")

        // 模拟处理进度（最多处理 30 秒）
        let maxIterations = 30
        for i in 0..<maxIterations {
            // 检查是否被取消
            if Task.isCancelled {
                print("❌ 后台任务被取消")
                return
            }

            // 模拟处理
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1秒

            // 更新进度
            let progress = Double(i + 1) / Double(maxIterations)
            let newTime = state.currentTime + (state.totalDuration - state.currentTime) * progress

            stateManager.updateProgress(
                for: state.videoID,
                currentTime: newTime,
                segmentIndex: state.currentSegmentIndex
            )

            print("📊 后台处理进度: \(Int(progress * 100))%")
        }

        // 标记完成
        stateManager.markCompleted(for: state.videoID)
    }

    // MARK: - Debug

    /// 模拟后台任务（用于开发测试）
    /// - Note: 仅在开发时使用，生产环境由系统调度
    func simulateBackgroundTask() async {
        print("🧪 模拟后台任务（仅用于测试）")

        let recoverableStates = stateManager.getRecoverableStates()

        guard let state = recoverableStates.first else {
            print("ℹ️ 没有待恢复的任务")
            return
        }

        await simulateBackgroundProcessing(state: state)
    }
}

// MARK: - Info.plist Configuration Helper

/*
 需要在 Info.plist 中添加以下配置：

 <key>BGTaskSchedulerPermittedIdentifiers</key>
 <array>
     <string>com.zacks_tennis.video_processing</string>
     <string>com.zacks_tennis.video_refresh</string>
 </array>

 <key>UIBackgroundModes</key>
 <array>
     <string>processing</string>
     <string>fetch</string>
 </array>
 */

// MARK: - Usage Notes

/*
 使用说明：

 1. 在 App 启动时初始化:
    let _ = BackgroundTaskManager.shared

 2. 开始处理时:
    BackgroundTaskManager.shared.scheduleProcessingTask(for: videoID)

 3. 测试后台任务（仅开发环境）:
    // 在 Xcode 中暂停 app，然后在调试控制台执行:
    e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.zacks_tennis.video_processing"]

 4. 注意事项:
    - 后台任务不保证执行
    - 最多执行时间约 30 秒
    - 应该作为断点续传的辅助，不能依赖它完成核心功能
    - 处理状态必须正确保存，以便前台恢复
 */
