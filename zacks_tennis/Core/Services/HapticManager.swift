//
//  HapticManager.swift
//  zacks_tennis
//
//  触觉反馈管理器 - 统一管理应用内的触觉反馈
//

import UIKit

/// 触觉反馈管理器
/// 提供语义化的触觉反馈方法，统一管理应用内所有触觉交互
final class HapticManager {

    // MARK: - Singleton

    static let shared = HapticManager()

    // MARK: - Generators

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    // MARK: - Initialization

    private init() {
        // 预热所有生成器以减少延迟
        prepareAll()
    }

    // MARK: - Prepare

    /// 预热所有触觉生成器（减少首次触发延迟）
    func prepareAll() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactSoft.prepare()
        impactRigid.prepare()
        selection.prepare()
        notification.prepare()
    }

    // MARK: - Semantic Feedback Methods

    /// 收藏/取消收藏操作
    func favorite() {
        impactMedium.impactOccurred()
    }

    /// 选择/取消选择项目
    func select() {
        selection.selectionChanged()
    }

    /// 进入选择模式（长按触发）
    func enterSelection() {
        impactHeavy.impactOccurred()
    }

    /// 退出选择模式
    func exitSelection() {
        impactLight.impactOccurred()
    }

    /// 操作成功（批量收藏完成、导出成功等）
    func success() {
        notification.notificationOccurred(.success)
    }

    /// 警告提示（删除确认等）
    func warning() {
        notification.notificationOccurred(.warning)
    }

    /// 操作失败
    func error() {
        notification.notificationOccurred(.error)
    }

    /// 击球声标记经过（进度条拖动时）
    func hitMarker() {
        impactLight.impactOccurred()
    }

    /// 播放/暂停切换
    func playPause() {
        impactSoft.impactOccurred()
    }

    /// 快进/快退操作
    func seek() {
        impactLight.impactOccurred()
    }

    /// 滑动切换页面
    func pageChange() {
        impactLight.impactOccurred()
    }

    /// 拖动开始
    func dragStart() {
        impactLight.impactOccurred()
    }

    /// 拖动结束
    func dragEnd() {
        impactMedium.impactOccurred()
    }

    /// 按钮点击（通用）
    func tap() {
        impactLight.impactOccurred()
    }

    /// 重要按钮点击
    func importantTap() {
        impactMedium.impactOccurred()
    }

    /// 全选操作
    func selectAll() {
        impactMedium.impactOccurred()
    }

    // MARK: - Custom Intensity

    /// 自定义强度的轻触觉
    func lightImpact(intensity: CGFloat = 1.0) {
        impactLight.impactOccurred(intensity: intensity)
    }

    /// 自定义强度的中等触觉
    func mediumImpact(intensity: CGFloat = 1.0) {
        impactMedium.impactOccurred(intensity: intensity)
    }

    /// 自定义强度的重触觉
    func heavyImpact(intensity: CGFloat = 1.0) {
        impactHeavy.impactOccurred(intensity: intensity)
    }
}
