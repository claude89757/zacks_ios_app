//
//  RallyGridSection.swift
//  zacks_tennis
//
//  回合网格模块 - 3列网格布局展示所有回合视频
//

import SwiftUI

/// 回合网格展示部分
struct RallyGridSection: View {
    let rallies: [VideoHighlight]
    let video: Video
    @Binding var selectedRally: VideoHighlight?
    @Binding var showPlayer: Bool

    @State private var thumbnails: [UUID: UIImage] = [:]

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

            // 3列网格
            if rallies.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(rallies) { rally in
                        RallyGridCard(
                            rally: rally,
                            thumbnail: thumbnails[rally.id]
                        )
                        .onTapGesture {
                            selectedRally = rally
                            showPlayer = true
                        }
                    }
                }
            }
        }
        .task {
            await loadThumbnails()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("还没有检测到回合")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
}

// MARK: - Rally Grid Card

/// 3列网格回合卡片（简化版，专注于缩略图展示）
struct RallyGridCard: View {
    let rally: VideoHighlight
    let thumbnail: UIImage?

    var body: some View {
        ZStack {
            // 缩略图
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fill)
                    .overlay {
                        ProgressView()
                    }
            }

            // 渐变遮罩（增强文字可读性）
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            // 信息叠加层
            VStack {
                // 顶部：收藏标记
                HStack {
                    Spacer()

                    if rally.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(4)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Circle())
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
        .cornerRadius(8)
        .clipped()
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
        showPlayer: .constant(false)
    )
    .padding()
}
