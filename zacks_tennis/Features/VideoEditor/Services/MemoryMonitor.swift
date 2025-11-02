//
//  MemoryMonitor.swift
//  zacks_tennis
//
//  内存监控器 - 监听内存警告并触发缓存清理
//

import Foundation
import UIKit
import Combine

/// 内存压力级别
enum MemoryPressureLevel {
    case normal      // 正常
    case warning     // 警告（接近限制）
    case critical    // 危急（需要立即清理）
}

/// 内存监控器 - 单例模式
@MainActor
final class MemoryMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = MemoryMonitor()

    // MARK: - Published Properties

    /// 当前内存使用量（MB）
    @Published private(set) var currentMemoryUsage: Double = 0

    /// 内存压力级别
    @Published private(set) var pressureLevel: MemoryPressureLevel = .normal

    /// 是否启用监控
    @Published var isMonitoringEnabled: Bool = true

    // MARK: - Private Properties

    /// 内存警告通知订阅
    private var memoryWarningCancellable: AnyCancellable?

    /// 定时器（定期检查内存）
    private var timer: Timer?

    /// 内存警告回调列表
    private var warningCallbacks: [(MemoryPressureLevel) -> Void] = []

    /// 内存使用历史（用于趋势分析）
    private var memoryHistory: [Double] = []
    private let maxHistoryCount = 10

    // MARK: - Thresholds

    /// 内存警告阈值（MB）
    private let warningThreshold: Double = 300

    /// 内存危急阈值（MB）
    private let criticalThreshold: Double = 500

    // MARK: - Initialization

    private init() {
        setupMonitoring()
    }

    // MARK: - Setup

    /// 设置内存监控
    private func setupMonitoring() {
        // 监听系统内存警告通知
        memoryWarningCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMemoryWarning()
                }
            }

        // 启动定时器（每 5 秒检查一次）
        startPeriodicCheck()

        print("✅ MemoryMonitor 已启动")
    }

    /// 启动定期检查
    private func startPeriodicCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMemoryUsage()
            }
        }
    }

    // MARK: - Public Methods

    /// 注册内存警告回调
    /// - Parameter callback: 回调函数，接收内存压力级别
    func registerWarningCallback(_ callback: @escaping (MemoryPressureLevel) -> Void) {
        warningCallbacks.append(callback)
    }

    /// 手动触发内存检查
    func checkMemoryUsage() {
        guard isMonitoringEnabled else { return }

        let usage = getMemoryUsage()
        currentMemoryUsage = usage

        // 更新历史
        memoryHistory.append(usage)
        if memoryHistory.count > maxHistoryCount {
            memoryHistory.removeFirst()
        }

        // 评估压力级别
        let newLevel = evaluatePressureLevel(usage)

        // 如果级别变化，触发回调
        if newLevel != pressureLevel {
            pressureLevel = newLevel
            notifyCallbacks(newLevel)
        }
    }

    /// 获取内存使用趋势（上升/下降/稳定）
    func getMemoryTrend() -> String {
        guard memoryHistory.count >= 3 else { return "稳定" }

        let recent = memoryHistory.suffix(3)
        let avg = recent.reduce(0, +) / Double(recent.count)
        let last = recent.last ?? 0

        let diff = last - avg

        if diff > 50 {
            return "快速上升 ⚠️"
        } else if diff > 20 {
            return "缓慢上升 📈"
        } else if diff < -50 {
            return "快速下降 ✅"
        } else if diff < -20 {
            return "缓慢下降 📉"
        } else {
            return "稳定"
        }
    }

    /// 强制清理缓存（危急情况）
    func forceCleanup() {
        print("🔥 强制清理内存缓存")
        notifyCallbacks(.critical)
    }

    // MARK: - Private Methods

    /// 处理系统内存警告
    private func handleMemoryWarning() {
        print("⚠️ 收到系统内存警告")
        pressureLevel = .critical
        notifyCallbacks(.critical)
        checkMemoryUsage()
    }

    /// 评估内存压力级别
    private func evaluatePressureLevel(_ usage: Double) -> MemoryPressureLevel {
        if usage >= criticalThreshold {
            return .critical
        } else if usage >= warningThreshold {
            return .warning
        } else {
            return .normal
        }
    }

    /// 通知所有回调
    private func notifyCallbacks(_ level: MemoryPressureLevel) {
        for callback in warningCallbacks {
            callback(level)
        }

        // 打印日志
        switch level {
        case .normal:
            print("✅ 内存压力：正常")
        case .warning:
            print("⚠️ 内存压力：警告 (当前: \(Int(currentMemoryUsage))MB)")
        case .critical:
            print("🔥 内存压力：危急 (当前: \(Int(currentMemoryUsage))MB)")
        }
    }

    /// 获取当前内存使用量（MB）
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / 1024.0 / 1024.0
            return usedMemory
        } else {
            return 0
        }
    }

    // MARK: - Deinit

    deinit {
        timer?.invalidate()
        memoryWarningCancellable?.cancel()
    }
}

// MARK: - Memory Statistics

extension MemoryMonitor {
    /// 获取内存统计信息
    func getMemoryStats() -> MemoryStats {
        return MemoryStats(
            current: currentMemoryUsage,
            average: memoryHistory.isEmpty ? 0 : memoryHistory.reduce(0, +) / Double(memoryHistory.count),
            peak: memoryHistory.max() ?? 0,
            trend: getMemoryTrend(),
            pressureLevel: pressureLevel
        )
    }
}

/// 内存统计数据
struct MemoryStats {
    let current: Double      // 当前使用（MB）
    let average: Double      // 平均使用（MB）
    let peak: Double         // 峰值使用（MB）
    let trend: String        // 趋势
    let pressureLevel: MemoryPressureLevel
}
