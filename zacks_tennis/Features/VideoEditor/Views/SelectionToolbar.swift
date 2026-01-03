//
//  SelectionToolbar.swift
//  zacks_tennis
//
//  选择模式底部工具栏 - 显示已选数量和批量操作按钮
//  UX优化: 视觉增强、动画、VoiceOver支持
//

import SwiftUI

/// 选择模式底部工具栏
struct SelectionToolbar: View {
    let selectedCount: Int
    let allSelected: Bool
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    /// 是否有选中项
    private var hasSelection: Bool {
        selectedCount > 0
    }

    var body: some View {
        HStack(spacing: 16) {
            // 左侧：已选数量
            HStack(spacing: 6) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundColor(hasSelection ? .blue : .gray)
                    .font(.body)
                    .symbolEffect(.bounce, value: selectedCount)

                Text("已选 \(selectedCount) 项")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(hasSelection ? .primary : .secondary)
                    .contentTransition(.numericText(value: Double(selectedCount)))
                    .animation(.spring(response: 0.3), value: selectedCount)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("已选中 \(selectedCount) 个回合")

            Spacer()

            // 右侧：操作按钮
            HStack(spacing: 12) {
                // 收藏/取消收藏按钮
                Button {
                    onToggleFavorite()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.body)
                        Text("收藏")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(hasSelection ? .red : .gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(hasSelection ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(!hasSelection)
                .accessibilityLabel("收藏选中的 \(selectedCount) 个回合")
                .accessibilityHint(hasSelection ? "双击收藏" : "请先选择回合")

                // 删除按钮
                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.body)
                        Text("删除")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(hasSelection ? Color.red : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!hasSelection)
                .accessibilityLabel("删除选中的 \(selectedCount) 个回合")
                .accessibilityHint(hasSelection ? "双击删除，需要确认" : "请先选择回合")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Preview

#Preview("选择工具栏 - 已选3项") {
    SelectionToolbar(
        selectedCount: 3,
        allSelected: false,
        onDelete: {},
        onToggleFavorite: {}
    )
}

#Preview("选择工具栏 - 全选") {
    SelectionToolbar(
        selectedCount: 10,
        allSelected: true,
        onDelete: {},
        onToggleFavorite: {}
    )
}

#Preview("选择工具栏 - 未选中") {
    SelectionToolbar(
        selectedCount: 0,
        allSelected: false,
        onDelete: {},
        onToggleFavorite: {}
    )
}

#Preview("选择工具栏 - 交互") {
    struct PreviewWrapper: View {
        @State private var count = 0

        var body: some View {
            VStack {
                Spacer()

                HStack(spacing: 20) {
                    Button("减少") {
                        if count > 0 { count -= 1 }
                    }
                    Button("增加") {
                        count += 1
                    }
                }

                Spacer()

                SelectionToolbar(
                    selectedCount: count,
                    allSelected: count >= 10,
                    onDelete: {},
                    onToggleFavorite: {}
                )
            }
        }
    }

    return PreviewWrapper()
}
