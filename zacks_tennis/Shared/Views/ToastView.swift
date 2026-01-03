//
//  ToastView.swift
//  zacks_tennis
//
//  Toast 提示组件 - 轻量级操作反馈
//

import SwiftUI

/// Toast 提示视图
struct ToastView: View {
    let message: String
    let icon: String
    var iconColor: Color = .white
    var backgroundColor: Color = Color.black.opacity(0.85)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(25)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Toast Modifier

/// Toast 叠加层修饰符
struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let icon: String
    var iconColor: Color = .white
    var duration: Double = 2.0
    var position: ToastPosition = .top

    func body(content: Content) -> some View {
        content
            .overlay(alignment: position.alignment) {
                if isShowing {
                    ToastView(
                        message: message,
                        icon: icon,
                        iconColor: iconColor
                    )
                    .padding(position.padding)
                    .transition(position.transition)
                    .zIndex(999)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isShowing = false
                            }
                        }
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowing)
    }
}

/// Toast 位置
enum ToastPosition {
    case top
    case center
    case bottom

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }

    var padding: EdgeInsets {
        switch self {
        case .top: return EdgeInsets(top: 60, leading: 16, bottom: 0, trailing: 16)
        case .center: return EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        case .bottom: return EdgeInsets(top: 0, leading: 16, bottom: 100, trailing: 16)
        }
    }

    var transition: AnyTransition {
        switch self {
        case .top:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        case .center:
            return .scale.combined(with: .opacity)
        case .bottom:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        }
    }
}

// MARK: - View Extension

extension View {
    /// 添加 Toast 提示
    /// - Parameters:
    ///   - isShowing: 控制显示的绑定
    ///   - message: 提示消息
    ///   - icon: SF Symbol 图标名称
    ///   - iconColor: 图标颜色
    ///   - duration: 显示时长（秒）
    ///   - position: 显示位置
    func toast(
        isShowing: Binding<Bool>,
        message: String,
        icon: String = "checkmark.circle.fill",
        iconColor: Color = .green,
        duration: Double = 2.0,
        position: ToastPosition = .top
    ) -> some View {
        modifier(ToastModifier(
            isShowing: isShowing,
            message: message,
            icon: icon,
            iconColor: iconColor,
            duration: duration,
            position: position
        ))
    }
}

// MARK: - Preset Toast Types

extension View {
    /// 成功提示 Toast
    func successToast(isShowing: Binding<Bool>, message: String) -> some View {
        toast(
            isShowing: isShowing,
            message: message,
            icon: "checkmark.circle.fill",
            iconColor: .green
        )
    }

    /// 收藏成功 Toast
    func favoriteToast(isShowing: Binding<Bool>, count: Int, isFavorited: Bool) -> some View {
        toast(
            isShowing: isShowing,
            message: isFavorited ? "已收藏 \(count) 个回合" : "已取消收藏 \(count) 个回合",
            icon: isFavorited ? "heart.fill" : "heart.slash",
            iconColor: isFavorited ? .red : .gray
        )
    }

    /// 删除成功 Toast
    func deleteToast(isShowing: Binding<Bool>, count: Int) -> some View {
        toast(
            isShowing: isShowing,
            message: "已删除 \(count) 个回合",
            icon: "trash.fill",
            iconColor: .red
        )
    }

    /// 错误提示 Toast
    func errorToast(isShowing: Binding<Bool>, message: String) -> some View {
        toast(
            isShowing: isShowing,
            message: message,
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange
        )
    }

    /// 信息提示 Toast
    func infoToast(isShowing: Binding<Bool>, message: String) -> some View {
        toast(
            isShowing: isShowing,
            message: message,
            icon: "info.circle.fill",
            iconColor: .blue
        )
    }
}

// MARK: - Toast Manager (for programmatic use)

/// Toast 管理器（用于程序化调用）
@MainActor
@Observable
final class ToastManager {
    static let shared = ToastManager()

    var isShowing: Bool = false
    var message: String = ""
    var icon: String = "checkmark.circle.fill"
    var iconColor: Color = .green

    private init() {}

    func show(
        message: String,
        icon: String = "checkmark.circle.fill",
        iconColor: Color = .green,
        duration: Double = 2.0
    ) {
        self.message = message
        self.icon = icon
        self.iconColor = iconColor

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isShowing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeOut(duration: 0.3)) {
                self.isShowing = false
            }
        }
    }

    func showSuccess(_ message: String) {
        show(message: message, icon: "checkmark.circle.fill", iconColor: .green)
    }

    func showError(_ message: String) {
        show(message: message, icon: "exclamationmark.triangle.fill", iconColor: .orange)
    }

    func showFavorite(count: Int, isFavorited: Bool) {
        let msg = isFavorited ? "已收藏 \(count) 个回合" : "已取消收藏 \(count) 个回合"
        let icon = isFavorited ? "heart.fill" : "heart.slash"
        let color: Color = isFavorited ? .red : .gray
        show(message: msg, icon: icon, iconColor: color)
    }

    func showDelete(count: Int) {
        show(message: "已删除 \(count) 个回合", icon: "trash.fill", iconColor: .red)
    }
}

// MARK: - Preview

#Preview("Toast 样式") {
    VStack(spacing: 20) {
        ToastView(message: "操作成功", icon: "checkmark.circle.fill", iconColor: .green)
        ToastView(message: "已收藏 3 个回合", icon: "heart.fill", iconColor: .red)
        ToastView(message: "已删除 2 个回合", icon: "trash.fill", iconColor: .red)
        ToastView(message: "加载失败", icon: "exclamationmark.triangle.fill", iconColor: .orange)
        ToastView(message: "已复制到剪贴板", icon: "doc.on.doc.fill", iconColor: .blue)
    }
    .padding()
}

#Preview("Toast 交互") {
    struct PreviewWrapper: View {
        @State private var showSuccessToast = false
        @State private var showFavoriteToast = false
        @State private var showDeleteToast = false

        var body: some View {
            VStack(spacing: 20) {
                Button("显示成功提示") {
                    showSuccessToast = true
                }

                Button("显示收藏提示") {
                    showFavoriteToast = true
                }

                Button("显示删除提示") {
                    showDeleteToast = true
                }
            }
            .successToast(isShowing: $showSuccessToast, message: "操作成功")
            .favoriteToast(isShowing: $showFavoriteToast, count: 3, isFavorited: true)
            .deleteToast(isShowing: $showDeleteToast, count: 2)
        }
    }

    return PreviewWrapper()
}
