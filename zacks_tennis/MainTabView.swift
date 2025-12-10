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
            // 1. AI 视频剪辑
            VideoEditorView()
                .tabItem {
                    Label("视频", systemImage: "video.badge.checkmark")
                }
                .tag(Tab.videoEditor)

            // 2. 算法说明
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
        case videoEditor
        case description
    }
}

// MARK: - 预览
#Preview {
    MainTabView()
        .modelContainer(for: [Video.self], inMemory: true)
}
