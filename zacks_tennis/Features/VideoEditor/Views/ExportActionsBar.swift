//
//  ExportActionsBar.swift
//  zacks_tennis
//
//  固定底部导出栏 - 提供快捷导出功能
//

import SwiftUI

/// 固定底部导出操作栏
struct ExportActionsBar: View {
    let video: Video
    let viewModel: VideoEditorViewModel
    @Binding var showExportOptions: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 主按钮：导出精彩片段
            Button {
                showExportOptions = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)

                    Text("导出精彩片段")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // 快捷导出菜单
            Menu {
                Button {
                    quickExportTop(5)
                } label: {
                    Label("Top 5 精彩回合", systemImage: "star.fill")
                }

                Button {
                    quickExportTop(10)
                } label: {
                    Label("Top 10 精彩回合", systemImage: "star.fill")
                }

                Divider()

                Button {
                    quickExportAll()
                } label: {
                    Label("全部回合", systemImage: "video.stack")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 50, height: 50)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
    }

    // MARK: - Quick Export Actions

    private func quickExportTop(_ count: Int) {
        Task {
            await viewModel.exportTopHighlights(from: video, count: count)
        }
    }

    private func quickExportAll() {
        Task {
            await viewModel.exportCustomHighlights(from: video, highlights: video.highlights)
        }
    }
}

// MARK: - Preview

#Preview("导出操作栏") {
    let sampleVideo = Video(
        title: "网球比赛.mp4",
        originalFilePath: "test.mp4",
        duration: 300.0,
        width: 1920,
        height: 1080,
        fileSize: 1024 * 1024 * 100
    )

    ExportActionsBar(
        video: sampleVideo,
        viewModel: VideoEditorViewModel(),
        showExportOptions: .constant(false)
    )
}
