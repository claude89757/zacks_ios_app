//
//  SelectionToolbar.swift
//  zacks_tennis
//
//  选择模式底部工具栏 - 显示已选数量和批量操作按钮
//

import SwiftUI

/// 选择模式底部工具栏
struct SelectionToolbar: View {
    let selectedCount: Int
    let allSelected: Bool
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 左侧：已选数量
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.body)

                Text("已选 \(selectedCount) 项")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

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
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(selectedCount == 0)

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
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .disabled(selectedCount == 0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
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

#Preview("选择工具栏 - 未选中") {
    SelectionToolbar(
        selectedCount: 0,
        allSelected: false,
        onDelete: {},
        onToggleFavorite: {}
    )
}
