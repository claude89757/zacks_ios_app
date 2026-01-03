//
//  RallyPlayerView.swift
//  zacks_tennis
//
//  TikTok 风格短视频播放器 - 垂直滑动切换回合
//  UX优化: 垂直滑动、进度指示器、自动播放、循环播放、速度调节、新手引导
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

    // 当前播放的回合 ID（使用 id-based 跟踪）
    @State private var currentRallyId: VideoHighlight.ID?
    @State private var isPlaying: Bool = true
    @StateObject private var playerManager = VideoPlayerManager.shared

    // 新手引导状态
    @AppStorage("hasSeenPlayerOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    // 边界提示 Toast 状态
    @State private var showBoundaryToast = false
    @State private var boundaryToastMessage = ""

    /// 当前索引（从 ID 计算）
    private var currentIndex: Int {
        guard let id = currentRallyId else { return 0 }
        return rallies.firstIndex(where: { $0.id == id }) ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if rallies.isEmpty {
                emptyStateView
            } else {
                // 垂直滚动分页（iOS 17+ API）
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rallies.enumerated()), id: \.element.id) { index, rally in
                            RallyPlayerCard(
                                index: index,
                                currentIndex: currentIndex,
                                rally: rally,
                                video: video,
                                isPlaying: $isPlaying,
                                totalCount: rallies.count,
                                onFavoriteToggle: {
                                    toggleFavorite(rally)
                                },
                                onPlaybackEnd: {
                                    handlePlaybackEnd(at: index)
                                }
                            )
                            .id(rally.id)
                            .containerRelativeFrame(.vertical)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentRallyId)
                .scrollIndicators(.hidden)
                .ignoresSafeArea()
                .onChange(of: currentRallyId) { oldValue, newValue in
                    handleRallyChange(from: oldValue, to: newValue)
                }

                // 顶部导航栏
                VStack {
                    topNavigationBar
                    Spacer()
                }

                // 右侧垂直进度条
                HStack {
                    Spacer()
                    verticalProgressIndicator
                        .padding(.trailing, 8)
                }
            }
        }
        .onAppear {
            setupInitialState()
        }
        .onDisappear {
            playerManager.pauseAll()
        }
        // 新手引导覆盖层
        .playerOnboarding(isShowing: $showOnboarding)
        // 边界提示 Toast
        .toast(
            isShowing: $showBoundaryToast,
            message: boundaryToastMessage,
            icon: "info.circle.fill",
            iconColor: .blue,
            position: .center
        )
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            // 关闭按钮
            Button {
                HapticManager.shared.tap()
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

            // 顶部进度指示器：3/15
            Text("\(currentIndex + 1) / \(rallies.count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(16)
                .contentTransition(.numericText(value: Double(currentIndex)))
                .animation(.spring(response: 0.3), value: currentIndex)

            Spacer()

            // 帮助按钮
            Button {
                HapticManager.shared.tap()
                withAnimation {
                    showOnboarding = true
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 50)
    }

    // MARK: - Vertical Progress Indicator

    /// 右侧垂直进度条
    private var verticalProgressIndicator: some View {
        VStack(spacing: 3) {
            ForEach(0..<rallies.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index == currentIndex ? 5 : 4, height: calculateSegmentHeight())
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
        .padding(.vertical, 120) // 避开顶部和底部 UI
    }

    /// 计算每个进度条段的高度
    private func calculateSegmentHeight() -> CGFloat {
        let totalHeight: CGFloat = UIScreen.main.bounds.height - 300
        let count = max(rallies.count, 1)
        let segmentHeight = (totalHeight - CGFloat(count - 1) * 3) / CGFloat(count)
        return max(4, min(segmentHeight, 20)) // 限制高度范围
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .symbolEffect(.pulse)

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

    private func setupInitialState() {
        guard !rallies.isEmpty else { return }

        // 设置初始位置
        if let selected = selectedRally,
           rallies.contains(where: { $0.id == selected.id }) {
            currentRallyId = selected.id
        } else {
            currentRallyId = rallies[0].id
        }

        selectedRally = rallies[currentIndex]
        playerManager.pauseAll()
        playCurrentRally(autoStart: isPlaying)

        // 首次使用显示新手引导
        if !hasSeenOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    showOnboarding = true
                }
            }
        }
    }

    /// 处理回合切换
    private func handleRallyChange(from oldValue: VideoHighlight.ID?, to newValue: VideoHighlight.ID?) {
        guard let newId = newValue else { return }
        guard let newIndex = rallies.firstIndex(where: { $0.id == newId }) else { return }

        // 更新选中的回合
        selectedRally = rallies[newIndex]

        // 触觉反馈
        HapticManager.shared.pageChange()

        // 边界提示
        if oldValue != nil {
            if newIndex == 0 {
                showBoundaryMessage("已经是第一个片段了")
            } else if newIndex == rallies.count - 1 {
                showBoundaryMessage("已经是最后一个片段了")
            }
        }

        // 暂停之前的播放器
        playerManager.pauseAll()

        // 如果需要自动播放，启动新的播放器
        playCurrentRally(autoStart: isPlaying)
    }

    /// 处理播放结束 - 自动切换到下一个（循环播放）
    private func handlePlaybackEnd(at index: Int) {
        guard index == currentIndex else { return }

        // 延迟 0.5 秒后切换
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if index < rallies.count - 1 {
                    // 切换到下一个
                    currentRallyId = rallies[index + 1].id
                } else {
                    // 循环到第一个
                    currentRallyId = rallies[0].id
                    showBoundaryMessage("已循环到第一个片段")
                }
            }
        }
    }

    /// 显示边界提示
    private func showBoundaryMessage(_ message: String) {
        boundaryToastMessage = message
        showBoundaryToast = true
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

        // 触觉反馈
        HapticManager.shared.favorite()

        // SwiftData 会自动保存更改
        try? modelContext.save()
    }
}

