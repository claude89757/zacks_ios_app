//
//  NotificationSettingsView.swift
//  zacks_tennis
//
//  通知设置视图
//

import SwiftUI

struct NotificationSettingsView: View {
    @State private var notificationService = NotificationService.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("通知状态")
                    Spacer()
                    Text(notificationService.isAuthorized ? "已开启" : "未开启")
                        .foregroundColor(notificationService.isAuthorized ? .green : .orange)
                }

                if !notificationService.isAuthorized {
                    Button("前往设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section("提醒类型") {
                Toggle("空场提醒", isOn: .constant(true))
                Toggle("预约提醒", isOn: .constant(true))
                Toggle("活动推送", isOn: .constant(false))
            }
        }
        .navigationTitle("通知设置")
    }
}
