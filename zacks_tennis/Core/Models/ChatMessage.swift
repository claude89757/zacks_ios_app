//
//  ChatMessage.swift
//  zacks_tennis
//
//  聊天消息模型
//

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date = Date()
}
