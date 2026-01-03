//
//  RallyGridSection.swift
//  zacks_tennis
//
//  回合网格模块 - 3列网格布局展示所有回合视频
//  UX优化: 骨架屏、长按选择、双击收藏、触觉反馈、VoiceOver
//

import SwiftUI
import SwiftData

/// 回合网格展示部分
struct RallyGridSection: View {
    let rallies: [VideoHighlight]
    let video: Video
    @Binding var selectedRally: VideoHighlight?
    @Binding var showPlayer: Bool
    @Binding var isSelecting: Bool
    @Binding var selectedRallies: Set<VideoHighlight.ID>

    @Environment(\.modelContext) private var modelContext

    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var showHeartAnimation: UUID? = nil

    // 捏合手势缩放（网格列数）
    @AppStorage("rallyGridColumnCount") private var columnCount = 3
    @GestureState private var magnificationScale: CGFloat = 1.0

    /// 动态列配置
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Text("全部回合")
                    .font(.headline)

                Spacer()

                Text("\(rallies.count) 个回合")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 动态网格（支持捏合缩放）
            if rallies.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(rallies) { rally in
                        RallyGridCard(
                            rally: rally,
                            thumbnail: thumbnails[rally.id],
                            isSelecting: isSelecting,
                            isSelected: selectedRallies.contains(rally.id),
                            showHeartAnimation: showHeartAnimation == rally.id
                        )
                        .onTapGesture {
                            handleTap(rally)
                        }
                        .onTapGesture(count: 2) {
                            handleDoubleTap(rally)
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            handleLongPress(rally)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: rally))
                        .accessibilityHint(accessibilityHint)
                        .accessibilityAddTraits(rally.isFavorite ? .isSelected : [])
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .updating($magnificationScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { scale in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if scale > 1.2 {
                                    // 放大手势 → 减少列数（最少2列）
                                    columnCount = max(2, columnCount - 1)
                                } else if scale < 0.8 {
                                    // 缩小手势 → 增加列数（最多4列）
                                    columnCount = min(4, columnCount + 1)
                                }
                            }
                        }
                )
            }
        }
        .task {
            await loadThumbnails()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .symbolEffect(.pulse)

            Text("还没有检测到回合")
                .font(.headline)
                .foregroundColor(.primary)

            Text("请先对视频进行 AI 分析")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Gesture Handlers

    /// 单击处理
    private func handleTap(_ rally: VideoHighlight) {
        if isSelecting {
            toggleSelection(rally.id)
            HapticManager.shared.select()
        } else {
            selectedRally = rally
            showPlayer = true
        }
    }

    /// 双击收藏处理
    private func handleDoubleTap(_ rally: VideoHighlight) {
        guard !isSelecting else { return }

        // 切换收藏状态
        rally.isFavorite.toggle()
        try? modelContext.save()

        // 显示心形动画
        showHeartAnimation = rally.id
        HapticManager.shared.favorite()

        // 动画结束后隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showHeartAnimation = nil
        }
    }

    /// 长按进入选择模式
    private func handleLongPress(_ rally: VideoHighlight) {
        guard !isSelecting else { return }

        HapticManager.shared.enterSelection()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isSelecting = true
            selectedRallies.insert(rally.id)
        }
    }

    // MARK: - Load Thumbnails

    private func loadThumbnails() async {
        let generator = ThumbnailGenerator.shared
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent(video.originalFilePath)

        for rally in rallies {
            // 检查是否已有缓存的缩略图路径
            if let thumbnailPath = rally.thumbnailPath,
               let thumbnail = loadThumbnailFromPath(thumbnailPath) {
                thumbnails[rally.id] = thumbnail
                continue
            }

            // 生成新缩略图（3列布局使用更小的尺寸）
            do {
                let middleTime = (rally.startTime + rally.endTime) / 2.0
                let thumbnail = try await generator.generateThumbnail(
                    for: videoURL,
                    at: middleTime,
                    size: CGSize(width: 220, height: 124) // 3列布局优化尺寸
                )
                thumbnails[rally.id] = thumbnail
            } catch {
                print("⚠️ 生成缩略图失败: \(error.localizedDescription)")
            }
        }
    }

    private func loadThumbnailFromPath(_ path: String) -> UIImage? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let thumbnailURL = documentsURL.appendingPathComponent(path)

        guard let data = try? Data(contentsOf: thumbnailURL) else {
            return nil
        }

        return UIImage(data: data)
    }

    // MARK: - Selection Actions

    /// 切换选中状态
    private func toggleSelection(_ id: VideoHighlight.ID) {
        if selectedRallies.contains(id) {
            selectedRallies.remove(id)
        } else {
            selectedRallies.insert(id)
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for rally: VideoHighlight) -> String {
        var label = "回合 \(rally.rallyNumber), 时长 \(rally.durationText), 精彩度 \(Int(rally.excitementScore))分"
        if rally.isFavorite {
            label += ", 已收藏"
        }
        return label
    }

    private var accessibilityHint: String {
        if isSelecting {
            return "双击选择或取消选择"
        } else {
            return "双击播放, 长按选择, 双击两次收藏"
        }
    }
}

