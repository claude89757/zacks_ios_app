//
//  zacks_tennisApp.swift
//  zacks_tennis
//
//  Zacks 网球 App 入口文件
//  Created by 谢增添 on 2025/11/2.
//

import SwiftUI
import SwiftData

@main
struct zacks_tennisApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// SwiftData 模型容器 - 管理所有数据模型
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // 核心数据模型
            Court.self,
            User.self,
            NotificationItem.self,
            Video.self,
            VideoHighlight.self,  // AI 视频剪辑：回合视频片段
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            // 自动删除旧数据库并重建（开发阶段）
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // 如果加载失败，删除旧数据库并重试
            print("⚠️ ModelContainer 加载失败: \(error)")
            print("尝试删除旧数据库并重新创建...")

            // 删除旧的 SwiftData 存储文件
            let storeURL = modelConfiguration.url
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))

            // 重新尝试创建
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("重新创建 ModelContainer 失败: \(error)")
            }
        }
    }()

    // MARK: - Initialization

    init() {
        // 触发 BackgroundTaskManager 初始化（init 中已自动注册后台任务）
        _ = BackgroundTaskManager.shared
        print("✅ 后台任务已注册")

        // 清理过期的处理状态
        ProcessingStateManager.shared.cleanupExpiredStates()
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
    }

    // MARK: - Lifecycle Management

    /// 处理应用生命周期变化
    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // 应用进入前台
            print("📱 应用进入前台")

            // 清理过期的处理状态（每次进入前台时）
            ProcessingStateManager.shared.cleanupExpiredStates()
            print("✅ 已清理过期的处理状态")

            // 可以在这里取消后台任务（如果需要）
            // BackgroundTaskManager.shared.cancelAllTasks()

        case .inactive:
            // 应用即将进入后台
            print("📱 应用即将进入后台")
            // 暂停所有视频播放
            Task { @MainActor in
                VideoPlayerManager.shared.pauseAll()
            }

        case .background:
            // 应用已进入后台 - 调度后台处理任务
            print("📱 应用进入后台，调度后台任务...")
            BackgroundTaskManager.shared.scheduleProcessingTask()

            // 清理视频播放器资源
            Task { @MainActor in
                VideoPlayerManager.shared.cleanupAll()
                print("✅ 已清理所有视频播放器资源")
            }

        @unknown default:
            break
        }
    }
}
