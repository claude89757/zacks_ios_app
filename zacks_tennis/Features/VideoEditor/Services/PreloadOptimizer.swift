//
//  PreloadOptimizer.swift
//  zacks_tennis
//
//  智能预加载优化器 - 根据用户行为和系统资源动态调整预加载策略
//

import Foundation
import UIKit
import Combine

/// 预加载策略
enum PreloadStrategy {
    case aggressive  // 激进（预加载 5 个）
    case balanced    // 平衡（预加载 3 个）
    case conservative // 保守（预加载 1 个）
    case disabled    // 禁用预加载
}

/// 智能预加载优化器
@MainActor
final class PreloadOptimizer: ObservableObject {

    // MARK: - Singleton

    static let shared = PreloadOptimizer()

    // MARK: - Published Properties

    /// 当前预加载策略
    @Published private(set) var currentStrategy: PreloadStrategy = .balanced

    // MARK: - Private Properties

    /// 内存监控器
    private let memoryMonitor = MemoryMonitor.shared

    /// 用户行为跟踪
    private var userBehavior = UserBehaviorTracker()

    /// 系统资源状态
    private var systemResources = SystemResourcesStatus()

    // MARK: - Initialization

    private init() {
        setupMemoryMonitoring()
        startPeriodicOptimization()
    }

    // MARK: - Setup

    /// 设置内存监控
    private func setupMemoryMonitoring() {
        memoryMonitor.registerWarningCallback { [weak self] level in
            Task { @MainActor in
                self?.handleMemoryPressure(level)
            }
        }
    }

    /// 启动定期优化（每 30 秒调整一次策略）
    private func startPeriodicOptimization() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.optimizeStrategy()
            }
        }
    }

    // MARK: - Public Methods

    /// 获取推荐的预加载数量
    var recommendedPreloadCount: Int {
        switch currentStrategy {
        case .aggressive:
            return 5
        case .balanced:
            return 3
        case .conservative:
            return 1
        case .disabled:
            return 0
        }
    }

    /// 记录用户滑动行为
    /// - Parameter direction: 滑动方向（向上/向下）
    func recordSwipe(direction: SwipeDirection) {
        userBehavior.recordSwipe(direction: direction)
        optimizeStrategy()
    }

    /// 记录视频播放时长
    /// - Parameter duration: 播放时长（秒）
    func recordPlayDuration(_ duration: Double) {
        userBehavior.recordPlayDuration(duration)
    }

    /// 手动设置策略
    /// - Parameter strategy: 预加载策略
    func setStrategy(_ strategy: PreloadStrategy) {
        currentStrategy = strategy
        print("📊 PreloadOptimizer: 策略已设置为 \(strategy)")
    }

    // MARK: - Private Methods

    /// 优化预加载策略
    private func optimizeStrategy() {
        // 1. 检查内存压力
        let memoryLevel = memoryMonitor.pressureLevel

        // 2. 检查系统资源
        systemResources.update()

        // 3. 分析用户行为
        let behaviorScore = userBehavior.getScore()

        // 4. 决策矩阵
        let newStrategy = decideStrategy(
            memoryLevel: memoryLevel,
            batteryLevel: systemResources.batteryLevel,
            thermalState: systemResources.thermalState,
            behaviorScore: behaviorScore
        )

        // 5. 更新策略
        if newStrategy != currentStrategy {
            currentStrategy = newStrategy
            print("📊 PreloadOptimizer: 策略调整为 \(newStrategy)")
        }
    }

    /// 决策预加载策略
    private func decideStrategy(
        memoryLevel: MemoryPressureLevel,
        batteryLevel: Float,
        thermalState: ProcessInfo.ThermalState,
        behaviorScore: Double
    ) -> PreloadStrategy {

        // 内存危急，禁用预加载
        if memoryLevel == .critical {
            return .disabled
        }

        // 内存警告，使用保守策略
        if memoryLevel == .warning {
            return .conservative
        }

        // 低电量（< 20%），使用保守策略
        if batteryLevel < 0.2 {
            return .conservative
        }

        // 设备过热，使用保守策略
        if thermalState == .serious || thermalState == .critical {
            return .conservative
        }

        // 用户快速滑动（behaviorScore > 0.7），使用激进策略
        if behaviorScore > 0.7 {
            return .aggressive
        }

        // 用户中等速度滑动（behaviorScore > 0.4），使用平衡策略
        if behaviorScore > 0.4 {
            return .balanced
        }

        // 用户慢速滑动或长时间观看，使用保守策略
        return .conservative
    }

    /// 处理内存压力
    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .normal:
            // 恢复到基于行为的策略
            optimizeStrategy()

        case .warning:
            currentStrategy = .conservative
            print("⚠️ PreloadOptimizer: 内存警告，切换到保守策略")

        case .critical:
            currentStrategy = .disabled
            print("🔥 PreloadOptimizer: 内存危急，禁用预加载")
        }
    }
}

// MARK: - Supporting Types

/// 滑动方向
enum SwipeDirection {
    case up    // 向上（下一个视频）
    case down  // 向下（上一个视频）
}

/// 用户行为跟踪器
struct UserBehaviorTracker {
    /// 最近的滑动记录（时间戳）
    private var recentSwipes: [Date] = []

    /// 播放时长记录
    private var playDurations: [Double] = []

    /// 最大记录数
    private let maxRecords = 20

    /// 记录滑动
    mutating func recordSwipe(direction: SwipeDirection) {
        recentSwipes.append(Date())

        // 保持最近 N 条记录
        if recentSwipes.count > maxRecords {
            recentSwipes.removeFirst()
        }
    }

    /// 记录播放时长
    mutating func recordPlayDuration(_ duration: Double) {
        playDurations.append(duration)

        // 保持最近 N 条记录
        if playDurations.count > maxRecords {
            playDurations.removeFirst()
        }
    }

    /// 计算行为评分（0-1）
    /// - 评分越高，表示用户滑动越快，需要更多预加载
    func getScore() -> Double {
        guard !recentSwipes.isEmpty else { return 0.5 }

        // 计算滑动频率（每分钟滑动次数）
        let now = Date()
        let recentMinute = recentSwipes.filter { now.timeIntervalSince($0) < 60 }
        let swipeFrequency = Double(recentMinute.count)

        // 计算平均播放时长
        let avgPlayDuration = playDurations.isEmpty ? 10.0 : playDurations.reduce(0, +) / Double(playDurations.count)

        // 综合评分
        // - 滑动频率 > 10/分钟 -> 高评分
        // - 平均播放时长 < 5 秒 -> 高评分
        let frequencyScore = min(swipeFrequency / 10.0, 1.0)
        let durationScore = max(1.0 - (avgPlayDuration / 10.0), 0.0)

        return (frequencyScore * 0.6 + durationScore * 0.4)
    }
}

/// 系统资源状态
struct SystemResourcesStatus {
    /// 电池电量（0-1）
    var batteryLevel: Float = 1.0

    /// 热状态
    var thermalState: ProcessInfo.ThermalState = .nominal

    /// 低电量模式
    var isLowPowerModeEnabled: Bool = false

    /// 更新状态
    mutating func update() {
        // 电池电量
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel

        // 热状态
        thermalState = ProcessInfo.processInfo.thermalState

        // 低电量模式
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