// MARK: - Rally Grid Card

/// 3列网格回合卡片（带骨架屏、收藏动画、视觉增强）
struct RallyGridCard: View {
    let rally: VideoHighlight
    let thumbnail: UIImage?
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var showHeartAnimation: Bool = false

    var body: some View {
        ZStack {
            // 缩略图或骨架屏
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } else {
                // 骨架屏加载效果
                RallyCardSkeleton()
            }

            // 渐变遮罩（增强文字可读性）
            if thumbnail != nil {
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // 信息叠加层
            if thumbnail != nil {
                VStack {
                    // 顶部：左侧勾选框 + 右侧收藏标记
                    HStack {
                        // 左侧：勾选框（选择模式）
                        if isSelecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundColor(isSelected ? .white : .white)
                                .padding(8)
                                .background(isSelected ? Color.blue : Color.black.opacity(0.5))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                .padding(4)
                        }

                        Spacer()

                        // 右侧：收藏标记
                        if rally.isFavorite && !isSelecting {
                            Image(systemName: "heart.fill")
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .padding(6)
                                .background(Color.white.opacity(0.95))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .padding(4)
                        }
                    }

                    Spacer()

                    // 底部：回合序号和时长
                    HStack(alignment: .bottom) {
                        // 左下：回合序号
                        Text("#\(rally.rallyNumber)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green)
                            .cornerRadius(4)

                        Spacer()

                        // 右下：时长
                        Text(rally.durationText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    .padding(6)
                }
            }

            // 双击收藏心形动画
            if showHeartAnimation {
                SmallHeartAnimation()
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .clipped()
    }

    /// 边框颜色：选中蓝色 > 收藏红色 > 透明
    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if rally.isFavorite && !isSelecting {
            return Color.red.opacity(0.5)
        } else {
            return .clear
        }
    }

    /// 边框宽度
    private var borderWidth: CGFloat {
        if isSelected {
            return 3
        } else if rally.isFavorite && !isSelecting {
            return 2
        } else {
            return 0
        }
    }
}

// MARK: - Preview

#Preview("回合网格模块") {
    let sampleRallies = (1...12).map { i in
        VideoHighlight(
            video: nil,
            rallyNumber: i,
            startTime: Double(i * 10),
            endTime: Double(i * 10 + 15),
            excitementScore: Double.random(in: 40...95),
            videoFilePath: "",
            type: "rally"
        )
    }

    let sampleVideo = Video(
        title: "网球比赛.mp4",
        originalFilePath: "test.mp4",
        duration: 300.0,
        width: 1920,
        height: 1080,
        fileSize: 1024 * 1024 * 100
    )

    RallyGridSection(
        rallies: sampleRallies,
        video: sampleVideo,
        selectedRally: .constant(nil),
        showPlayer: .constant(false),
        isSelecting: .constant(false),
        selectedRallies: .constant([])
    )
    .padding()
}

#Preview("骨架屏加载") {
    LazyVGrid(columns: [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ], spacing: 8) {
        ForEach(0..<9) { _ in
            RallyCardSkeleton()
        }
    }
    .padding()
}
