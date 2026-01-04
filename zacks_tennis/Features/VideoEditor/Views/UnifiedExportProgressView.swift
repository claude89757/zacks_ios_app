//
//  UnifiedExportProgressView.swift
//  zacks_tennis
//
//  统一导出进度视图 - 可作为 sheet 或 overlay 使用
//

import SwiftUI

/// 统一导出进度视图
struct UnifiedExportProgressView: View {
    let exportManager: ExportManager
    let onDismiss: (() -> Void)?
    let onCancel: (() -> Void)?

    @State private var showCancelConfirmation = false

    init(
        exportManager: ExportManager = .shared,
        onDismiss: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.exportManager = exportManager
        self.onDismiss = onDismiss
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { } // 阻止点击穿透

            VStack(spacing: 24) {
                // 状态图标
                statusIcon

                // 标题
                Text(exportManager.state.displayText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                // 进度指示器
                if exportManager.state.isActive {
                    progressSection
                }

                // 错误恢复建议
                if case .failed(let error) = exportManager.state {
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // 操作按钮
                buttonsSection
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 20)
            )
            .padding(.horizontal, 40)
        }
        .confirmationDialog("确认取消", isPresented: $showCancelConfirmation) {
            Button("取消导出", role: .destructive) {
                onCancel?()
            }
            Button("继续导出", role: .cancel) {}
        } message: {
            Text("取消后已导出的部分将被删除")
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch exportManager.state {
        case .idle, .preparing:
            ProgressView()
                .scaleEffect(1.5)
                .frame(width: 80, height: 80)

        case .exporting, .encoding:
            circularProgress

        case .savingToPhotos:
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .frame(width: 80, height: 80)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
                .frame(width: 80, height: 80)

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
                .frame(width: 80, height: 80)

        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
                .frame(width: 80, height: 80)
        }
    }

    private var circularProgress: some View {
        ZStack {
            // 背景圆环
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                .frame(width: 80, height: 80)

            // 进度圆环
            Circle()
                .trim(from: 0, to: exportManager.state.progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: exportManager.state.progress)

            // 百分比文本
            Text("\(Int(exportManager.state.progress * 100))%")
                .font(.headline)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Progress Section

    @ViewBuilder
    private var progressSection: some View {
        VStack(spacing: 12) {
            // 线性进度条
            ProgressView(value: exportManager.state.progress)
                .tint(.blue)

            // 当前操作
            if !exportManager.currentOperation.isEmpty {
                Text(exportManager.currentOperation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 后台导出提示
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("可以切换页面，导出将在后台继续")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.top, 8)
        }
    }

    // MARK: - Buttons Section

    @ViewBuilder
    private var buttonsSection: some View {
        switch exportManager.state {
        case .exporting, .encoding, .savingToPhotos, .preparing:
            // 取消按钮
            Button(role: .destructive) {
                showCancelConfirmation = true
            } label: {
                Label("取消导出", systemImage: "xmark.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
            }

        case .completed, .failed, .cancelled:
            // 完成按钮
            Button {
                onDismiss?()
            } label: {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Compact Version (for status bar or inline display)

/// 紧凑版进度视图 - 用于状态栏或内联显示
struct CompactExportProgressView: View {
    let exportManager: ExportManager

    var body: some View {
        HStack(spacing: 12) {
            // 进度指示器
            if exportManager.state.isActive {
                ProgressView(value: exportManager.state.progress)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else if exportManager.state.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if case .failed = exportManager.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }

            // 状态文本
            Text(exportManager.state.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - Preview

#Preview("导出中") {
    UnifiedExportProgressView(
        exportManager: .shared,
        onDismiss: {},
        onCancel: {}
    )
}

#Preview("紧凑版") {
    CompactExportProgressView(exportManager: .shared)
        .padding()
}
