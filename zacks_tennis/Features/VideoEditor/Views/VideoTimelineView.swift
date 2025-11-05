//
//  VideoTimelineView.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  视频时间线可视化 - 展示回合和击球点分布
//

import SwiftUI

struct VideoTimelineView: View {
    let totalDuration: Double
    let rallies: [RallySegment]
    let hitEvents: [(time: Double, confidence: Double)]
    var onTapTime: ((Double) -> Void)? = nil

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0

    // 时间线高度
    private let timelineHeight: CGFloat = 80
    private let hitMarkerHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(.blue)
                Text("击球点时间线")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                // 缩放级别指示器
                if zoomScale > 1.0 {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                        Text(String(format: "%.1f×", zoomScale))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }

                // 缩放提示
                Text(zoomScale == 1.0 ? "捏合缩放 · 点击跳转" : "点击跳转")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            // 时间线画布
            GeometryReader { geometry in
                let canvasWidth = geometry.size.width
                let effectiveWidth = canvasWidth * zoomScale
                let pixelsPerSecond = effectiveWidth / totalDuration

                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // 背景网格
                        timelineBackground(width: effectiveWidth)

                        // 回合段
                        ForEach(rallies.indices, id: \.self) { index in
                            rallySegmentView(
                                rally: rallies[index],
                                pixelsPerSecond: pixelsPerSecond,
                                height: timelineHeight
                            )
                        }

                        // 击球点标记
                        ForEach(hitEvents.indices, id: \.self) { index in
                            hitMarkerView(
                                hitEvent: hitEvents[index],
                                pixelsPerSecond: pixelsPerSecond,
                                timelineHeight: timelineHeight
                            )
                        }

                        // 时间刻度
                        timeScaleView(
                            duration: totalDuration,
                            pixelsPerSecond: pixelsPerSecond,
                            timelineHeight: timelineHeight
                        )
                    }
                    .frame(width: effectiveWidth, height: timelineHeight + 30)
                    .contentShape(Rectangle())  // 使整个区域可点击
                    .onTapGesture { location in
                        // 计算点击位置对应的视频时间
                        let tappedTime = location.x / pixelsPerSecond
                        let clampedTime = min(max(tappedTime, 0), totalDuration)
                        onTapTime?(clampedTime)
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = min(max(value, 1.0), 10.0)
                        }
                )
            }
            .frame(height: timelineHeight + 30)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            // 图例
            legendView()
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Subviews

    /// 时间线背景网格
    private func timelineBackground(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color(.systemBackground))
            .frame(width: width, height: timelineHeight)
    }

    /// 回合段视图
    private func rallySegmentView(rally: RallySegment, pixelsPerSecond: CGFloat, height: CGFloat) -> some View {
        let x = rally.startTime * pixelsPerSecond
        let width = rally.duration * pixelsPerSecond
        let color = excitementColor(score: rally.excitementScore)

        return Rectangle()
            .fill(color.opacity(0.3))
            .frame(width: width, height: height)
            .overlay(
                Rectangle()
                    .stroke(color, lineWidth: 2)
            )
            .offset(x: x, y: 0)
    }

    /// 击球点标记视图
    private func hitMarkerView(hitEvent: (time: Double, confidence: Double), pixelsPerSecond: CGFloat, timelineHeight: CGFloat) -> some View {
        let x = hitEvent.time * pixelsPerSecond
        let color = confidenceColor(confidence: hitEvent.confidence)
        let markerSize = 3.0 + hitEvent.confidence * 5.0  // 3-8 points

        return Circle()
            .fill(color)
            .frame(width: markerSize, height: markerSize)
            .offset(x: x - markerSize / 2, y: timelineHeight / 2 - markerSize / 2)
    }

    /// 时间刻度视图
    private func timeScaleView(duration: Double, pixelsPerSecond: CGFloat, timelineHeight: CGFloat) -> some View {
        let interval = calculateTimeInterval(duration: duration, zoomScale: zoomScale)
        let tickCount = Int(duration / interval) + 1

        return ForEach(0..<tickCount, id: \.self) { index in
            let time = Double(index) * interval
            let x = time * pixelsPerSecond

            VStack(alignment: .center, spacing: 2) {
                // 刻度线
                Rectangle()
                    .fill(Color(.systemGray3))
                    .frame(width: 1, height: 6)

                // 时间标签
                Text(formatTime(time))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .offset(x: x, y: timelineHeight + 2)
        }
    }

    /// 图例
    private func legendView() -> some View {
        HStack(spacing: 16) {
            // 回合精彩度图例
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text("高精彩度")
                    .font(.caption2)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text("中等")
                    .font(.caption2)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text("低精彩度")
                    .font(.caption2)
            }

            Spacer()

            // 击球点图例
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                Text("击球点")
                    .font(.caption2)
            }
        }
        .foregroundColor(.secondary)
    }

    // MARK: - Helper Functions

    /// 根据精彩度返回颜色
    private func excitementColor(score: Double) -> Color {
        if score >= 80 {
            return .red
        } else if score >= 60 {
            return .orange
        } else if score >= 40 {
            return .yellow
        } else {
            return .green
        }
    }

    /// 根据置信度返回颜色
    private func confidenceColor(confidence: Double) -> Color {
        if confidence >= 0.7 {
            return .blue
        } else if confidence >= 0.55 {
            return .cyan
        } else {
            return .gray
        }
    }

    /// 计算时间刻度间隔
    private func calculateTimeInterval(duration: Double, zoomScale: CGFloat) -> Double {
        let baseInterval: Double
        if duration <= 60 {
            baseInterval = 10  // 每10秒
        } else if duration <= 180 {
            baseInterval = 30  // 每30秒
        } else {
            baseInterval = 60  // 每1分钟
        }

        // 根据缩放调整间隔
        if zoomScale > 3.0 {
            return baseInterval / 2
        } else {
            return baseInterval
        }
    }

    /// 格式化时间（分:秒）
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Data Models

struct RallySegment: Identifiable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let excitementScore: Double

    var duration: Double {
        endTime - startTime
    }
}

// MARK: - Video Extension

extension Video {
    /// 转换为时间线回合数据
    var timelineRallies: [RallySegment] {
        highlights.map { highlight in
            RallySegment(
                startTime: highlight.startTime,
                endTime: highlight.endTime,
                excitementScore: highlight.excitementScore
            )
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleRallies = [
        RallySegment(startTime: 10, endTime: 25, excitementScore: 85),
        RallySegment(startTime: 30, endTime: 42, excitementScore: 65),
        RallySegment(startTime: 50, endTime: 68, excitementScore: 45),
        RallySegment(startTime: 75, endTime: 95, excitementScore: 90)
    ]

    let sampleHits: [(time: Double, confidence: Double)] = [
        (10.5, 0.92), (12.1, 0.88), (15.2, 0.75), (18.5, 0.82), (22.0, 0.79),
        (30.2, 0.91), (33.5, 0.87), (36.8, 0.65), (40.1, 0.73),
        (51.0, 0.58), (55.3, 0.62), (60.2, 0.68), (65.5, 0.54),
        (76.2, 0.95), (79.5, 0.93), (82.8, 0.88), (86.1, 0.90), (90.0, 0.85)
    ]

    return ScrollView {
        VStack(spacing: 20) {
            Text("视频分析时间线")
                .font(.title2)
                .fontWeight(.bold)

            VideoTimelineView(
                totalDuration: 120.0,
                rallies: sampleRallies,
                hitEvents: sampleHits
            )

            Spacer()
        }
        .padding()
    }
}
