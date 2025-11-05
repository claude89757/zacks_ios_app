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
    @State private var showingTimeline = false
    @State private var showingDebugTools = false
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
            // 调试工具菜单
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // 查看时间线
                    Button {
                        showingTimeline = true
                    } label: {
                        Label("查看时间线", systemImage: "chart.bar.xaxis")
                    }
                    .disabled(!video.isAnalyzed || video.highlights.isEmpty)

                    // 导出调试数据
                    Button {
                        showingDebugTools = true
                    } label: {
                        Label("导出调试数据", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(!video.isAnalyzed)
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .imageScale(.large)
                }
            }

            // 原有的导出按钮
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingExportOptions = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(video.highlights.isEmpty)
            }
        }
        .sheet(isPresented: $showingTimeline) {
            TimelineSheetView(video: video)
        }
        .sheet(isPresented: $showingDebugTools) {
            DebugToolsSheetView(video: video)
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

// MARK: - Timeline Sheet View

struct TimelineSheetView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 说明文字
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("时间线展示了视频中所有回合和击球点的分布情况")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // 时间线可视化
                    VideoTimelineView(
                        totalDuration: video.duration,
                        rallies: video.timelineRallies,
                        hitEvents: video.allHitEvents,
                        onTapTime: { time in
                            print("🎯 跳转到视频时间: \(time)s")
                            // TODO: 实现视频跳转功能
                        }
                    )
                    .padding(.bottom)
                }
            }
            .navigationTitle("击球点时间线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Debug Tools Sheet View

struct DebugToolsSheetView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showShareSheet = false
    @State private var shareFileURL: URL?
    @State private var selectedTab = 0  // 0: 数据导出, 1: 音频诊断
    @State private var audioDiagnosticData: AudioDiagnosticData? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分段控制
                Picker("选择功能", selection: $selectedTab) {
                    Text("数据导出").tag(0)
                    Text("音频诊断").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // 内容区域
                if selectedTab == 0 {
                    dataExportView
                } else {
                    audioDiagnosticView
                }
            }  // VStack
            .onAppear {
                loadAudioDiagnosticData()
            }
            .navigationTitle("调试工具")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .overlay(
                // Toast 提示
                Group {
                    if showToast {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(toastMessage)
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 10)
                            .padding(.bottom, 50)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            )
            .sheet(isPresented: $showShareSheet) {
                if let url = shareFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }  // NavigationStack
    }  // body View

    // MARK: - Data Export View

    private var dataExportView: some View {
        ScrollView {
                VStack(spacing: 20) {
                    // 说明文字
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("导出完整的分析数据用于算法调试和优化")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // 操作按钮
                    VStack(spacing: 12) {
                        // 复制到剪贴板
                        Button {
                            copyToClipboard()
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("复制到剪贴板")
                                        .font(.headline)
                                    Text("快速复制 JSON 数据")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // 导出文件
                        Button {
                            exportToFile()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("导出 JSON 文件")
                                        .font(.headline)
                                    Text("保存为文件并分享")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    // 数据统计
                    VStack(alignment: .leading, spacing: 12) {
                        Text("数据统计")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            statRow(icon: "film", label: "视频时长", value: formatDuration(video.duration))
                            statRow(icon: "number", label: "回合数量", value: "\(video.rallyCount)")
                            statRow(icon: "waveform", label: "击球事件", value: "\(video.allHitEvents.count)")
                            statRow(icon: "doc.text", label: "估计大小", value: estimatedDataSize)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer()
                }  // VStack
            }  // ScrollView
    }  // dataExportView

    // MARK: - Audio Diagnostic View

    private var audioDiagnosticView: some View {
        Group {
            if let diagnosticData = audioDiagnosticData {
                // 显示音频诊断可视化
                AudioDiagnosticMainView(diagnosticData: diagnosticData)
            } else {
                // 显示启用诊断模式的说明
                noDiagnosticDataView
            }
        }
    }

    private var noDiagnosticDataView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)

                // 图标
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                // 说明文字
                VStack(spacing: 12) {
                    Text("音频诊断未启用")
                        .font(.title2.bold())

                    Text("启用音频诊断模式可以帮助您深入了解音频峰值检测的每个阶段，找出为什么击球声没有被检测到。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // 功能说明
                VStack(alignment: .leading, spacing: 16) {
                    Text("诊断功能包括:")
                        .font(.headline)

                    featureItem(icon: "chart.line.uptrend.xyaxis", text: "RMS 时间序列图 - 显示音频电平变化")
                    featureItem(icon: "chart.xyaxis.line", text: "候选峰值分布 - 振幅 vs 置信度")
                    featureItem(icon: "chart.bar", text: "过滤阶段漏斗 - 各阶段通过率")
                    featureItem(icon: "exclamationmark.triangle", text: "拒绝原因统计 - 了解峰值为何被过滤")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                // 提示
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.yellow)
                    Text("诊断模式需要重新分析视频，可能需要几分钟时间")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)

                // 启用按钮（暂时禁用，需要集成到分析流程）
                Button {
                    // TODO: 启用诊断模式并重新分析
                    showToastMessage("此功能正在开发中")
                } label: {
                    Label("启用诊断模式并重新分析", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.5))  // 暂时灰色表示未实现
                        .cornerRadius(12)
                }
                .disabled(true)  // 暂时禁用
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func featureItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }

    // MARK: - Helper Views

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Methods

    /// 从文件加载音频诊断数据
    private func loadAudioDiagnosticData() {
        guard let filePath = video.audioDiagnosticDataPath else {
            print("⚠️ [DebugTools] 没有可用的音频诊断数据文件路径")
            return
        }

        if let data = AudioDiagnosticExporter.loadFromFile(filePath: filePath) {
            audioDiagnosticData = data
            print("✅ [DebugTools] 已加载音频诊断数据")
        } else {
            audioDiagnosticData = nil
            print("❌ [DebugTools] 加载音频诊断数据失败")
        }
    }

    // MARK: - Computed Properties

    private var estimatedDataSize: String {
        let rallySize = video.rallyCount * 500
        let hitSize = video.allHitEvents.count * 200
        let totalBytes = rallySize + hitSize + 1000
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    // MARK: - Actions

    private func copyToClipboard() {
        let result = AnalysisDebugExporter.copyToClipboard(video: video)

        if result.success {
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(result.dataSize), countStyle: .file)
            showToastMessage("已复制 \(sizeStr) 到剪贴板")
        } else {
            showToastMessage("复制失败，请重试")
        }
    }

    private func exportToFile() {
        if let fileURL = AnalysisDebugExporter.exportToFile(video: video) {
            shareFileURL = fileURL
            showShareSheet = true
        } else {
            showToastMessage("导出失败，请重试")
        }
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showToast = false
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}  // DebugToolsSheetView

// MARK: - ShareSheet Helper

/// UIActivityViewController 的 SwiftUI 包装器
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
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
