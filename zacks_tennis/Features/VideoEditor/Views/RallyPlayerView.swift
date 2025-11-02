//
//  RallyPlayerView.swift
//  zacks_tennis
//
//  TikTok 风格短视频播放器 - 垂直滑动切换回合
//

import SwiftUI
import AVKit
import SwiftData

struct RallyPlayerView: View {
    let rallies: [VideoHighlight]
    let video: Video
    @Binding var selectedRally: VideoHighlight?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var currentIndex: Int = 0
    @State private var isPlaying: Bool = true
    @StateObject private var playerManager = VideoPlayerManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if rallies.isEmpty {
                emptyStateView
            } else {
                // TabView 垂直分页
                TabView(selection: $currentIndex) {
                    ForEach(Array(rallies.enumerated()), id: \.element.id) { index, rally in
                        RallyPlayerCard(
                            index: index,
                            currentIndex: $currentIndex,
                            rally: rally,
                            video: video,
                            isPlaying: $isPlaying,
                            onFavoriteToggle: {
                                toggleFavorite(rally)
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .onChange(of: currentIndex) { oldValue, newValue in
                    handleIndexChange(newValue)
                }

                // 顶部导航栏
                VStack {
                    topNavigationBar
                    Spacer()
                }

                // 底部进度指示器
                VStack {
                    Spacer()
                    pageIndicator
                }
            }
        }
        .onAppear {
            setupInitialIndex()
        }
        .onDisappear {
            playerManager.pauseAll()
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            Text("精彩回合")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // 占位保持居中
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.top, 50)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(rallies.count, 5), id: \.self) { index in
                if shouldShowDot(at: index) {
                    Circle()
                        .fill(index == currentIndex ? Color.white : Color.white.opacity(0.5))
                        .frame(width: index == currentIndex ? 8 : 6, height: index == currentIndex ? 8 : 6)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }

            if rallies.count > 5 {
                Text("...")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption)
            }
        }
        .padding(.bottom, 40)
    }

    private func shouldShowDot(at index: Int) -> Bool {
        // 只显示当前附近的 5 个点
        if rallies.count <= 5 {
            return true
        }

        let range = max(0, currentIndex - 2)...min(rallies.count - 1, currentIndex + 2)
        return range.contains(index)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("没有可播放的回合")
                .font(.headline)
                .foregroundColor(.white)

            Button {
                dismiss()
            } label: {
                Text("返回")
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Helper Methods

    private func setupInitialIndex() {
        guard !rallies.isEmpty else { return }

        if let selected = selectedRally,
           let index = rallies.firstIndex(where: { $0.id == selected.id }) {
            currentIndex = index
        }

        selectedRally = rallies[currentIndex]
        playerManager.pauseAll()
        playCurrentRally(autoStart: isPlaying)
    }

    private func handleIndexChange(_ newIndex: Int) {
        // 更新选中的回合
        guard newIndex >= 0 && newIndex < rallies.count else { return }
        selectedRally = rallies[newIndex]

        // 暂停之前的播放器
        playerManager.pauseAll()

        // 如果需要自动播放，启动新的播放器
        playCurrentRally(autoStart: isPlaying)
    }

    private func playCurrentRally(autoStart: Bool) {
        guard currentIndex >= 0 && currentIndex < rallies.count else { return }
        let rally = rallies[currentIndex]
        selectedRally = rally

        // 获取视频 URL
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent(video.originalFilePath)

        // 播放回合片段
        playerManager.play(
            url: videoURL,
            startTime: rally.startTime,
            endTime: rally.endTime,
            autoStart: autoStart
        )
    }

    private func toggleFavorite(_ rally: VideoHighlight) {
        rally.isFavorite.toggle()

        // SwiftData 会自动保存更改
        try? modelContext.save()
    }
}

// MARK: - Rally Player Card

struct RallyPlayerCard: View {
    let index: Int
    @Binding var currentIndex: Int
    let rally: VideoHighlight
    let video: Video
    @Binding var isPlaying: Bool
    let onFavoriteToggle: () -> Void

    @StateObject private var playerManager = VideoPlayerManager.shared
    @State private var isPlayerReady = false
    @State private var playbackProgress: Double = 0
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false

    private var isActive: Bool {
        currentIndex == index
    }

    private var shouldShowProgressBar: Bool {
        isPlayerReady && isActive
    }

    var body: some View {
        ZStack {
            // 视频播放器
            if let player = playerManager.activePlayer, isPlayerReady {
                VideoPlayer(player: player) {
                    // 自定义控制层
                    ZStack {
                        Color.clear

                        // 点击切换播放/暂停
                        Button {
                            togglePlayPause()
                        } label: {
                            Color.clear
                        }
                    }
                }
                .ignoresSafeArea()
            } else {
                // 加载中
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // 右侧信息栏
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    VStack(spacing: 24) {
                        // 收藏按钮
                        Button {
                            onFavoriteToggle()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: rally.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 28))
                                    .foregroundColor(rally.isFavorite ? .red : .white)

                                Text(rally.isFavorite ? "已收藏" : "收藏")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }

                        // 精彩度评分
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                    .frame(width: 48, height: 48)

                                Circle()
                                    .trim(from: 0, to: rally.excitementScore / 100)
                                    .stroke(scoreColor, lineWidth: 3)
                                    .frame(width: 48, height: 48)
                                    .rotationEffect(.degrees(-90))

                                Text("\(Int(rally.excitementScore))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }

                            Text("精彩度")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }

                        // 时长
                        VStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 28))
                                .foregroundColor(.white)

                            Text(rally.durationText)
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 16)
                }

