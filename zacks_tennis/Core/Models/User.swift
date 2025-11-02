//
//  User.swift
//  zacks_tennis
//
//  用户模型 - 存储用户个人信息和偏好设置
//

import Foundation
import SwiftData

@Model
final class User {
    /// 唯一标识符
    var id: UUID

    /// 用户名
    var username: String

    /// 昵称
    var nickname: String

    /// 头像 URL
    var avatarURL: String?

    /// 邮箱
    var email: String?

    /// 手机号
    var phoneNumber: String?

    /// 性别
    var gender: String?

    /// 出生日期
    var birthDate: Date?

    /// 所在城市
    var city: String?

    /// 网球水平 (初级/中级/高级/职业)
    var skillLevel: String

    /// 个人简介
    var bio: String

    /// 注册时间
    var registeredAt: Date

    /// 最后登录时间
    var lastLoginAt: Date

    // MARK: - 偏好设置

    /// 是否启用通知
    var notificationsEnabled: Bool

    /// 是否启用邮件提醒
    var emailNotificationsEnabled: Bool

    /// 偏好的场地类型
    var preferredSurfaceType: String?

    /// 偏好的时间段
    var preferredTimeSlots: [String]

    /// 关注的城市列表
    var followedCities: [String]

    // MARK: - 统计数据

    /// 视频处理次数
    var videoProcessCount: Int

    /// 收藏的场地数量
    var favoriteCourtsCount: Int

    /// AI 对话次数
    var aiChatCount: Int

    init(
        username: String,
        nickname: String? = nil,
        email: String? = nil,
        skillLevel: String = "中级"
    ) {
        self.id = UUID()
        self.username = username
        self.nickname = nickname ?? username
        self.email = email
        self.skillLevel = skillLevel
        self.bio = ""
        self.registeredAt = Date()
        self.lastLoginAt = Date()

        // 默认偏好设置
        self.notificationsEnabled = true
        self.emailNotificationsEnabled = false
        self.preferredTimeSlots = ["18:00-20:00"]
        self.followedCities = []

        // 初始化统计数据
        self.videoProcessCount = 0
        self.favoriteCourtsCount = 0
        self.aiChatCount = 0
    }
}

// MARK: - 便利方法
extension User {
    /// 获取显示名称
    var displayName: String {
        nickname.isEmpty ? username : nickname
    }

    /// 更新最后登录时间
    func updateLastLogin() {
        self.lastLoginAt = Date()
    }

    /// 增加视频处理计数
    func incrementVideoProcessCount() {
        self.videoProcessCount += 1
    }

    /// 增加 AI 对话计数
    func incrementAIChatCount() {
        self.aiChatCount += 1
    }
}
