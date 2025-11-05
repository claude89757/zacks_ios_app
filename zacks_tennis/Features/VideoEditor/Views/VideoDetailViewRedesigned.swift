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

    // 选择模式状态
    @State private var isSelecting = false
    @State private var selectedRallies: Set<VideoHighlight.ID> = []
    @State private var showBatchDeleteAlert = false

    // 调试工具状态
    @State private var showingTimeline = false
    @State private var showingDebugTools = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 回合网格（3列布局）
                RallyGridSection(
                    rallies: video.highlights,
                    video: video,
                    selectedRally: $selectedRally,
                    showPlayer: $showRallyPlayer,
                    isSelecting: $isSelecting,
                    selectedRallies: $selectedRallies
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
            // 选择模式：左侧显示"取消"按钮
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        withAnimation {
                            exitSelectionMode()
                        }
                    }
                }
            }

            // 选择模式：右侧显示"全选/取消全选"按钮
            if isSelecting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selectedRallies.count == video.highlights.count ? "取消全选" : "全选") {
                        toggleSelectAll()
                    }
                }
            }
            // 非选择模式：右侧显示菜单
            else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation {
                                isSelecting = true
                            }
                        } label: {
                            Label("选择", systemImage: "checkmark.circle")
                        }

                        Divider()

                        // 查看时间线
                        Button {
                            showingTimeline = true
                        } label: {
                            Label("查看时间线", systemImage: "chart.bar.xaxis")
                        }
                        .disabled(!video.isAnalyzed || video.highlights.isEmpty)

                        // 导出调试数据
                        Button {
                            showingDebugTools = true
                        } label: {
                            Label("导出调试数据", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(!video.isAnalyzed)

                        Divider()

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
        }
        // 固定底部工具栏
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                // 选择模式：显示选择工具栏
                SelectionToolbar(
                    selectedCount: selectedRallies.count,
                    allSelected: selectedRallies.count == video.highlights.count,
                    onDelete: {
                        showBatchDeleteAlert = true
                    },
                    onToggleFavorite: {
                        batchToggleFavorite()
                    }
                )
            } else {
                // 正常模式：显示导出栏
                ExportActionsBar(
                    video: video,
                    viewModel: viewModel,
                    showExportOptions: $showExportOptions
                )
            }
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
            SimplifiedExportSheet(
                video: video,
                viewModel: viewModel
            )
        }
        // 删除视频确认
        .alert("删除视频", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteVideo()
            }
        } message: {
            Text("确定要删除这个视频吗？此操作不可撤销。")
        }
        // 批量删除确认
        .alert("删除回合", isPresented: $showBatchDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                batchDelete()
            }
        } message: {
            Text("确定要删除选中的 \(selectedRallies.count) 个回合吗？此操作不可撤销。")
        }
        // 时间线弹窗
        .sheet(isPresented: $showingTimeline) {
            TimelineSheetView(video: video)
        }
        // 调试工具弹窗
        .sheet(isPresented: $showingDebugTools) {
            DebugToolsSheetView(video: video)
        }
    }

    // MARK: - Actions

    private func deleteVideo() {
        modelContext.delete(video)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Selection Mode Actions

    /// 退出选择模式
    private func exitSelectionMode() {
        isSelecting = false
        selectedRallies.removeAll()
    }

    /// 全选/取消全选
    private func toggleSelectAll() {
        if selectedRallies.count == video.highlights.count {
            // 当前全选，执行取消全选
            selectedRallies.removeAll()
        } else {
            // 执行全选
            selectedRallies = Set(video.highlights.map { $0.id })
        }
    }

    /// 批量删除
    private func batchDelete() {
        let ralliesToDelete = video.highlights.filter { selectedRallies.contains($0.id) }

        for rally in ralliesToDelete {
            modelContext.delete(rally)
        }

        try? modelContext.save()
        exitSelectionMode()
    }

    /// 批量切换收藏状态
    private func batchToggleFavorite() {
        let selectedHighlights = video.highlights.filter { selectedRallies.contains($0.id) }

        // 如果所有选中项都已收藏，则取消收藏；否则全部收藏
        let allFavorited = selectedHighlights.allSatisfy { $0.isFavorite }

        for highlight in selectedHighlights {
            highlight.isFavorite = !allFavorited
        }

        try? modelContext.save()
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
