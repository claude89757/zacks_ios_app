//
//  VideoEditorView.swift
//  zacks_tennis
//
//  AI 视频剪辑主视图 - 视频列表和管理界面
//

import SwiftUI
import SwiftData
import PhotosUI

struct VideoEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = VideoEditorViewModel()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingVideoPicker = false
    @State private var selectedVideo: Video?
    @State private var showGlobalError = false

    var body: some View {
        NavigationStack {
            // 🔥 始终显示列表视图，确保第一次和第二次导入体验一致
            videoListView
                .overlay {
                    // 仅在列表真正为空且不在导入时显示空状态
                    if viewModel.videos.isEmpty && !viewModel.isImporting {
                        emptyStateOverlay
                    }
                }
            .navigationTitle("AI 视频剪辑")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .videos,
                        preferredItemEncoding: .current  // 🚀 优化：使用当前编码，避免自动转码
                    ) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.canStartNewTask ? .green : .gray)
                    }
                    .disabled(!viewModel.canStartNewTask)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                if let newValue {
                    Task {
                        await viewModel.importVideo(from: newValue)
                        selectedPhotoItem = nil
                    }
                }
            }
            .onChange(of: viewModel.showError) { _, newValue in
                if newValue {
                    showGlobalError = true
                }
            }
            .onAppear {
                viewModel.configure(modelContext: modelContext)
            }
            .alert("错误", isPresented: $showGlobalError) {
                Button("确定", role: .cancel) {
                    showGlobalError = false
                    viewModel.showError = false
                }
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
        }
    }

    // MARK: - Empty State Overlay

    /// 空状态覆盖层（仅在真正为空且不在导入时显示）
    private var emptyStateOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("还没有视频")
                .font(.title2)
                .fontWeight(.semibold)

            Text("点击右上角的 ➕ 按钮导入网球视频\n开始智能分析和剪辑")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))  // 🔥 添加背景色覆盖下面的空列表
    }

    // MARK: - Video List

    private var videoListView: some View {
        List {
            ForEach(viewModel.videos) { video in
                NavigationLink(value: video) {
                    VideoRowView(video: video, viewModel: viewModel)
                }
                .disabled(video.isImporting || video.isAnalyzing)  // 🔥 禁止点击正在导入/分析的视频
            }
            .onDelete(perform: deleteVideos)
        }
        .navigationDestination(for: Video.self) { video in
            VideoDetailViewRedesigned(video: video, viewModel: viewModel)
        }
    }

    // MARK: - Actions

    private func deleteVideos(at offsets: IndexSet) {
        for index in offsets {
            viewModel.deleteVideo(viewModel.videos[index])
        }
    }
}

// MARK: - Video Row View

struct VideoRowView: View {
    let video: Video
    var viewModel: VideoEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                // 缩略图
                ZStack {
                    if let thumbnailPath = video.thumbnailPath,
                       let thumbnail = loadThumbnail(path: thumbnailPath) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "video")
                                    .font(.title)
                                    .foregroundColor(.gray)
                            }
                    }

                    // 导入/分析中的遮罩
                    if video.isImporting || video.isAnalyzing {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 80, height: 80)
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    }
                }

                // 信息
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title)
                        .font(.headline)
                        .lineLimit(1)

                    HStack {
                        Text(video.durationText)
                        Text("·")
                        Text(video.resolutionText)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    // 状态
                    HStack {
                        Circle()
                            .fill(viewModel.getStatusColor(for: video))
                            .frame(width: 8, height: 8)

                        Text(viewModel.getStatusText(for: video))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 右侧信息
                VStack(alignment: .trailing, spacing: 4) {
                    if video.isAnalyzed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Text(video.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .opacity(video.isImporting || video.isAnalyzing ? 0.5 : 1.0)  // 🔥 只对主内容区域降低透明度

            // 🔥 导入/分析进度条（新增）
            if video.isImporting || video.isAnalyzing {
                VStack(spacing: 8) {
                    Divider()

                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                // 当前阶段
                                Text(video.currentAnalysisStage.isEmpty ? (video.isImporting ? "正在导入..." : "正在分析...") : video.currentAnalysisStage)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)

                                // 进度条
                                ProgressView(value: video.analysisProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .tint(.blue)
                            }

                            // 百分比
                            Text("\(Int(video.analysisProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }

                        // 💡 温馨提示
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)

                            Text(video.isImporting ? "正在导入视频，请稍候..." : "为保证分析质量，建议停留在当前页面")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func loadThumbnail(path: String) -> UIImage? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let thumbnailURL = documentsURL.appendingPathComponent(path)

        guard let data = try? Data(contentsOf: thumbnailURL) else {
            return nil
        }

        return UIImage(data: data)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoEditorView()
            .modelContainer(for: [Video.self], inMemory: true)
    }
}
