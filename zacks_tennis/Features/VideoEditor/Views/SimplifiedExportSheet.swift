//
//  SimplifiedExportSheet.swift
//  zacks_tennis
//
//  简化版导出选项页 - 提供3个快捷导出选项
//

import SwiftUI

/// 简化版导出选项Sheet
struct SimplifiedExportSheet: View {
    let video: Video
    @Bindable var viewModel: VideoEditorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showExportError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // 选项1：最长的10个回合
                    ExportOptionRow(
                        title: "最长的 10 个回合",
                        subtitle: formatDuration(video.getLongestHighlights(count: 10)),
                        icon: "arrow.up.right.circle.fill",
                        color: .blue
                    ) {
                        exportLongest(10)
                    }

                    // 选项2：最长的5个回合
                    ExportOptionRow(
                        title: "最长的 5 个回合",
                        subtitle: formatDuration(video.getLongestHighlights(count: 5)),
                        icon: "arrow.up.circle.fill",
                        color: .green
                    ) {
                        exportLongest(5)
                    }

                    // 选项3：收藏的回合
                    ExportOptionRow(
                        title: "收藏的回合",
                        subtitle: "\(video.favoriteHighlights.count) 个回合",
                        icon: "heart.fill",
                        color: .red,
                        isDisabled: video.favoriteHighlights.isEmpty
                    ) {
                        exportFavorites()
                    }
                } header: {
                    Text("快捷导出")
                }

                // 调试选项
                Section {
                    // 选项4：导出带网球标注的视频（调试用）
                    ExportOptionRow(
                        title: "导出带网球标注视频",
                        subtitle: "显示网球轨迹和检测框（调试用）",
                        icon: "scope",
                        color: .orange,
                        isDisabled: video.highlights.isEmpty
                    ) {
                        exportWithBallAnnotations()
                    }
                } header: {
                    Text("调试工具")
                } footer: {
                    Text("导出的视频将包含网球检测框、轨迹线和速度信息，方便调优检测参数")
                }
            }
            .navigationTitle("导出选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: viewModel.showError) { _, newValue in
            if newValue {
                showExportError = true
            }
        }
        .alert("导出失败", isPresented: $showExportError, presenting: viewModel.errorMessage) { _ in
            Button("确定", role: .cancel) {
                showExportError = false
                viewModel.showError = false
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Actions

    private func exportLongest(_ count: Int) {
        Task {
            await viewModel.exportLongestHighlights(from: video, count: count)
            // 只在导出成功时才关闭Sheet，让用户能看到错误提示
            if !viewModel.showError {
                dismiss()
            }
        }
    }

    private func exportFavorites() {
        guard !video.favoriteHighlights.isEmpty else { return }
        Task {
            await viewModel.exportFavoriteHighlights(from: video)
            // 只在导出成功时才关闭Sheet，让用户能看到错误提示
            if !viewModel.showError {
                dismiss()
            }
        }
    }

    private func exportWithBallAnnotations() {
        guard !video.highlights.isEmpty else { return }
        Task {
            await viewModel.exportWithBallAnnotations(from: video)
            // 只在导出成功时才关闭Sheet，让用户能看到错误提示
            if !viewModel.showError {
                dismiss()
            }
        }
    }

    // MARK: - Helper

    private func formatDuration(_ highlights: [VideoHighlight]) -> String {
        let totalSeconds = Int(highlights.reduce(0.0) { $0 + $1.duration })
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "总时长 %d:%02d", minutes, seconds)
    }
}

// MARK: - Export Option Row

struct ExportOptionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 图标
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isDisabled ? .gray : color)
                    .frame(width: 40, height: 40)
                    .background(isDisabled ? Color.gray.opacity(0.1) : color.opacity(0.1))
                    .cornerRadius(8)

                // 文本
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isDisabled ? .secondary : .primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 箭头
                if !isDisabled {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .disabled(isDisabled)
    }
}

// MARK: - Preview

#Preview("简化导出选项") {
    SimplifiedExportSheetPreview()
}

private struct SimplifiedExportSheetPreview: View {
    @State private var viewModel = VideoEditorViewModel()

    var body: some View {
        SimplifiedExportSheet(
            video: createSampleVideoForPreview(),
            viewModel: viewModel
        )
    }
}

// MARK: - Preview Helper

private func createSampleVideoForPreview() -> Video {
    let sampleVideo = Video(
        title: "网球比赛.mp4",
        originalFilePath: "test.mp4",
        duration: 632.0,
        width: 1920,
        height: 1080,
        fileSize: 52_428_800
    )

    // 添加模拟数据
    for i in 1...15 {
        let highlight = VideoHighlight(
            video: sampleVideo,
            rallyNumber: i,
            startTime: Double(i * 10),
            endTime: Double(i * 10) + Double.random(in: 10...30),
            excitementScore: Double.random(in: 40...95),
            videoFilePath: "",
            type: "rally"
        )
        if i <= 3 {
            highlight.isFavorite = true
        }
        sampleVideo.highlights.append(highlight)
    }

    return sampleVideo
}
