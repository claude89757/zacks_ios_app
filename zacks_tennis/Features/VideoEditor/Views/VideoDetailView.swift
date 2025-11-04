//
//  VideoDetailView.swift
//  zacks_tennis
//
//  视频详情和剪辑界面 - 显示分析结果和导出精彩片段
//

import SwiftUI
import AVKit

struct VideoDetailView: View {
    let video: Video
    @Bindable var viewModel: VideoEditorViewModel

    @State private var showingExportOptions = false
    @State private var isPlaying = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 视频播放器
                videoPlayerSection

                // 视频信息
                videoInfoSection

                // 🔥 根据分析状态显示不同内容（新逻辑）
                switch video.analysisStatus {
                case "已完成":
                    analysisResultSection
                case "分析中":
                    analysisProgressSection
                case "失败", "已取消":
                    reAnalyzeButtonSection
                case "等待分析":
                    analyzeButtonSection
                default:
                    analyzingPlaceholder
                }

                // 精彩片段列表
                if !video.highlights.isEmpty {
                    highlightsSection
                }

                // 导出选项
                if video.isAnalyzed {
                    exportSection
                }
            }
            .padding()
        }
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        // 编辑标题
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        viewModel.deleteVideo(video)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if viewModel.isAnalyzing && viewModel.selectedVideo?.id == video.id {
                analyzingOverlay
            }

            if viewModel.isExporting {
                exportingOverlay
            }
        }
    }

    // MARK: - Video Player Section

    private var videoPlayerSection: some View {
        VStack {
            if let videoURL = getVideoURL() {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(height: 250)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 250)
                    .overlay {
                        Text("无法加载视频")
                            .foregroundColor(.secondary)
                    }
            }
        }
    }

    // MARK: - Video Info Section

    private var videoInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("时长", systemImage: "clock")
                    .foregroundColor(.secondary)
                Spacer()
                Text(video.durationText)
                    .fontWeight(.medium)
            }

            Divider()

            HStack {
                Label("分辨率", systemImage: "square.resize")
                    .foregroundColor(.secondary)
                Spacer()
                Text(video.resolutionText)
                    .fontWeight(.medium)
            }

            Divider()

            HStack {
                Label("文件大小", systemImage: "externaldrive")
                    .foregroundColor(.secondary)
                Spacer()
                Text(video.fileSizeText)
                    .fontWeight(.medium)
            }

            Divider()

            HStack {
                Label("创建时间", systemImage: "calendar")
                    .foregroundColor(.secondary)
                Spacer()
                Text(video.dateText)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Analyze Button Section

    private var analyzeButtonSection: some View {
        VStack(spacing: 12) {
            Text("使用 AI 分析视频")
                .font(.headline)

            Text("AI 将自动识别精彩回合、击球动作和关键时刻")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.analyzeVideo(video)
                }
            } label: {
                Label("开始分析", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canStartNewTask ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!viewModel.canStartNewTask)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Re-Analyze Button Section

    private var reAnalyzeButtonSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("分析失败")
                .font(.headline)

            Text("视频分析过程中出现错误，请重试")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.analyzeVideo(video)
                }
            } label: {
                Label("重新分析", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canStartNewTask ? Color.orange : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!viewModel.canStartNewTask)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Analysis Progress Section (SIMPLIFIED - 🔥 性能优化)

    private var analysisProgressSection: some View {
        VStack(spacing: 16) {
            // 动画图标
            Image(systemName: "wand.and.stars")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .symbolEffect(.pulse)

            Text("AI 正在分析视频")
                .font(.title3)
                .fontWeight(.semibold)

            // 🔥 简化提示：不再显示详细进度，减少UI刷新
            Text("分析正在后台进行中\n请返回视频列表查看详细进度")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Processing Status Card

    private var processingStatusCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: video.analysisProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(x: 1, y: 2, anchor: .center)

            Text("正在分析中...")
                .font(.headline)

            Text("进度: \(Int(video.analysisProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            if !video.currentAnalysisStage.isEmpty {
                Text(video.currentAnalysisStage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Analyzing Placeholder

    private var analyzingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text("正在准备分析...")
                .font(.headline)

            Text("AI 正在初始化，请稍候")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Analysis Result Section

    private var analysisResultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分析结果")
                .font(.headline)

            HStack(spacing: 20) {
                StatCard(
                    title: "回合数",
                    value: "\(video.rallyCount)",
                    icon: "tennis.racket",
                    color: .blue
                )

                StatCard(
                    title: "精彩片段",
                    value: "\(video.highlights.count)",
                    icon: "star.fill",
                    color: .orange
                )

                if video.exportedClipsCount > 0 {
                    StatCard(
                        title: "已导出",
                        value: "\(video.exportedClipsCount)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("精彩片段")
                .font(.headline)
                .padding(.horizontal)

            ForEach(video.highlights.prefix(10)) { highlight in
                HighlightRowView(highlight: highlight)
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(spacing: 12) {
            Text("导出精彩片段")
                .font(.headline)

            HStack(spacing: 12) {
                ExportButton(title: "Top 5", count: 5) {
                    Task {
                        await viewModel.exportTopHighlights(from: video, count: 5)
                    }
                }
                .opacity(viewModel.canStartNewTask ? 1.0 : 0.5)
                .disabled(!viewModel.canStartNewTask)

                ExportButton(title: "Top 10", count: 10) {
                    Task {
                        await viewModel.exportTopHighlights(from: video, count: 10)
                    }
                }
                .opacity(viewModel.canStartNewTask ? 1.0 : 0.5)
                .disabled(!viewModel.canStartNewTask)
            }

            Button {
                // 自定义导出
            } label: {
                Label("自定义导出", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canStartNewTask ? Color(.systemGray5) : Color(.systemGray6))
                    .foregroundColor(viewModel.canStartNewTask ? .primary : .secondary)
                    .cornerRadius(10)
            }
            .disabled(!viewModel.canStartNewTask)

            // 🔥 新增：忙碌提示
            if !viewModel.canStartNewTask {
                Text(viewModel.busyStatusMessage ?? "")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Overlays

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: viewModel.processingProgress) {
                    Text("AI 分析中...")
                        .font(.headline)
                }
                .frame(width: 200)

                Text(viewModel.currentOperation)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color(.systemGray6))
            .cornerRadius(15)
        }
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: viewModel.processingProgress) {
                    Text("导出中...")
                        .font(.headline)
                }
                .frame(width: 200)

                Text(viewModel.currentOperation)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color(.systemGray6))
            .cornerRadius(15)
        }
    }

    // MARK: - Helper Methods

    private func getVideoURL() -> URL? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(video.originalFilePath)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
}

struct HighlightRowView: View {
    let highlight: VideoHighlight

    var body: some View {
        HStack {
            // 评分标识
            ZStack {
                Circle()
                    .fill(getScoreColor(highlight.excitementScore))
                    .frame(width: 50, height: 50)

                Text("\(Int(highlight.excitementScore))")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.rallyDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(formatTime(highlight.startTime)) - \(formatTime(highlight.endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(highlight.type)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private func getScoreColor(_ score: Double) -> Color {
        if score >= 80 {
            return .green
        } else if score >= 60 {
            return .orange
        } else {
            return .blue
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct ExportButton: View {
    let title: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.title2)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoDetailView(
            video: Video(
                title: "测试视频",
                originalFilePath: "test.mp4",
                duration: 300,
                width: 1920,
                height: 1080,
                fileSize: 50_000_000
            ),
            viewModel: VideoEditorViewModel()
        )
    }
}
