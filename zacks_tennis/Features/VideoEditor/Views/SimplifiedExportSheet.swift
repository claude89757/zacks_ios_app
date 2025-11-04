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
    @State private var showExportProgress = false  // 控制模态进度弹窗
    @State private var showSuccessAlert = false    // 控制成功提示
    @State private var exportedCount = 0           // 导出的视频数量

    var body: some View {
        NavigationStack {
            List {
                // 状态横幅
                if viewModel.isBusy, let message = viewModel.busyStatusMessage {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    // 选项1：最长的10个回合
                    ExportOptionRow(
                        title: "最长的 10 个回合",
                        subtitle: formatDuration(video.getLongestHighlights(count: 10)),
                        icon: "arrow.up.right.circle.fill",
                        color: .blue,
                        isDisabled: viewModel.isBusy
                    ) {
                        exportLongest(10)
                    }

                    // 选项2：最长的5个回合
                    ExportOptionRow(
                        title: "最长的 5 个回合",
                        subtitle: formatDuration(video.getLongestHighlights(count: 5)),
                        icon: "arrow.up.circle.fill",
                        color: .green,
                        isDisabled: viewModel.isBusy
                    ) {
                        exportLongest(5)
                    }

                    // 选项3：收藏的回合
                    ExportOptionRow(
                        title: "收藏的回合",
                        subtitle: "\(video.favoriteHighlights.count) 个回合",
                        icon: "heart.fill",
                        color: .red,
                        isDisabled: video.favoriteHighlights.isEmpty || viewModel.isBusy
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
                        isDisabled: video.highlights.isEmpty || viewModel.isBusy
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
        .alert("导出成功", isPresented: $showSuccessAlert) {
            Button("好的") {
                dismiss()
            }
        } message: {
            if exportedCount == 1 {
                Text("精彩片段已合并并保存到相册")
            } else {
                Text("已导出 \(exportedCount) 个视频到相册")
            }
        }
        .overlay {
            // 模态进度弹窗（导出时显示）
            if showExportProgress {
                ExportProgressDialog(viewModel: viewModel)
            }
        }
    }

    // MARK: - Actions

    private func exportLongest(_ count: Int) {
        Task {
            // 显示模态进度弹窗
            showExportProgress = true

            await viewModel.exportLongestHighlights(from: video, count: count)

            // 隐藏进度弹窗
            showExportProgress = false

            // 如果导出成功，显示成功提示
            if !viewModel.showError && viewModel.exportedFileCount > 0 {
                exportedCount = viewModel.exportedFileCount
                showSuccessAlert = true
            }
            // 错误提示会自动通过 onChange 显示
        }
    }

    private func exportFavorites() {
        guard !video.favoriteHighlights.isEmpty else { return }
        Task {
            // 显示模态进度弹窗
            showExportProgress = true

            await viewModel.exportFavoriteHighlights(from: video)

            // 隐藏进度弹窗
            showExportProgress = false

            // 如果导出成功，显示成功提示
            if !viewModel.showError && viewModel.exportedFileCount > 0 {
                exportedCount = viewModel.exportedFileCount
                showSuccessAlert = true
            }
            // 错误提示会自动通过 onChange 显示
        }
    }

    private func exportWithBallAnnotations() {
        guard !video.highlights.isEmpty else { return }
        Task {
            // 显示模态进度弹窗
            showExportProgress = true

            await viewModel.exportWithBallAnnotations(from: video)

            // 隐藏进度弹窗
            showExportProgress = false

            // 如果导出成功，显示成功提示
            if !viewModel.showError && viewModel.exportedFileCount > 0 {
                exportedCount = viewModel.exportedFileCount
                showSuccessAlert = true
            }
            // 错误提示会自动通过 onChange 显示
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