                if shouldShowProgressBar {
                    progressBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }

                // 底部信息栏
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        // 回合序号和类型
                        HStack(spacing: 8) {
                            Text("#\(rally.rallyNumber)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)

                            Text(rally.type)
                                .font(.headline)
                                .foregroundColor(.white)
                        }

                        // 回合描述
                        if !rally.rallyDescription.isEmpty {
                            Text(rally.rallyDescription)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                        }

                        // 元数据标签
                        if let metadata = rally.metadata {
                            HStack(spacing: 8) {
                                if metadata.hasAudioPeaks {
                                    Label("击球声", systemImage: "waveform")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(4)
                                }

                                if let hitCount = metadata.estimatedHitCount, hitCount > 0 {
                                    Text("\(hitCount) 次击球")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }

            // 播放/暂停图标（临时显示）
            if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear {
            loadPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: currentIndex) { _, _ in
            loadPlayer()
        }
        .onReceive(playerManager.$activePlayer) { _ in
            loadPlayer()
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

    private func loadPlayer() {
        removeTimeObserver()

        guard isActive else {
            isPlayerReady = false
            playbackProgress = 0
            return
        }

        guard let player = playerManager.activePlayer else {
            isPlayerReady = false
            playbackProgress = 0
            return
        }

        player.currentItem?.forwardPlaybackEndTime = CMTime(
            seconds: rally.endTime,
            preferredTimescale: 600
        )

        playbackProgress = 0
        isPlayerReady = true
        addTimeObserver(to: player)
        updateProgress(currentSeconds: player.currentTime().seconds)
    }

    private func cleanupPlayer() {
        removeTimeObserver()

        if !isActive {
            isPlayerReady = false
            playbackProgress = 0
        }

        isScrubbing = false
        wasPlayingBeforeScrub = false
    }

    private func addTimeObserver(to player: AVPlayer) {
        removeTimeObserver()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        observedPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            handleTimeUpdate(player: player, currentSeconds: time.seconds)
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(token)
        }

        timeObserver = nil
        observedPlayer = nil
    }

    private func handleTimeUpdate(player: AVPlayer, currentSeconds: Double) {
        guard isActive, !isScrubbing else { return }

        updateProgress(currentSeconds: currentSeconds)

        if currentSeconds >= rally.endTime - 0.05 {
            playbackProgress = 1

            if isPlaying {
                isPlaying = false
            }

            player.pause()
        }
    }

    private func updateProgress(currentSeconds: Double) {
        if isScrubbing {
            return
        }

        let start = rally.startTime
        let end = rally.endTime
        let duration = max(end - start, 0.01)
        let normalized = (currentSeconds - start) / duration
        playbackProgress = min(max(normalized, 0), 1)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * playbackProgress, height: 4)
                
                // 击球声标记
                ForEach(Array(rally.audioPeakTimestamps.enumerated()), id: \.offset) { _, timestamp in
                    let normalizedPosition = min(max(timestamp / rally.duration, 0), 1)
                    let xPosition = geometry.size.width * normalizedPosition
                    
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2, height: 8)
                        .offset(x: xPosition, y: -2)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0.5)
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: knobOffset(in: geometry.size.width), y: -4)
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(totalWidth: geometry.size.width))
        }
        .frame(height: 16)
        .animation(.easeInOut(duration: 0.15), value: playbackProgress)
    }

    private func togglePlayPause() {
        guard isActive, let player = playerManager.activePlayer else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }

        player.currentItem?.forwardPlaybackEndTime = CMTime(
            seconds: rally.endTime,
            preferredTimescale: 600
        )

        let currentSeconds = player.currentTime().seconds
        let startTime = CMTime(seconds: rally.startTime, preferredTimescale: 600)

        if currentSeconds >= rally.endTime - 0.05 || currentSeconds < rally.startTime {
            playbackProgress = 0
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                Task { @MainActor in
                    player.play()
                }
            }
        } else {
            player.play()
        }

        isPlaying = true
    }

    private func knobOffset(in totalWidth: CGFloat) -> CGFloat {
        let clampedProgress = min(max(playbackProgress, 0), 1)
        let knobWidth: CGFloat = 12
        let xPosition = totalWidth * clampedProgress - knobWidth / 2
        return max(-knobWidth / 2, min(totalWidth - knobWidth / 2, xPosition))
    }

    private func scrubGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isActive, let player = playerManager.activePlayer else { return }

                startScrubbingIfNeeded(player: player)

                let locationX = min(max(value.location.x, 0), totalWidth)
                let progress = totalWidth > 0 ? locationX / totalWidth : 0
                updateProgressFromScrub(progress, player: player)
            }
            .onEnded { _ in
                finishScrubbing()
            }
    }

    private func startScrubbingIfNeeded(player: AVPlayer) {
        if !isScrubbing {
            isScrubbing = true
            wasPlayingBeforeScrub = isPlaying
            player.pause()
            player.currentItem?.forwardPlaybackEndTime = CMTime(
                seconds: rally.endTime,
                preferredTimescale: 600
            )
        }
    }

    private func updateProgressFromScrub(_ progress: Double, player: AVPlayer) {
        let clamped = min(max(progress, 0), 1)
        playbackProgress = clamped

        let targetSeconds = rally.startTime + clamped * max(rally.endTime - rally.startTime, 0)
        let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func finishScrubbing() {
        guard isActive, let player = playerManager.activePlayer else {
            isScrubbing = false
            wasPlayingBeforeScrub = false
            return
        }

        let clamped = min(max(playbackProgress, 0), 1)
        let targetSeconds = rally.startTime + clamped * max(rally.endTime - rally.startTime, 0)
        let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)

        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                isScrubbing = false

                if wasPlayingBeforeScrub {
                    player.currentItem?.forwardPlaybackEndTime = CMTime(
                        seconds: rally.endTime,
                        preferredTimescale: 600
                    )
                    player.play()
                    isPlaying = true
                }

                wasPlayingBeforeScrub = false
            }
        }
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

    RallyPlayerView(
        rallies: sampleRallies,
        video: sampleVideo,
        selectedRally: .constant(nil)
    )
}
