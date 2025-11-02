//
//  VideoDetailViewRedesigned.swift
//  zacks_tennis
//
//  视频详情页（重新设计）- 3列网格布局 + 核心统计 + 固定底部导出
//

import SwiftUI
import SwiftData

struct VideoDetailViewRedesigned: View {
    let video: Video
    @Bindable var viewModel: VideoEditorViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedRally: VideoHighlight?
    @State private var showRallyPlayer = false
    @State private var showExportOptions = false
    @State private var showDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 概览数据统计（4宫格）
                OverviewStatsSection(video: video)

                Divider()
                    .padding(.horizontal)

                // 2. 回合网格（3列布局）
                RallyGridSection(
                    rallies: video.highlights,
                    video: video,
                    selectedRally: $selectedRally,
                    showPlayer: $showRallyPlayer
                )

                // 底部留白（为固定导出栏留空间）
                Color.clear
                    .frame(height: 80)
            }
            .padding()
        }
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // 编辑视频标题
                    } label: {
                        Label("编辑标题", systemImage: "pencil")
                    }

                    Button {
                        // 查看分析详情
                    } label: {
                        Label("分析详情", systemImage: "chart.bar")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("删除视频", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // 固定底部导出栏
        .safeAreaInset(edge: .bottom) {
            ExportActionsBar(
                video: video,
                viewModel: viewModel,
                showExportOptions: $showExportOptions
            )
        }
        // 全屏播放器
        .fullScreenCover(isPresented: $showRallyPlayer) {
            if !video.highlights.isEmpty {
                RallyPlayerView(
                    rallies: video.highlights,
                    video: video,
                    selectedRally: $selectedRally
                )
            }
        }
        // 导出选项页
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsView(
                video: video,
                rallies: video.highlights,
                viewModel: viewModel
            )
        }
        // 删除确认
        .alert("删除视频", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteVideo()
            }
        } message: {
            Text("确定要删除这个视频吗？此操作不可撤销。")
        }
    }

    // MARK: - Actions

    private func deleteVideo() {
        modelContext.delete(video)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview("视频详情页（重新设计）") {
    let sampleVideo = createSampleVideo()

    return NavigationStack {
        VideoDetailViewRedesigned(
            video: sampleVideo,
            viewModel: VideoEditorViewModel()
        )
    }
}

// MARK: - Preview Helpers

private func createSampleVideo() -> Video {
    let video = Video(
        title: "网球比赛.mp4",
        originalFilePath: "test.mp4",
        duration: 632.0,
        width: 1920,
        height: 1080,
        fileSize: 52_428_800
    )

    // 模拟已分析状态
    video.isAnalyzed = true
    video.rallyCount = 15
    video.averageRallyDuration = 18.5
    video.longestRallyDuration = 35.0
    video.exportedClipsCount = 2

    // 添加模拟回合数据
    for i in 1...15 {
        let highlight = VideoHighlight(
            video: video,
            rallyNumber: i,
            startTime: Double(i * 10),
            endTime: Double(i * 10 + 15),
            excitementScore: Double.random(in: 40...95),
            videoFilePath: "",
            type: "rally"
        )
        video.highlights.append(highlight)
    }

    return video
}
