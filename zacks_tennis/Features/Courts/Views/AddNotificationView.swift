//
//  AddNotificationView.swift
//  zacks_tennis
//
//  添加提醒视图
//

import SwiftUI

struct AddNotificationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("提醒名称", text: .constant(""))
                }

                Section("监控设置") {
                    Text("选择球场、时间段等设置...")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        dismiss()
                    }
                }
            }
        }
    }
}
