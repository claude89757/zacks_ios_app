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
        // 单个导出按钮
        Button {
            showExportOptions = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)

                Text("导出")
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.horizontal)
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
