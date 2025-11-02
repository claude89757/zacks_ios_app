//
//  AIChatView.swift
//  zacks_tennis
//
//  AI 聊天助手视图 - ZACKS 智能助手
//

import SwiftUI

struct AIChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 消息列表
                if messages.isEmpty {
                    emptyStateView
                } else {
                    messagesList
                }

                // 输入框
                inputBar
            }
            .navigationTitle("ZACKS 助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            messages.removeAll()
                        } label: {
                            Label("清空对话", systemImage: "trash")
                        }

                        Button {
                            // 设置
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                if messages.isEmpty {
                    addWelcomeMessage()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.badge.filled.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("你好！我是 ZACKS")
                .font(.title2)
                .fontWeight(.semibold)

            Text("您的智能网球助手\n我可以帮您预约球场、解答问题")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SuggestionButton(text: "附近有哪些网球场？") {
                    sendMessage("附近有哪些网球场？")
                }

                SuggestionButton(text: "如何提高发球质量？") {
                    sendMessage("如何提高发球质量？")
                }

                SuggestionButton(text: "帮我找明天晚上的球场") {
                    sendMessage("帮我找明天晚上的球场")
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                                .padding()
                            Text("ZACKS 正在思考...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("输入消息...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button {
                sendMessage(inputText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty ? .gray : .green)
            }
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 5, y: -2)
    }

    // MARK: - Helper Methods

    private func addWelcomeMessage() {
        let welcome = ChatMessage(
            role: "assistant",
            content: "你好！我是 ZACKS，您的智能网球助手。\n\n我可以帮您：\n• 查找和预约网球场\n• 设置空场提醒\n• 解答网球相关问题\n• 分析您的视频\n\n有什么可以帮到您的吗？"
        )
        messages.append(welcome)
    }

    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        // 添加用户消息
        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)
        inputText = ""

        // 模拟 AI 响应
        isLoading = true

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒延迟

            let response = generateMockResponse(for: text)
            let aiMessage = ChatMessage(role: "assistant", content: response)

            await MainActor.run {
                messages.append(aiMessage)
                isLoading = false
            }
        }
    }

    private func generateMockResponse(for userMessage: String) -> String {
        if userMessage.contains("球场") || userMessage.contains("场地") {
            return "我找到了您附近的几个网球场：\n\n1. 东方网球中心 - 12片硬地场\n2. 朝阳公园网球场 - 8片场地\n3. 奥森网球中心 - 10片场地\n\n您想了解哪个球场的详细信息？"
        } else if userMessage.contains("发球") {
            return "提高发球质量的几个要点：\n\n1. 抛球要稳定，高度适中\n2. 击球点要在身体前上方\n3. 手腕要放松，利用鞭打动作\n4. 落地后跟进到位\n\n需要我为您推荐一些教学视频吗？"
        } else {
            return "我理解您的问题了。这是一个很好的问题！\n\n由于我目前还在开发中，更复杂的功能正在完善。您可以尝试：\n• 查看网球场信息\n• 设置空场提醒\n• 使用 AI 视频剪辑功能\n\n还有什么我可以帮您的吗？"
        }
    }
}

// MARK: - Preview

#Preview {
    AIChatView()
}
