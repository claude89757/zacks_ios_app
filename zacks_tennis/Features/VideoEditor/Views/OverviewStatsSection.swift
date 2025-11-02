//
//  OverviewStatsSection.swift
//  zacks_tennis
//
//  概览数据模块 - 显示视频分析的核心统计指标（4宫格布局）
//

import SwiftUI

/// 概览数据统计部分
struct OverviewStatsSection: View {
    let video: Video

    var body: some View {
        VStack(spacing: 16) {
            // 4宫格统计卡片（2行2列）
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                OverviewStatCard(
                    title: "回合数量",
                    value: "\(video.rallyCount)",
                    icon: "tennis.racket",
                    color: .green
                )

                OverviewStatCard(
                    title: "原视频时长",
                    value: video.durationText,
                    icon: "clock",
                    color: .blue
                )

                OverviewStatCard(
                    title: "剪辑总时长",
                    value: video.totalEditedDurationText,
                    icon: "scissors",
                    color: .orange
                )

                OverviewStatCard(
                    title: "已导出",
                    value: "\(video.exportedClipsCount)",
                    icon: "checkmark.circle",
                    color: .purple
                )
            }
        }
    }
}

/// 概览统计卡片
struct OverviewStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            // 图标
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)

            // 数值
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // 标题
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 预览
#Preview("概览数据模块") {
    OverviewStatsSection(video: Video(
        title: "测试视频",
        originalFilePath: "/test.mp4",
        duration: 632.0,
        width: 1920,
        height: 1080,
        fileSize: 52_428_800
    ))
    .padding()
}