// MARK: - Rally Player Card

struct RallyPlayerCard: View {
    let index: Int
    let currentIndex: Int
    let rally: VideoHighlight
    let video: Video
    @Binding var isPlaying: Bool
    let totalCount: Int
    let onFavoriteToggle: () -> Void
    let onPlaybackEnd: () -> Void

    @StateObject private var playerManager = VideoPlayerManager.shared
    @State private var isPlayerReady = false
    @State private var playbackProgress: Double = 0
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var showHeartAnimation = false
    @State private var showSeekIndicator: SeekDirection? = nil
    @State private var lastHitMarkerIndex: Int = -1

    // 播放速度
    @State private var playbackRate: Float = 1.0
    private let availableRates: [Float] = [0.5, 1.0, 1.5, 2.0]

    private var isActive: Bool {
        currentIndex == index
    }

    private var shouldShowProgressBar: Bool {
        isPlayerReady && isActive
    }

    /// 当前播放时间
    private var currentTimeText: String {
        let currentSeconds = rally.startTime + playbackProgress * rally.duration
        return formatTime(currentSeconds - rally.startTime)
    }

    /// 总时长文本
    private var totalTimeText: String {
        formatTime(rally.duration)
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
                // 双击快进/快退手势
                .gesture(doubleTapGesture)
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

                    VStack(spacing: 20) {
                        // 收藏按钮
                        Button {
                            onFavoriteToggle()
                            if rally.isFavorite {
                                showHeartAnimation = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    showHeartAnimation = false
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: rally.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 28))
                                    .foregroundColor(rally.isFavorite ? .red : .white)
                                    .scaleEffect(rally.isFavorite ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: rally.isFavorite)

                                Text(rally.isFavorite ? "已收藏" : "收藏")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel(rally.isFavorite ? "取消收藏" : "收藏")
                        .accessibilityHint("双击\(rally.isFavorite ? "取消" : "")收藏此回合")

                        // 播放速度按钮
                        Button {
                            cyclePlaybackRate()
                        } label: {
                            VStack(spacing: 4) {
                                Text(playbackRateText)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())

                                Text("速度")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("播放速度 \(playbackRateText)")
                        .accessibilityHint("双击切换播放速度")

                        // 精彩度评分
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                    .frame(width: 44, height: 44)

                                Circle()
                                    .trim(from: 0, to: rally.excitementScore / 100)
                                    .stroke(scoreColor, lineWidth: 3)
                                    .frame(width: 44, height: 44)
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
                                .font(.system(size: 24))
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
            if !isPlaying && isActive {
                Image(systemName: "play.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.8))
            }

            // 收藏心形动画
            if showHeartAnimation {
                HeartAnimation()
            }

            // 快进/快退指示器
            if let direction = showSeekIndicator {
                SeekIndicatorView(direction: direction)
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

    // MARK: - Playback Rate

    private var playbackRateText: String {
        if playbackRate == 1.0 { return "1x" }
        if playbackRate == 0.5 { return "0.5x" }
        if playbackRate == 1.5 { return "1.5x" }
        if playbackRate == 2.0 { return "2x" }
        return String(format: "%.1fx", playbackRate)
    }

    private func cyclePlaybackRate() {
        guard let currentRateIndex = availableRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            applyPlaybackRate()
            return
        }

        let nextIndex = (currentRateIndex + 1) % availableRates.count
        playbackRate = availableRates[nextIndex]
        applyPlaybackRate()

        HapticManager.shared.tap()
    }

    private func applyPlaybackRate() {
        guard let player = playerManager.activePlayer else { return }
        player.rate = isPlaying ? playbackRate : 0
    }

    // MARK: - Double Tap Gesture

    /// 双击手势：左半区快退5秒，右半区快进5秒
    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let screenWidth = UIScreen.main.bounds.width
                let tapX = value.location.x

                if tapX < screenWidth / 2 {
                    seekBy(seconds: -5)
                    showSeekIndicator = .backward
                } else {
                    seekBy(seconds: 5)
                    showSeekIndicator = .forward
                }

                HapticManager.shared.seek()

                // 隐藏指示器
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSeekIndicator = nil
                }
            }
    }

    /// 跳转指定秒数
    private func seekBy(seconds: Double) {
        guard isActive, let player = playerManager.activePlayer else { return }

        let currentSeconds = player.currentTime().seconds
        var targetSeconds = currentSeconds + seconds

        // 限制在回合范围内
        targetSeconds = max(rally.startTime, min(targetSeconds, rally.endTime - 0.1))

        let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)

        // 更新进度
        let normalized = (targetSeconds - rally.startTime) / rally.duration
        playbackProgress = min(max(normalized, 0), 1)
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
        lastHitMarkerIndex = -1
        isPlayerReady = true
        addTimeObserver(to: player)
        updateProgress(currentSeconds: player.currentTime().seconds)

        // 应用当前播放速度
        if isPlaying {
            player.rate = playbackRate
        }
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

        // 检查是否经过击球声标记（触觉反馈）
        checkHitMarkerFeedback(currentSeconds: currentSeconds)

        if currentSeconds >= rally.endTime - 0.05 {
            playbackProgress = 1

            if isPlaying {
                isPlaying = false
            }

            player.pause()

            // 通知父视图播放结束
            onPlaybackEnd()
        }
    }

