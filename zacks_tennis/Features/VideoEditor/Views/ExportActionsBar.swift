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
        VStack(spacing: 8) {
            // 状态消息
            if viewModel.isBusy, let message = viewModel.busyStatusMessage {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }

            // 导出按钮
            Button {
                showExportOptions = true
            } label: {
                HStack {
                    if viewModel.isBusy {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                    }

                    Text(viewModel.isBusy ? "导出中..." : "导出")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.isBusy ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.isBusy)
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
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
