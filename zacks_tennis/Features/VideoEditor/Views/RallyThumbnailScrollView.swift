//
//  RallyThumbnailScrollView.swift
//  zacks_tennis
//
//  回合缩略图滚动视图 - TikTok 风格的水平滚动列表
//

import SwiftUI

struct RallyThumbnailScrollView: View {
    let rallies: [VideoHighlight]
    let video: Video
    @Binding var selectedRally: VideoHighlight?

    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var isLoadingThumbnails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Text("精彩回合")
                    .font(.headline)

                Spacer()

                Text("\(rallies.count) 个回合")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // 水平滚动列表
            if rallies.isEmpty {
                emptyStateView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(rallies) { rally in
                            ThumbnailCard(
                                rally: rally,
                                thumbnail: thumbnails[rally.id],
                                isSelected: selectedRally?.id == rally.id
                            )
                            .onTapGesture {
                                selectedRally = rally
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 180)
            }
        }
        .task {
            await loadThumbnails()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("还没有检测到回合")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Load Thumbnails

    private func loadThumbnails() async {
        guard !isLoadingThumbnails else { return }

        isLoadingThumbnails = true
        defer { isLoadingThumbnails = false }

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

            // 生成新缩略图
            do {
                let middleTime = (rally.startTime + rally.endTime) / 2.0
                let thumbnail = try await generator.generateThumbnail(
                    for: videoURL,
                    at: middleTime,
                    size: CGSize(width: 240, height: 135)
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

// MARK: - Thumbnail Card

struct ThumbnailCard: View {
    let rally: VideoHighlight
    let thumbnail: UIImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 缩略图
            ZStack(alignment: .topTrailing) {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 90)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 160, height: 90)
                        .overlay {
                            ProgressView()
                        }
                }

                // 收藏标记
                if rally.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(6)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .padding(6)
                }

                // 时长标签
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        Text(rally.durationText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
            }
            .frame(width: 160, height: 90)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 3)
            )

            // 信息区域
            VStack(alignment: .leading, spacing: 4) {
                // 回合序号和类型
                HStack(spacing: 4) {
                    Text("#\(rally.rallyNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)

                    Text(rally.type)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // 精彩度评分
                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < scoreStars ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundColor(index < scoreStars ? .yellow : .gray)
                    }

                    Spacer()

                    Text("\(Int(rally.excitementScore))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(scoreColor)
                }
            }
            .padding(8)
            .frame(width: 160)
            .background(Color(.systemGray6))
            .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
        }
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Computed Properties

    /// 评分星星数量（0-5）
    private var scoreStars: Int {
        Int(rally.excitementScore / 20.0)
    }

    /// 评分颜色
    private var scoreColor: Color {
        if rally.excitementScore >= 80 {
            return .red
        } else if rally.excitementScore >= 60 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Rounded Corners Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview {
    let sampleRallies = [
        VideoHighlight(
            video: nil,
            rallyNumber: 1,
            startTime: 10.0,
            endTime: 25.0,
            excitementScore: 85,
            videoFilePath: "",
            type: "高强度对抗"
        ),
        VideoHighlight(
            video: nil,
            rallyNumber: 2,
            startTime: 35.0,
            endTime: 48.0,
            excitementScore: 65,
            videoFilePath: "",
            type: "多回合对拉"
        ),
        VideoHighlight(
            video: nil,
            rallyNumber: 3,
            startTime: 60.0,
            endTime: 68.0,
            excitementScore: 45,
            videoFilePath: "",
            type: "快速交锋"
        )
    ]

    let sampleVideo = Video(
        title: "网球比赛.mp4",
        originalFilePath: "test.mp4",
        duration: 300.0,
        width: 1920,
        height: 1080,
        fileSize: 1024 * 1024 * 100
    )

    RallyThumbnailScrollView(
        rallies: sampleRallies,
        video: sampleVideo,
        selectedRally: .constant(nil)
    )
    .padding()
}
