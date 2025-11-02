//
//  Court.swift
//  zacks_tennis
//
//  网球场模型 - 存储网球场基本信息和预定方式
//

import Foundation
import SwiftData

@Model
final class Court {
    /// 唯一标识符
    var id: UUID

    /// 场地名称
    var name: String

    /// 所在城市
    var city: String

    /// 详细地址
    var address: String

    /// 经度
    var latitude: Double?

    /// 纬度
    var longitude: Double?

    /// 场地描述
    var courtDescription: String

    /// 场地数量
    var courtCount: Int

    /// 地面类型 (硬地/红土/草地)
    var surfaceType: String

    /// 是否室内
    var isIndoor: Bool

    /// 预定方式 (URL Scheme 或微信小程序路径)
    var bookingMethod: String

    /// 预定链接
    var bookingURL: String?

    /// 微信小程序 AppID
    var wechatMiniProgramAppID: String?

    /// 微信小程序路径
    var wechatMiniProgramPath: String?

    /// 联系电话
    var phoneNumber: String?

    /// 价格范围
    var priceRange: String

    /// 营业时间
    var openingHours: String

    /// 设施特色 (灯光/停车/淋浴等)
    var facilities: [String]

    /// 是否收藏
    var isFavorite: Bool

    /// 创建时间
    var createdAt: Date

    /// 更新时间
    var updatedAt: Date

    /// 关联的空场提醒
    @Relationship(deleteRule: .cascade, inverse: \NotificationItem.court)
    var notifications: [NotificationItem]?

    init(
        name: String,
        city: String,
        address: String,
        courtDescription: String = "",
        courtCount: Int = 1,
        surfaceType: String = "硬地",
        isIndoor: Bool = false,
        bookingMethod: String = "电话预约",
        priceRange: String = "¥100-200/小时",
        openingHours: String = "06:00-22:00",
        facilities: [String] = []
    ) {
        self.id = UUID()
        self.name = name
        self.city = city
        self.address = address
        self.courtDescription = courtDescription
        self.courtCount = courtCount
        self.surfaceType = surfaceType
        self.isIndoor = isIndoor
        self.bookingMethod = bookingMethod
        self.priceRange = priceRange
        self.openingHours = openingHours
        self.facilities = facilities
        self.isFavorite = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - 便利方法
extension Court {
    /// 获取完整的位置信息
    var fullAddress: String {
        "\(city) \(address)"
    }

    /// 是否支持微信小程序预定
    var supportsWeChatMiniProgram: Bool {
        wechatMiniProgramAppID != nil && wechatMiniProgramPath != nil
    }

    /// 获取预定 URL（如果有）
    func getBookingURL() -> URL? {
        if let bookingURL = bookingURL {
            return URL(string: bookingURL)
        }
        return nil
    }
}
