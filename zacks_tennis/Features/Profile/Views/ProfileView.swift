//
//  ProfileView.swift
//  zacks_tennis
//
//  用户资料视图 - 个人信息、设置和统计数据
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    @State private var showingEditProfile = false

    var currentUser: User? {
        users.first
    }

    var body: some View {
        NavigationStack {
            List {
                // 用户信息卡片
                Section {
                    userInfoCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // 统计数据
                Section("使用统计") {
                    StatRow(
                        icon: "video.fill",
                        title: "视频处理",
                        value: "\(currentUser?.videoProcessCount ?? 0) 次",
                        color: .blue
                    )

                    StatRow(
                        icon: "star.fill",
                        title: "收藏场地",
                        value: "\(currentUser?.favoriteCourtsCount ?? 0) 个",
                        color: .yellow
                    )

                    StatRow(
                        icon: "message.fill",
                        title: "AI 对话",
                        value: "\(currentUser?.aiChatCount ?? 0) 次",
                        color: .green
                    )
                }

                // 偏好设置
                Section("偏好设置") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("通知设置", systemImage: "bell")
                    }

                    NavigationLink {
                        Text("场地偏好设置页面")
                    } label: {
                        Label("场地偏好", systemImage: "tennis.racket")
                    }
                }

                // 关于
                Section("关于") {
                    NavigationLink {
                        Text("关于 Zacks 网球")
                    } label: {
                        Label("关于 Zacks 网球", systemImage: "info.circle")
                    }

                    NavigationLink {
                        Text("帮助与反馈")
                    } label: {
                        Label("帮助与反馈", systemImage: "questionmark.circle")
                    }

                    HStack {
                        Label("版本", systemImage: "app.badge")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                // 开发者选项（调试用）
                if ProcessInfo.processInfo.environment["DEBUG_MODE"] != nil {
                    Section("开发者选项") {
                        Button {
                            addSampleData()
                        } label: {
                            Label("添加示例数据", systemImage: "plus.circle")
                        }

                        Button(role: .destructive) {
                            clearAllData()
                        } label: {
                            Label("清空所有数据", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(user: currentUser)
            }
            .onAppear {
                ensureUserExists()
            }
        }
    }

    // MARK: - User Info Card

    private var userInfoCard: some View {
        VStack(spacing: 16) {
            // 头像
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Text(currentUser?.displayName.prefix(1).uppercased() ?? "Z")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }

            // 用户名
            VStack(spacing: 4) {
                Text(currentUser?.displayName ?? "网球爱好者")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(currentUser?.email ?? "未设置邮箱")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 技能等级
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                Text(currentUser?.skillLevel ?? "中级")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(20)

            // 编辑按钮
            Button {
                showingEditProfile = true
            } label: {
                Text("编辑资料")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding()
    }

    // MARK: - Helper Methods

    private func ensureUserExists() {
        if users.isEmpty {
            let newUser = User(
                username: "用户\(Int.random(in: 1000...9999))",
                email: nil,
                skillLevel: "中级"
            )
            modelContext.insert(newUser)
            try? modelContext.save()
        }
    }

    private func addSampleData() {
        // 添加示例数据
        guard let user = currentUser else { return }

        user.videoProcessCount = Int.random(in: 5...50)
        user.aiChatCount = Int.random(in: 10...100)
        user.favoriteCourtsCount = Int.random(in: 3...15)

        try? modelContext.save()
    }

    private func clearAllData() {
        // 清空所有数据（谨慎使用）
        try? modelContext.delete(model: Court.self)
        try? modelContext.delete(model: Video.self)
        try? modelContext.delete(model: NotificationItem.self)
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
        .modelContainer(for: [User.self, Court.self, Video.self], inMemory: true)
}
