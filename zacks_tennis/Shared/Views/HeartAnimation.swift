//
//  HeartAnimation.swift
//  zacks_tennis
//
//  收藏心形动画组件 - 双击收藏时的视觉反馈
//

import SwiftUI

/// 收藏心形动画视图
/// 显示放大弹跳的心形动画，带粒子扩散效果
struct HeartAnimation: View {
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var particleOpacity: Double = 1

    /// 动画完成回调
    var onComplete: (() -> Void)?

    /// 心形颜色
    var color: Color = .red

    /// 心形大小
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            // 粒子扩散效果
            ForEach(0..<8) { index in
                ParticleView(
                    index: index,
                    color: color,
                    opacity: particleOpacity
                )
            }

            // 主心形
            Image(systemName: "heart.fill")
                .font(.system(size: size))
                .foregroundColor(color)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            animateHeart()
        }
    }

    private func animateHeart() {
        // 阶段1：心形放大弹跳
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)) {
            scale = 1.3
        }

        // 阶段2：心形回弹
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scale = 1.0
            }
        }

        // 阶段3：粒子扩散
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.5)) {
                particleOpacity = 0
            }
        }

        // 阶段4：心形消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                scale = 0.8
                opacity = 0
            }
        }

        // 动画完成回调
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onComplete?()
        }
    }
}

// MARK: - Particle View

/// 粒子视图
private struct ParticleView: View {
    let index: Int
    let color: Color
    let opacity: Double

    @State private var offset: CGFloat = 0
    @State private var scale: CGFloat = 1

    private var angle: Double {
        Double(index) * 45 // 8个粒子均匀分布
    }

    private var radians: Double {
        angle * .pi / 180
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .offset(
                x: cos(radians) * offset,
                y: sin(radians) * offset
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    offset = 50
                    scale = 0.5
                }
            }
    }
}

// MARK: - Heart Animation Overlay Modifier

/// 心形动画叠加层修饰符
struct HeartAnimationOverlay: ViewModifier {
    @Binding var isShowing: Bool
    var color: Color = .red
    var size: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowing {
                    HeartAnimation(
                        onComplete: {
                            isShowing = false
                        },
                        color: color,
                        size: size
                    )
                }
            }
    }
}

extension View {
    /// 添加心形动画叠加层
    /// - Parameters:
    ///   - isShowing: 控制动画显示的绑定
    ///   - color: 心形颜色
    ///   - size: 心形大小
    func heartAnimation(
        isShowing: Binding<Bool>,
        color: Color = .red,
        size: CGFloat = 80
    ) -> some View {
        modifier(HeartAnimationOverlay(
            isShowing: isShowing,
            color: color,
            size: size
        ))
    }
}

// MARK: - Small Heart Animation (for Cards)

/// 小型心形动画（用于卡片内）
struct SmallHeartAnimation: View {
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 1

    var onComplete: (() -> Void)?

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 40))
            .foregroundColor(.red)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                // 放大
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    scale = 1.2
                }

                // 回弹
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                        scale = 1.0
                    }
                }

                // 消失
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 0.6
                        opacity = 0
                    }
                }

                // 完成回调
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onComplete?()
                }
            }
    }
}

// MARK: - Preview

#Preview("心形动画效果") {
    VStack(spacing: 40) {
        // 大心形动画
        HeartAnimation()
            .frame(width: 200, height: 200)
            .background(Color.black.opacity(0.1))

        // 小心形动画
        SmallHeartAnimation()
            .frame(width: 100, height: 100)
            .background(Color.black.opacity(0.1))
    }
}

#Preview("卡片内心形动画") {
    struct PreviewWrapper: View {
        @State private var showAnimation = false

        var body: some View {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fill)
                .frame(width: 200)
                .cornerRadius(8)
                .heartAnimation(isShowing: $showAnimation)
                .onTapGesture(count: 2) {
                    showAnimation = true
                }
        }
    }

    return PreviewWrapper()
        .padding()
}