    /// 检查是否经过击球声标记，触发触觉反馈
    private func checkHitMarkerFeedback(currentSeconds: Double) {
        let timestamps = rally.audioPeakTimestamps
        guard !timestamps.isEmpty else { return }

        let relativeTime = currentSeconds - rally.startTime

        for (index, timestamp) in timestamps.enumerated() {
            // 在标记点附近 0.1 秒内触发
            if abs(relativeTime - timestamp) < 0.1 && index > lastHitMarkerIndex {
                lastHitMarkerIndex = index
                HapticManager.shared.hitMarker()
                break
            }
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
            VStack(spacing: 4) {
                // 时间预览（拖动时显示）
                if isScrubbing {
                    HStack {
                        Text(currentTimeText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .offset(x: max(0, min(geometry.size.width * playbackProgress - 20, geometry.size.width - 50)))

                        Spacer()
                    }
                }

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
                        .frame(width: isScrubbing ? 16 : 12, height: isScrubbing ? 16 : 12)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .offset(x: knobOffset(in: geometry.size.width), y: isScrubbing ? -6 : -4)
                        .animation(.easeInOut(duration: 0.1), value: isScrubbing)

                    // 时间显示（右下角）
                    if !isScrubbing {
                        HStack {
                            Spacer()
                            Text("\(currentTimeText) / \(totalTimeText)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .offset(y: 12)
                    }
                }
                .contentShape(Rectangle().inset(by: -10)) // 扩大触摸区域
                .gesture(scrubGesture(totalWidth: geometry.size.width))
            }
        }
        .frame(height: isScrubbing ? 36 : 28)
        .animation(.easeInOut(duration: 0.15), value: playbackProgress)
        .animation(.easeInOut(duration: 0.15), value: isScrubbing)
    }

    private func togglePlayPause() {
        guard isActive, let player = playerManager.activePlayer else { return }

        HapticManager.shared.playPause()

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
            lastHitMarkerIndex = -1
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                Task { @MainActor in
                    player.rate = playbackRate
                }
            }
        } else {
            player.rate = playbackRate
        }

        isPlaying = true
    }

    private func knobOffset(in totalWidth: CGFloat) -> CGFloat {
        let clampedProgress = min(max(playbackProgress, 0), 1)
        let knobWidth: CGFloat = isScrubbing ? 16 : 12
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
            HapticManager.shared.dragStart()
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

        HapticManager.shared.dragEnd()

        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                isScrubbing = false

                // 更新击球声标记索引
                let relativeTime = targetSeconds - rally.startTime
                lastHitMarkerIndex = rally.audioPeakTimestamps.lastIndex(where: { $0 < relativeTime }) ?? -1

                if wasPlayingBeforeScrub {
                    player.currentItem?.forwardPlaybackEndTime = CMTime(
                        seconds: rally.endTime,
                        preferredTimescale: 600
                    )
                    player.rate = playbackRate
                    isPlaying = true
                }

                wasPlayingBeforeScrub = false
            }
        }
    }

    /// 格式化时间
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Seek Indicator

enum SeekDirection {
    case forward
    case backward
}

struct SeekIndicatorView: View {
    let direction: SeekDirection

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            if direction == .backward {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 32, weight: .bold))
                Text("5秒")
                    .font(.headline)
            } else {
                Text("5秒")
                    .font(.headline)
                Image(systemName: "goforward.5")
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(x: direction == .backward ? -60 : 60)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                scale = 1
                opacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 0
                }
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
