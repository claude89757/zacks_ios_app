//
//  VideoPlayerManager.swift
//  zacks_tennis
//
//  视频播放器管理器 - AVPlayer 对象池
//  管理多个 AVPlayer 实例，优化内存和性能
//

import Foundation
import AVFoundation
import Combine
import UIKit

/// 视频播放器管理器 - 单例模式
@MainActor
final class VideoPlayerManager: ObservableObject {

    // MARK: - Singleton

    static let shared = VideoPlayerManager()

    // MARK: - Properties

    /// 播放器池（URL -> AVPlayer）
    private var playerPool: [URL: AVPlayer] = [:]

    /// 当前活跃的播放器
    @Published private(set) var activePlayer: AVPlayer?

    /// 当前播放器是否已准备就绪（currentItem.status == .readyToPlay）
    @Published private(set) var isPlayerReady: Bool = false

    /// 当前活跃播放器的播放时间范围
    private var currentEndTime: Double?

    /// 播放器池大小限制
    private let maxPoolSize: Int = 5

    /// 最近使用时间（LRU 缓存）
    private var lastUsedTime: [URL: Date] = [:]

    /// 播放状态观察者
    private var statusObservers: [URL: AnyCancellable] = [:]

    // MARK: - Initialization

    private init() {
        // 监听应用进入后台事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // 注册内存警告回调
        MemoryMonitor.shared.registerWarningCallback { [weak self] level in
            Task { @MainActor in
                self?.handleMemoryPressure(level)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // 注意：cleanupAll() 不能在 deinit 中调用（@MainActor 限制）
        // 应该在应用终止前手动调用
    }

    // MARK: - Public Methods

    /// 获取或创建播放器
    /// - Parameter url: 视频 URL
    /// - Returns: AVPlayer 实例
    func getPlayer(for url: URL) -> AVPlayer {
        // 如果池中已有，直接返回并更新使用时间
        if let existingPlayer = playerPool[url] {
            lastUsedTime[url] = Date()
            activePlayer = existingPlayer
            return existingPlayer
        }

        // 检查池大小，如果超限则移除最久未使用的
        if playerPool.count >= maxPoolSize {
            evictLeastRecentlyUsed()
        }

        // 创建新播放器
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause

        // 添加到池中
        playerPool[url] = player
        lastUsedTime[url] = Date()
        activePlayer = player

        // 添加状态观察
        observePlayerStatus(player, url: url)

        return player
    }

    /// 播放指定 URL 的视频
    /// - Parameters:
    ///   - url: 视频 URL
    ///   - startTime: 开始时间（可选）
    ///   - endTime: 结束时间（可选）
    ///   - autoStart: 是否自动开始播放
    func play(url: URL, startTime: Double? = nil, endTime: Double? = nil, autoStart: Bool = true) {
        // 重置就绪状态
        isPlayerReady = false

        let player = getPlayer(for: url)

        // 保存结束时间，在 playerItem 准备好后设置
        currentEndTime = endTime

        // 尝试设置 forwardPlaybackEndTime（如果 currentItem 已经存在）
        applyEndTimeIfReady(to: player)

        // 如果播放器已经缓存且 ready，立即恢复就绪状态
        // （从播放器池获取的已缓存播放器不会再次触发 KVO .readyToPlay 回调）
        if player.currentItem?.status == .readyToPlay {
            isPlayerReady = true
        }

        guard let startTime = startTime else {
            if autoStart {
                player.play()
            } else {
                player.pause()
            }
            return
        }

        let time = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                if autoStart {
                    player.play()
                } else {
                    player.pause()
                }
            }
        }
    }

    /// 当 playerItem 准备好时应用结束时间
    private func applyEndTimeIfReady(to player: AVPlayer) {
        guard let currentItem = player.currentItem else { return }

        if let endTime = currentEndTime {
            let end = CMTime(seconds: endTime, preferredTimescale: 600)
            currentItem.forwardPlaybackEndTime = end
        } else {
            currentItem.forwardPlaybackEndTime = .invalid
        }
    }

    /// 暂停当前播放器
    func pause() {
        activePlayer?.pause()
    }

    /// 停止并释放指定播放器
    /// - Parameter url: 视频 URL
    func releasePlayer(for url: URL) {
        let wasActive = playerPool[url] != nil && activePlayer === playerPool[url]

        if let player = playerPool[url] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            statusObservers[url]?.cancel()
            statusObservers.removeValue(forKey: url)
        }

        playerPool.removeValue(forKey: url)
        lastUsedTime.removeValue(forKey: url)

