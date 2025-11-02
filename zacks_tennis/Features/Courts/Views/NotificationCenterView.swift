//
//  NotificationCenterView.swift
//  zacks_tennis
//
//  空场提醒视图 - 管理球场空位提醒订阅
//

import SwiftUI
import SwiftData

struct NotificationCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notifications: [NotificationItem]

    @State private var notificationService = NotificationService.shared
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                if notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationList
                }
            }
            .navigationTitle("空场提醒")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddNotificationView()
            }
            .onAppear {
                Task {
                    await notificationService.checkAuthorizationStatus()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("还没有提醒")
                .font(.title2)
                .fontWeight(.semibold)

            Text("创建提醒，当球场有空位时\n我们会及时通知您")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if !notificationService.isAuthorized {
                Button {
                    Task {
                        _ = try? await notificationService.requestAuthorization()
                    }
                } label: {
                    Label("开启通知权限", systemImage: "bell")
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("创建提醒", systemImage: "plus.circle.fill")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }

    // MARK: - Notification List

    private var notificationList: some View {
        List {
            if !notificationService.isAuthorized {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        VStack(alignment: .leading) {
                            Text("通知权限未开启")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("请在设置中开启通知权限")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            ForEach(notifications) { item in
                NotificationItemRow(item: item)
            }
            .onDelete(perform: deleteItems)
        }
    }

    // MARK: - Actions

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = notifications[index]
            Task {
                await notificationService.removeNotifications(for: item)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview {
    NotificationCenterView()
        .modelContainer(for: [NotificationItem.self, Court.self], inMemory: true)
}
