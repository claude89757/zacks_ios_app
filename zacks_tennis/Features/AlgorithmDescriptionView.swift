//
//  AlgorithmDescriptionView.swift
//  zacks_tennis
//
//  视频剪辑算法说明页面 - 展示三种算法方案
//

import SwiftUI

struct AlgorithmDescriptionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 三张算法卡片
                    AlgorithmCard(
                        algorithm: .audioOnly,
                        isActive: true
                    )

                    AlgorithmCard(
                        algorithm: .visionOnly,
                        isActive: false
                    )

                    AlgorithmCard(
                        algorithm: .hybrid,
                        isActive: false
                    )
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("视频剪辑算法")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - 算法卡片
struct AlgorithmCard: View {
    let algorithm: AlgorithmType
    let isActive: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 卡片头部
            HStack(alignment: .top, spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(iconBackgroundGradient)
                        .frame(width: 56, height: 56)

                    Image(systemName: algorithm.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(isActive ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    // 标题和状态徽章
                    HStack {
                        Text(algorithm.title)
                            .font(.title3.bold())
                            .foregroundStyle(isActive ? .primary : .secondary)

                        Spacer()

                        StatusBadge(status: algorithm.status, isActive: isActive)
                    }

                    // 副标题
                    Text(algorithm.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(isActive ? .secondary : .tertiary)
                }
            }

            Divider()
                .opacity(isActive ? 1 : 0.5)

            // 工作原理
            DetailRow(
                icon: "gearshape.2.fill",
                title: "工作原理",
                content: algorithm.howItWorks,
                isActive: isActive
            )

            // 优势
            DetailRow(
                icon: "checkmark.circle.fill",
                title: "优势",
                content: algorithm.pros,
                isActive: isActive,
                color: .green
            )

            // 劣势
            DetailRow(
                icon: "exclamationmark.triangle.fill",
                title: "劣势",
                content: algorithm.cons,
                isActive: isActive,
                color: .orange
            )

            // 技术难度
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(isActive ? .blue : .secondary)
                Text("技术难度:")
                    .font(.subheadline.bold())
                    .foregroundStyle(isActive ? .primary : .secondary)

                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(
                                index < algorithm.difficulty
                                    ? (isActive ? .yellow : .gray)
                                    : .gray.opacity(0.3)
                            )
                    }
                }

                Spacer()

                Text(algorithm.difficultyText)
                    .font(.caption.bold())
                    .foregroundStyle(isActive ? .secondary : .tertiary)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(borderGradient, lineWidth: isActive ? 2 : 1)
        )
        .shadow(
            color: isActive ? shadowColor : .clear,
            radius: isActive ? 20 : 0,
            x: 0,
            y: isActive ? 10 : 0
        )
        .opacity(isActive ? 1 : 0.6)
        .scaleEffect(isActive ? 1 : 0.98)
    }

    // MARK: - 样式计算属性

    private var iconBackgroundGradient: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [algorithm.primaryColor, algorithm.secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.gray.opacity(0.3), .gray.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        algorithm.primaryColor.opacity(0.08),
                        algorithm.secondaryColor.opacity(0.05),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var borderGradient: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [algorithm.primaryColor.opacity(0.6), algorithm.secondaryColor.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var shadowColor: Color {
        algorithm.primaryColor.opacity(0.3)
    }
}

// MARK: - 详细信息行
struct DetailRow: View {
    let icon: String
    let title: String
    let content: String
    let isActive: Bool
    var color: Color = .blue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(isActive ? color : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(isActive ? .primary : .secondary)

                Text(content)
                    .font(.footnote)
                    .foregroundStyle(isActive ? .secondary : .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 状态徽章
struct StatusBadge: View {
    let status: String
    let isActive: Bool

    var body: some View {
        Text(status)
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? .green.opacity(0.2) : .gray.opacity(0.15))
            )
            .foregroundStyle(isActive ? .green : .secondary)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? .green.opacity(0.4) : .gray.opacity(0.3),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - 算法类型定义
enum AlgorithmType {
    case audioOnly
    case visionOnly
    case hybrid

    var title: String {
        switch self {
        case .audioOnly: return "音频智能检测"
        case .visionOnly: return "计算机视觉检测"
        case .hybrid: return "音频+视觉融合"
        }
    }

    var subtitle: String {
        switch self {
        case .audioOnly: return "听声识别击球"
        case .visionOnly: return "AI 视觉识别"
        case .hybrid: return "声音+视觉双保险"
        }
    }

    var status: String {
        switch self {
        case .audioOnly: return "已实现 · 调优中"
        case .visionOnly: return "规划中"
        case .hybrid: return "未来功能"
        }
    }

    var icon: String {
        switch self {
        case .audioOnly: return "waveform"
        case .visionOnly: return "eye.fill"
        case .hybrid: return "sparkles"
        }
    }

    var howItWorks: String {
        switch self {
        case .audioOnly:
            return "识别击球的\"啪\"声，自动找出多次击球组成的回合"
        case .visionOnly:
            return "通过摄像头识别网球运动轨迹和球员动作"
        case .hybrid:
            return "先用声音快速定位，再用视觉验证是否真实击球"
        }
    }

    var pros: String {
        switch self {
        case .audioOnly:
            return "速度快、省电、晚上打球也能用"
        case .visionOnly:
            return "更准确、能分析动作姿势"
        case .hybrid:
            return "又快又准、适应各种场景"
        }
    }

    var cons: String {
        switch self {
        case .audioOnly:
            return "环境太吵可能误判、无法区分是否有效击球"
        case .visionOnly:
            return "比较耗电、光线不好时效果差"
        case .hybrid:
            return "开发难度大、比较耗资源"
        }
    }

    var difficulty: Int {
        switch self {
        case .audioOnly: return 2
        case .visionOnly: return 4
        case .hybrid: return 5
        }
    }

    var difficultyText: String {
        switch self {
        case .audioOnly: return "中等"
        case .visionOnly: return "困难"
        case .hybrid: return "非常困难"
        }
    }

    var primaryColor: Color {
        switch self {
        case .audioOnly: return .green
        case .visionOnly: return .blue
        case .hybrid: return .purple
        }
    }

    var secondaryColor: Color {
        switch self {
        case .audioOnly: return .blue
        case .visionOnly: return .cyan
        case .hybrid: return .pink
        }
    }
}

// MARK: - 预览
#Preview {
    AlgorithmDescriptionView()
}
