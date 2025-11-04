//
//  MainTabView.swift
//  zacks_tennis
//
//  主标签页导航 - 应用的核心导航结构
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab: Tab = .videoEditor

    var body: some View {
        TabView(selection: $selectedTab) {
            // 1. 网球场信息 (已注释)
//            CourtInfoView()
//                .tabItem {
//                    Label("场地", systemImage: "tennis.racket")
//                }
//                .tag(Tab.courts)

            // 2. AI 视频剪辑
            VideoEditorView()
                .tabItem {
                    Label("视频", systemImage: "video.badge.checkmark")
                }
                .tag(Tab.videoEditor)

            // 3. AI 聊天助手 (已注释)
//            AIChatView()
//                .tabItem {
//                    Label("ZACKS", systemImage: "message.badge.filled.fill")
//                }
//                .tag(Tab.aiChat)

            // 4. 用户资料 (已注释)
//            ProfileView()
//                .tabItem {
//                    Label("我的", systemImage: "person.circle")
//                }
//                .tag(Tab.profile)

            // 5. 算法说明
            AlgorithmDescriptionView()
                .tabItem {
                    Label("说明", systemImage: "doc.text.image")
                }
                .tag(Tab.description)
        }
        .accentColor(.green) // 网球主题色
    }
}

// MARK: - Tab 枚举
extension MainTabView {
    enum Tab {
        case courts
        case aiChat
        case videoEditor
        case profile
        case description
    }
}

// MARK: - 预览
#Preview {
    MainTabView()
        .modelContainer(for: [Court.self, User.self, NotificationItem.self, Video.self], inMemory: true)
}
