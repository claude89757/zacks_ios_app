//
//  NotificationItem.swift
//  zacks_tennis
//
//  空场提醒项模型 - 存储用户订阅的空场提醒配置
//

import Foundation
import SwiftData

@Model
final class NotificationItem {
    /// 唯一标识符
    var id: UUID

    /// 关联的网球场
    var court: Court?

    /// 提醒名称
    var title: String

    /// 监控的日期（可选，nil 表示每天）
    var targetDate: Date?

    /// 监控的时间段（如 "18:00-20:00"）
    var timeSlots: [String]

    /// 监控的星期几 (1-7, 1=周一, 7=周日，空数组表示每天)
    var daysOfWeek: [Int]

    /// 是否启用
    var isEnabled: Bool

    /// 提醒方式 (本地通知/邮件)
    var notificationMethod: String

    /// 邮件地址（如果选择邮件提醒）
    var emailAddress: String?

    /// 检查频率（分钟）
    var checkIntervalMinutes: Int

    /// 创建时间
    var createdAt: Date

    /// 更新时间
    var updatedAt: Date

    /// 最后检查时间
    var lastCheckedAt: Date?

    /// 最后触发时间
    var lastTriggeredAt: Date?

    /// 触发次数
    var triggerCount: Int

    /// 备注
    var notes: String

    init(
        court: Court? = nil,
        title: String,
        timeSlots: [String] = [],
        daysOfWeek: [Int] = [],
        notificationMethod: String = "本地通知",
        checkIntervalMinutes: Int = 30
    ) {
        self.id = UUID()
        self.court = court
        self.title = title
        self.timeSlots = timeSlots
        self.daysOfWeek = daysOfWeek
        self.isEnabled = true
        self.notificationMethod = notificationMethod
        self.checkIntervalMinutes = checkIntervalMinutes
        self.createdAt = Date()
        self.updatedAt = Date()
        self.triggerCount = 0
        self.notes = ""
    }
}

// MARK: - 便利方法
extension NotificationItem {
    /// 获取星期几的显示文本
    var daysOfWeekText: String {
        if daysOfWeek.isEmpty {
            return "每天"
        }

        let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
        return daysOfWeek.sorted().map { day in
            "周\(dayNames[day - 1])"
        }.joined(separator: ", ")
    }

    /// 获取时间段显示文本
    var timeSlotsText: String {
        if timeSlots.isEmpty {
            return "全天"
        }
        return timeSlots.joined(separator: ", ")
    }

    /// 检查当前是否应该监控
    func shouldMonitorNow() -> Bool {
        guard isEnabled else { return false }

        let calendar = Calendar.current
        let now = Date()

        // 检查星期几
        if !daysOfWeek.isEmpty {
            let weekday = calendar.component(.weekday, from: now)
            // Calendar.weekday: 1=周日, 2=周一, ..., 7=周六
            // 我们的 daysOfWeek: 1=周一, ..., 7=周日
            let adjustedWeekday = weekday == 1 ? 7 : weekday - 1
            if !daysOfWeek.contains(adjustedWeekday) {
                return false
            }
        }

        // 检查目标日期
        if let targetDate = targetDate {
            let isTargetDay = calendar.isDate(now, inSameDayAs: targetDate)
            if !isTargetDay {
                return false
            }
        }

        return true
    }

    /// 记录触发
    func recordTrigger() {
        self.lastTriggeredAt = Date()
        self.triggerCount += 1
        self.updatedAt = Date()
    }

    /// 更新最后检查时间
    func updateLastChecked() {
        self.lastCheckedAt = Date()
    }
}
