//
//  NotificationService.swift
//  zacks_tennis
//
//  通知服务 - 管理本地通知和空场提醒
//

import Foundation
import UserNotifications

/// 通知服务
@MainActor
@Observable
class NotificationService {
    static let shared = NotificationService()

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var isAuthorized: Bool = false

    private let center = UNUserNotificationCenter.current()

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - 权限管理

    /// 请求通知权限
    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await checkAuthorizationStatus()
        return granted
    }

    /// 检查当前授权状态
    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - 空场提醒

    /// 为指定的提醒项创建本地通知
    func scheduleNotification(for item: NotificationItem) async throws {
        guard isAuthorized else {
            throw NotificationError.notAuthorized
        }

        // 移除旧的通知
        await removeNotifications(for: item)

        // 为每个时间段创建通知
        for timeSlot in item.timeSlots {
            let components = parseTimeSlot(timeSlot)

            if item.daysOfWeek.isEmpty {
                // 每天重复
                try await scheduleRepeatingNotification(
                    for: item,
                    at: components,
                    daysOfWeek: [1, 2, 3, 4, 5, 6, 7]
                )
            } else {
                // 指定星期几
                try await scheduleRepeatingNotification(
                    for: item,
                    at: components,
                    daysOfWeek: item.daysOfWeek
                )
            }
        }
    }

    /// 创建重复通知
    private func scheduleRepeatingNotification(
        for item: NotificationItem,
        at timeComponents: (hour: Int, minute: Int),
        daysOfWeek: [Int]
    ) async throws {
        for dayOfWeek in daysOfWeek {
            var dateComponents = DateComponents()
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            // Calendar.weekday: 1=周日, 2=周一, ..., 7=周六
            // 我们的 daysOfWeek: 1=周一, ..., 7=周日
            dateComponents.weekday = dayOfWeek == 7 ? 1 : dayOfWeek + 1

            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = "\(item.court?.name ?? "球场")在 \(timeComponents.hour):\(String(format: "%02d", timeComponents.minute)) 可能有空位，快去预约吧！"
            content.sound = .default
            content.badge = 1
            content.categoryIdentifier = "COURT_AVAILABILITY"

            // 添加操作
            content.userInfo = [
                "notificationItemID": item.id.uuidString,
                "courtID": item.court?.id.uuidString ?? ""
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )

            let identifier = "\(item.id.uuidString)_\(dayOfWeek)_\(timeComponents.hour)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            try await center.add(request)
        }
    }

    /// 移除指定提醒项的所有通知
    func removeNotifications(for item: NotificationItem) async {
        let identifiers = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(item.id.uuidString) }
            .map { $0.identifier }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// 创建即时通知（用于测试或即时提醒）
    func sendImmediateNotification(title: String, body: String) async throws {
        guard isAuthorized else {
            throw NotificationError.notAuthorized
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }

    /// 清除所有通知
    func removeAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// 获取待处理的通知数量
    func getPendingNotificationsCount() async -> Int {
        let requests = await center.pendingNotificationRequests()
        return requests.count
    }

    // MARK: - 通知操作

    /// 配置通知操作（打开应用、预约等）
    func configureNotificationActions() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_COURT",
            title: "查看球场",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "关闭",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "COURT_AVAILABILITY",
            actions: [openAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        center.setNotificationCategories([category])
    }

    // MARK: - 辅助方法

    /// 解析时间段字符串（如 "18:00-20:00"）
    private func parseTimeSlot(_ timeSlot: String) -> (hour: Int, minute: Int) {
        let components = timeSlot.split(separator: "-")[0].split(separator: ":")
        let hour = Int(components[0]) ?? 0
        let minute = Int(components[1]) ?? 0
        return (hour, minute)
    }
}

// MARK: - 错误类型
enum NotificationError: LocalizedError {
    case notAuthorized
    case scheduleFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未授权通知权限，请在设置中开启"
        case .scheduleFailed:
            return "创建通知失败"
        }
    }
}