        if wasActive {
            activePlayer = nil
            isPlayerReady = false
            currentEndTime = nil
        }
    }

    /// 暂停所有播放器
    func pauseAll() {
        for player in playerPool.values {
            player.pause()
        }
    }

    /// 清理所有播放器
    func cleanupAll() {
        for (url, player) in playerPool {
            player.pause()
            player.replaceCurrentItem(with: nil)
            statusObservers[url]?.cancel()
        }

        playerPool.removeAll()
        lastUsedTime.removeAll()
        statusObservers.removeAll()
        activePlayer = nil
        isPlayerReady = false
        currentEndTime = nil
    }

    /// 预加载视频
    /// - Parameter url: 视频 URL
    func preload(url: URL) {
        let player = getPlayer(for: url)
        player.currentItem?.loadedTimeRanges.forEach { _ in
            // 触发加载
        }
    }

    /// 批量预加载
    /// - Parameter urls: 视频 URL 数组
    func preloadMultiple(urls: [URL]) {
        for url in urls.prefix(maxPoolSize) {
            preload(url: url)
        }
    }

    // MARK: - Private Methods

    /// 移除最久未使用的播放器（LRU 策略）
    private func evictLeastRecentlyUsed() {
        guard let lruURL = lastUsedTime.min(by: { $0.value < $1.value })?.key else {
            return
        }

        releasePlayer(for: lruURL)
    }

    /// 观察播放器状态
    private func observePlayerStatus(_ player: AVPlayer, url: URL) {
        let observer = player.publisher(for: \.currentItem?.status)
            .sink { [weak self] status in
                guard let self = self else { return }

                Task { @MainActor in
                    switch status {
                    case .readyToPlay:
                        // 播放器已准备就绪，现在可以安全设置 forwardPlaybackEndTime
                        if player === self.activePlayer {
                            self.applyEndTimeIfReady(to: player)
                            self.isPlayerReady = true
                        }

                    case .failed:
                        print("⚠️ 播放器加载失败: \(url)")
                        if player === self.activePlayer {
                            self.isPlayerReady = false
                        }
                        self.releasePlayer(for: url)

                    case .unknown:
                        if player === self.activePlayer {
                            self.isPlayerReady = false
                        }

                    @unknown default:
                        break
                    }
                }
            }

        statusObservers[url] = observer
    }

    /// 应用进入后台时暂停所有播放
    @objc private func applicationDidEnterBackground() {
        pauseAll()
    }

    /// 处理内存压力
    /// - Parameter level: 内存压力级别
    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .normal:
            // 正常情况，不做处理
            break

        case .warning:
            // 警告级别：清理非活跃播放器
            print("⚠️ VideoPlayerManager: 内存警告，清理非活跃播放器")
            cleanupInactivePlayers()

        case .critical:
            // 危急级别：清理所有非当前播放器
            print("🔥 VideoPlayerManager: 内存危急，清理所有非活跃播放器")
            cleanupAllExceptActive()
        }
    }

    /// 清理非活跃的播放器（超过 30 秒未使用）
    private func cleanupInactivePlayers() {
        let threshold = Date().addingTimeInterval(-30)

        let urlsToRemove = lastUsedTime.filter { _, lastUsed in
            lastUsed < threshold
        }.map { $0.key }

        for url in urlsToRemove {
            if let player = playerPool[url] {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            playerPool.removeValue(forKey: url)
            lastUsedTime.removeValue(forKey: url)
            statusObservers.removeValue(forKey: url)
        }

        if !urlsToRemove.isEmpty {
            print("🗑️ 清理了 \(urlsToRemove.count) 个非活跃播放器")
        }
    }

    /// 清理除当前活跃播放器外的所有播放器
    private func cleanupAllExceptActive() {
        guard let active = activePlayer else {
            // 没有活跃播放器，清理所有
            cleanupAll()
            return
        }

        // 找到当前活跃播放器的 URL
        let activeURL = playerPool.first(where: { $0.value === active })?.key

        // 清理其他所有播放器
        let urlsToRemove = playerPool.keys.filter { $0 != activeURL }

        for url in urlsToRemove {
            if let player = playerPool[url] {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            playerPool.removeValue(forKey: url)
            lastUsedTime.removeValue(forKey: url)
            statusObservers.removeValue(forKey: url)
        }

        print("🗑️ 清理了 \(urlsToRemove.count) 个非活跃播放器，保留当前播放器")
    }

    // MARK: - Pool Statistics

    /// 获取池中播放器数量
    var poolSize: Int {
        playerPool.count
    }

    /// 获取所有已缓存的 URL
    var cachedURLs: [URL] {
        Array(playerPool.keys)
    }
}

// MARK: - Player Item Extension

extension AVPlayerItem {
    /// 获取加载进度（0-1）
    var loadedProgress: Double {
        guard let timeRange = loadedTimeRanges.first?.timeRangeValue else {
            return 0.0
        }

        let duration = CMTimeGetSeconds(duration)
        let loadedDuration = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)

        return duration > 0 ? loadedDuration / duration : 0.0
    }
}
