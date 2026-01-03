//
//  SkeletonView.swift
//  zacks_tennis
//
//  骨架屏组件 - 提供 Shimmer 加载动画效果
//

import SwiftUI

// MARK: - Skeleton Modifier

/// 骨架屏 Shimmer 动画修饰符
struct SkeletonModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    var isActive: Bool = true
    var baseColor: Color = Color.gray.opacity(0.3)
    var highlightColor: Color = Color.gray.opacity(0.1)
    var duration: Double = 1.5

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geometry in
                        LinearGradient(
                            gradient: Gradient(colors: [
                                baseColor,
                                highlightColor,
                                baseColor
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: phase * geometry.size.width)
                    }
                    .clipped()
                }
            }
            .onAppear {
                guard isActive else { return }
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// 添加骨架屏 Shimmer 动画效果
    /// - Parameters:
    ///   - isActive: 是否激活动画
    ///   - baseColor: 基础颜色
    ///   - highlightColor: 高亮颜色
    ///   - duration: 动画周期（秒）
    func skeleton(
        isActive: Bool = true,
        baseColor: Color = Color.gray.opacity(0.3),
        highlightColor: Color = Color.gray.opacity(0.1),
        duration: Double = 1.5
    ) -> some View {
        modifier(SkeletonModifier(
            isActive: isActive,
            baseColor: baseColor,
            highlightColor: highlightColor,
            duration: duration
        ))
    }
}

// MARK: - Skeleton Placeholder Views

/// 矩形骨架占位符
struct SkeletonRectangle: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.3))
            .skeleton()
    }
}

/// 圆形骨架占位符
struct SkeletonCircle: View {
    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .skeleton()
    }
}

/// 缩略图骨架占位符（16:9 比例）
struct SkeletonThumbnail: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(16/9, contentMode: .fill)
            .skeleton()
    }
}

/// 回合卡片骨架占位符（完整布局）
struct RallyCardSkeleton: View {
    var body: some View {
        ZStack {
            // 缩略图占位
            SkeletonThumbnail()

            // 渐变遮罩
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )

            // 信息叠加层
            VStack {
                Spacer()

                HStack(alignment: .bottom) {
                    // 左下：回合序号占位
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 32, height: 20)

                    Spacer()

                    // 右下：时长占位
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 40, height: 18)
                }
                .padding(6)
            }
        }
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview("骨架屏效果") {
    VStack(spacing: 20) {
        // 单个矩形
        SkeletonRectangle()
            .frame(height: 100)

        // 圆形
        SkeletonCircle()
            .frame(width: 60, height: 60)

        // 缩略图
        SkeletonThumbnail()
            .frame(height: 120)

        // 完整卡片
        RallyCardSkeleton()
            .frame(height: 120)

        // 网格布局
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(0..<6) { _ in
                RallyCardSkeleton()
            }
        }
    }
    .padding()
}
