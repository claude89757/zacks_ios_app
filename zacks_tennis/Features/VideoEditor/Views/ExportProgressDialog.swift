//
//  ExportProgressDialog.swift
//  zacks_tennis
//
//  模态导出进度弹窗 - 阻止用户交互，显示导出进度
//

import SwiftUI

struct ExportProgressDialog: View {
    @Bindable var viewModel: VideoEditorViewModel

    var body: some View {
        ZStack {
            // 半透明背景，覆盖整个屏幕
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .allowsHitTesting(true) // 阻止点击穿透

            // 进度卡片
            VStack(spacing: 24) {
                // 标题
                Text("正在导出视频")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // 进度指示器
                VStack(spacing: 16) {
                    // 旋转动画（表示正在处理）
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)

                    // 进度条和百分比
                    if viewModel.processingProgress > 0 {
                        VStack(spacing: 8) {
                            // 进度条
                            ProgressView(value: viewModel.processingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                .frame(height: 8)
                                .background(Color.white.opacity(0.3))
                                .cornerRadius(4)

                            // 百分比
                            Text("\(Int(viewModel.processingProgress * 100))%")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: 200)
                    }

                    // 当前操作文本
                    if !viewModel.currentOperation.isEmpty {
                        Text(viewModel.currentOperation)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // 重要提示
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("请勿退出应用")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .font(.callout)

                    Text("导出过程中请保持应用打开")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .systemGray6).opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .allowsHitTesting(true) // 确保整个视图阻止底层交互
    }
}

// 预览
#Preview {
    @Previewable @State var viewModel = VideoEditorViewModel()

    ZStack {
        // 模拟背景内容
        Color.blue.ignoresSafeArea()

        ExportProgressDialog(viewModel: viewModel)
            .onAppear {
                viewModel.processingProgress = 0.65
                viewModel.currentOperation = "正在导出第 3/10 个视频..."
            }
    }
}
