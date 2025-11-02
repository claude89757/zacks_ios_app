//
//  VideoAnalysisDetailView.swift
//  zacks_tennis
//
//  视频分析详情页 - 显示所有回合和统计信息
//

import SwiftUI
import SwiftData

struct VideoAnalysisDetailView: View {
    let video: Video
    @Bindable var viewModel: VideoEditorViewModel
    @State private var selectedRally: VideoHighlight?
    @State private var showingRallyPlayer = false
    @State private var showingExportOptions = false
    @State private var filterOption: FilterOption = .all

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 视频信息卡片
                videoInfoCard

                // 统计信息
                statsSection

                // 过滤选项
                filterSection

                // 回合缩略图列表
                if !video.highlights.isEmpty {
                    RallyThumbnailScrollView(
                        rallies: filteredRallies,
                        video: video,
                        selectedRally: $selectedRally
                    )
                }

                // 回合列表
                rallyListSection
            }
            .padding(.vertical)
        }
        .navigationTitle("分析结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingExportOptions = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(video.highlights.isEmpty)
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(video: video, rallies: filteredRallies, viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingRallyPlayer) {
            RallyPlayerView(
                rallies: filteredRallies,
                video: video,
                selectedRally: $selectedRally
            )
        }
    }

    // MARK: - Video Info Card

    private var videoInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(formatDuration(video.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 处理状态
                if video.isAnalyzed {
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("未处理", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分辨率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(video.width)×\(video.height)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("文件大小")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatFileSize(video.fileSize))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    title: "回合数",
                    value: "\(video.highlights.count)",
                    icon: "number",
                    color: .blue
                )

                StatCard(
                    title: "精彩回合",
                    value: "\(excitingRalliesCount)",
                    icon: "star.fill",
                    color: .yellow
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    title: "平均时长",
                    value: formatDuration(video.averageRallyDuration),
                    icon: "clock.fill",
                    color: .green
                )

                StatCard(
                    title: "最长回合",
                    value: formatDuration(video.longestRallyDuration),
                    icon: "timer",
                    color: .orange
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    title: "收藏",
                    value: "\(favoritesCount)",
                    icon: "heart.fill",
                    color: .red
                )

                StatCard(
                    title: "精彩率",
                    value: String(format: "%.0f%%", excitingRatio * 100),
                    icon: "percent",
                    color: .purple
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("筛选回合")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        FilterChip(
                            title: option.title,
                            icon: option.icon,
                            isSelected: filterOption == option,
                            count: countForFilter(option)
                        )
                        .onTapGesture {
                            filterOption = option
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Rally List Section

    private var rallyListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("回合列表")
                    .font(.headline)

                Spacer()

                if !filteredRallies.isEmpty {
                    Button {
                        selectedRally = filteredRallies.first
                        showingRallyPlayer = true
                    } label: {
                        Label("全部播放", systemImage: "play.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal)

            if filteredRallies.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredRallies) { rally in
                        RallyListCard(rally: rally, video: video)
                            .onTapGesture {
                                selectedRally = rally
                                showingRallyPlayer = true
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.gray)

            Text("没有符合条件的回合")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Computed Properties

    private var filteredRallies: [VideoHighlight] {
        let rallies = video.highlights

        switch filterOption {
        case .all:
            return rallies
        case .favorites:
            return rallies.filter { $0.isFavorite }
        case .exciting:
            return rallies.filter { $0.excitementScore >= 70 }
        case .long:
            return rallies.filter { $0.duration > 10 }
        }
    }

    private var excitingRalliesCount: Int {
        video.highlights.filter { $0.excitementScore >= 70 }.count
    }

    private var favoritesCount: Int {
        video.highlights.filter { $0.isFavorite }.count
    }

    private var excitingRatio: Double {
        guard !video.highlights.isEmpty else { return 0 }
        return Double(excitingRalliesCount) / Double(video.highlights.count)
    }

    private func countForFilter(_ option: FilterOption) -> Int {
        switch option {
        case .all:
            return video.highlights.count
        case .favorites:
            return favoritesCount
        case .exciting:
            return excitingRalliesCount
        case .long:
            return video.highlights.filter { $0.duration > 10 }.count
        }
    }

    // MARK: - Helper Methods

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1024.0 / 1024.0
        if megabytes >= 1024 {
            return String(format: "%.1f GB", megabytes / 1024.0)
        } else {
            return String(format: "%.1f MB", megabytes)
        }
    }
}

// MARK: - Filter Option

enum FilterOption: CaseIterable {
    case all, favorites, exciting, long

    var title: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "收藏"
        case .exciting: return "精彩"
        case .long: return "长回合"
        }
    }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .favorites: return "heart.fill"
        case .exciting: return "star.fill"
        case .long: return "clock.fill"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)

            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)

            Text("\(count)")
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.green : Color(.systemGray6))
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(20)
    }
}

// MARK: - Rally List Card

struct RallyListCard: View {
    let rally: VideoHighlight
    let video: Video

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 60)
                    .cornerRadius(8)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(rally.rallyNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)

                    Text(rally.type)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    if rally.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                HStack(spacing: 8) {
                    Label(rally.durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(scoreColor)

                        Text("\(Int(rally.excitementScore))")
                            .font(.caption)
                            .foregroundColor(scoreColor)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .task {
            await loadThumbnail()
        }
    }

    // MARK: - Computed Properties

    private var scoreColor: Color {
        if rally.excitementScore >= 80 {
            return .red
        } else if rally.excitementScore >= 60 {
            return .orange
        } else {
            return .green
        }
    }

    // MARK: - Helper Methods

    private func loadThumbnail() async {
        // 检查缓存路径
        if let thumbnailPath = rally.thumbnailPath {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let thumbnailURL = documentsURL.appendingPathComponent(thumbnailPath)

            if let data = try? Data(contentsOf: thumbnailURL),
               let image = UIImage(data: data) {
                thumbnail = image
                return
            }
        }

        // 生成新缩略图
        let generator = ThumbnailGenerator.shared
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent(video.originalFilePath)

        do {
            let middleTime = (rally.startTime + rally.endTime) / 2.0
            let image = try await generator.generateThumbnail(
                for: videoURL,
                at: middleTime,
                size: CGSize(width: 200, height: 120)
            )
            thumbnail = image
        } catch {
            print("⚠️ 加载缩略图失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoAnalysisDetailView(
            video: Video(
                title: "网球比赛.mp4",
                originalFilePath: "test.mp4",
                duration: 300.0,
                width: 1920,
                height: 1080,
                fileSize: 1024 * 1024 * 100
            ),
            viewModel: VideoEditorViewModel()
        )
    }
}
