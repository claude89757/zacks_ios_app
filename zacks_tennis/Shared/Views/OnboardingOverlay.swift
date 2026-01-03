//
//  OnboardingOverlay.swift
//  zacks_tennis
//
//  新手引导覆盖层组件 - 首次使用播放器时显示操作指南
//

import SwiftUI

/// 播放器新手引导覆盖层
struct PlayerOnboardingOverlay: View {
    @Binding var isShowing: Bool
    @AppStorage("hasSeenPlayerOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissOnboarding()
                }

            VStack(spacing: 36) {
                // 标题
                VStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                        .symbolEffect(.pulse)

                    Text("操作指南")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("轻松掌握播放器操作")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                // 引导项列表
                VStack(spacing: 20) {
                    OnboardingItem(
                        icon: "arrow.up.arrow.down",
                        iconColor: .blue,
                        title: "上下滑动",
                        description: "切换到上一个或下一个片段"
                    )

                    OnboardingItem(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "双击屏幕中央",
                        description: "快速收藏/取消收藏当前片段"
                    )

                    OnboardingItem(
                        icon: "gobackward.5",
                        iconColor: .orange,
                        title: "双击屏幕左侧/右侧",
                        description: "快退/快进 5 秒"
                    )

                    OnboardingItem(
                        icon: "play.fill",
                        iconColor: .green,
                        title: "点击屏幕",
                        description: "暂停/播放视频"
                    )

                    OnboardingItem(
                        icon: "gauge.with.dots.needle.67percent",
                        iconColor: .purple,
                        title: "点击速度按钮",
                        description: "切换播放速度 (0.5x ~ 2x)"
                    )
                }

                Spacer()

                // 确认按钮
                Button {
                    dismissOnboarding()
                } label: {
                    HStack(spacing: 8) {
                        Text("知道了")
                            .font(.headline)
                        Image(systemName: "checkmark")
                            .font(.headline)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                // 底部提示
                Text("点击任意位置关闭")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func dismissOnboarding() {
        HapticManager.shared.tap()
        hasSeenOnboarding = true
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
        }
    }
}

/// 引导项视图
struct OnboardingItem: View {
    let icon: String
    var iconColor: Color = .green
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

            // 文字
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer()
        }
    }
}

// MARK: - View Extension

extension View {
    /// 添加播放器新手引导覆盖层
    func playerOnboarding(isShowing: Binding<Bool>) -> some View {
        overlay {
            if isShowing.wrappedValue {
                PlayerOnboardingOverlay(isShowing: isShowing)
            }
        }
    }
}

// MARK: - Preview

#Preview("新手引导") {
    ZStack {
        Color.black.ignoresSafeArea()

        PlayerOnboardingOverlay(isShowing: .constant(true))
    }
}

#Preview("引导项") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            OnboardingItem(
                icon: "arrow.up.arrow.down",
                iconColor: .blue,
                title: "上下滑动",
                description: "切换到上一个或下一个片段"
            )

            OnboardingItem(
                icon: "heart.fill",
                iconColor: .red,
                title: "双击屏幕中央",
                description: "快速收藏/取消收藏"
            )
        }
        .padding()
    }
}
