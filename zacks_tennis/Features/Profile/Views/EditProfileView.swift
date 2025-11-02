//
//  EditProfileView.swift
//  zacks_tennis
//
//  编辑资料视图
//

import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let user: User?

    @State private var nickname: String = ""
    @State private var email: String = ""
    @State private var skillLevel: String = "中级"

    let skillLevels = ["初级", "中级", "高级", "职业"]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("昵称", text: $nickname)
                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section("技能等级") {
                    Picker("技能等级", selection: $skillLevel) {
                        ForEach(skillLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveProfile()
                    }
                }
            }
            .onAppear {
                nickname = user?.nickname ?? ""
                email = user?.email ?? ""
                skillLevel = user?.skillLevel ?? "中级"
            }
        }
    }

    private func saveProfile() {
        user?.nickname = nickname
        user?.email = email
        user?.skillLevel = skillLevel
        dismiss()
    }
}
