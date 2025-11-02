//
//  ThumbnailGenerator.swift
//  zacks_tennis
//
//  缩略图生成器 - 从视频生成缩略图
//  支持批量生成、缓存管理、内存优化
//

import Foundation
import AVFoundation
import UIKit

/// 缩略图生成器
@MainActor
final class ThumbnailGenerator {

    // MARK: - Properties

    /// 单例
    static let shared = ThumbnailGenerator()

    /// 缓存目录
    private let cacheDirectory: URL

    /// 当前正在生成的任务
    private var currentTasks: [String: Task<UIImage, Error>] = [:]

    // MARK: - Initialization

    private init() {
        // 创建缩略图缓存目录
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = documentsURL.appendingPathComponent("Thumbnails", isDirectory: true)

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 注册内存警告回调
        MemoryMonitor.shared.registerWarningCallback { [weak self] level in
            Task { @MainActor in
                self?.handleMemoryPressure(level)
            }
        }
    }

    // MARK: - Public Methods

    /// 为视频生成缩略图
    /// - Parameters:
    ///   - videoURL: 视频 URL
    ///   - time: 时间点（秒）
    ///   - size: 缩略图尺寸
    /// - Returns: 生成的缩略图
    func generateThumbnail(
        for videoURL: URL,
        at time: Double,
        size: CGSize = CGSize(width: 240, height: 135)
    ) async throws -> UIImage {

        // 检查缓存
        let cacheKey = cacheKey(for: videoURL, time: time, size: size)
        if let cachedImage = loadFromCache(key: cacheKey) {
            return cachedImage
        }

        // 检查是否已有正在进行的任务
        if let existingTask = currentTasks[cacheKey] {
            return try await existingTask.value
        }

        // 创建新任务
        let task = Task {
            return try await generateThumbnailInternal(
                videoURL: videoURL,
                time: time,
                size: size,
                cacheKey: cacheKey
            )
        }

        currentTasks[cacheKey] = task

        defer {
            currentTasks.removeValue(forKey: cacheKey)
        }

        return try await task.value
    }

    /// 批量生成缩略图
    /// - Parameters:
    ///   - videoURL: 视频 URL
    ///   - times: 时间点数组
    ///   - size: 缩略图尺寸
    /// - Returns: 缩略图数组
    func generateThumbnails(
        for videoURL: URL,
        at times: [Double],
        size: CGSize = CGSize(width: 240, height: 135)
    ) async throws -> [UIImage] {

        var thumbnails: [UIImage] = []

        for time in times {
            let thumbnail = try await generateThumbnail(
                for: videoURL,
                at: time,
                size: size
            )
            thumbnails.append(thumbnail)
        }

        return thumbnails
    }

    /// 为回合生成缩略图（取中间帧）
    /// - Parameters:
    ///   - rally: 回合对象
    ///   - video: 视频对象
    ///   - size: 缩略图尺寸
    /// - Returns: 生成的缩略图路径
    func generateThumbnailForRally(
        _ rally: VideoHighlight,
        video: Video,
        size: CGSize = CGSize(width: 240, height: 135)
    ) async throws -> String {

        // 计算中间时间点
        let middleTime = (rally.startTime + rally.endTime) / 2.0

        // 获取视频 URL
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent(video.originalFilePath)

        // 生成缩略图
        let thumbnail = try await generateThumbnail(
            for: videoURL,
            at: middleTime,
            size: size
        )

        // 保存到缓存
        let filename = "rally_\(rally.id.uuidString).jpg"
        let thumbnailPath = cacheDirectory.appendingPathComponent(filename)

        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw ThumbnailError.compressionFailed
        }

        try data.write(to: thumbnailPath)

        // 返回相对路径
        return "Thumbnails/\(filename)"
    }

    /// 清理缓存
    func clearCache() throws {
        try FileManager.default.removeItem(at: cacheDirectory)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private Methods

    /// 内部生成缩略图逻辑
    private func generateThumbnailInternal(
        videoURL: URL,
        time: Double,
        size: CGSize,
        cacheKey: String
    ) async throws -> UIImage {

        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)

        // 配置图片生成器
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = size

        // 生成图片
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, result, error in

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard result == .succeeded, let cgImage = cgImage else {
                    continuation.resume(throwing: ThumbnailError.generationFailed)
                    return
                }

                let image = UIImage(cgImage: cgImage)

                // 保存到缓存
                Task { @MainActor in
                    self.saveToCache(image: image, key: cacheKey)
                }

                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Cache Management

    /// 生成缓存 key
    private func cacheKey(for videoURL: URL, time: Double, size: CGSize) -> String {
        let videoName = videoURL.lastPathComponent
        return "\(videoName)_\(Int(time))_\(Int(size.width))x\(Int(size.height))"
    }

    /// 从缓存加载
    private func loadFromCache(key: String) -> UIImage? {
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).jpg")

        guard let data = try? Data(contentsOf: cacheURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    /// 保存到缓存
    private func saveToCache(image: UIImage, key: String) {
        let cacheURL = cacheDirectory.appendingPathComponent("\(key).jpg")

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        try? data.write(to: cacheURL)
    }

    /// 获取缓存大小
    func getCacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }

            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    // MARK: - Memory Management

    /// 处理内存压力
    /// - Parameter level: 内存压力级别
    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .normal:
            // 正常情况，不做处理
            break

        case .warning:
            // 警告级别：清理部分缓存（保留最近的缩略图）
            print("⚠️ ThumbnailGenerator: 内存警告，清理旧缓存")
            clearOldCache(keepRecentCount: 50)

        case .critical:
            // 危急级别：清理所有缓存
            print("🔥 ThumbnailGenerator: 内存危急，清理所有缓存")
            try? clearCache()
        }
    }

    /// 清理旧缓存，保留最近的 N 个
    /// - Parameter count: 保留数量
    private func clearOldCache(keepRecentCount count: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return
        }

        // 获取所有缓存文件及创建时间
        var files: [(url: URL, date: Date)] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey]),
                  let creationDate = resourceValues.creationDate else {
                continue
            }

            files.append((fileURL, creationDate))
        }

        // 按时间排序（新到旧）
        files.sort { $0.date > $1.date }

        // 删除超过保留数量的文件
        let filesToDelete = files.dropFirst(count)

        for file in filesToDelete {
            try? FileManager.default.removeItem(at: file.url)
        }

        if !filesToDelete.isEmpty {
            print("🗑️ 清理了 \(filesToDelete.count) 个旧缩略图缓存")
        }
    }
}

// MARK: - Supporting Types

/// 缩略图错误
enum ThumbnailError: LocalizedError {
    case generationFailed
    case compressionFailed
    case invalidVideoURL

    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "缩略图生成失败"
        case .compressionFailed:
            return "图片压缩失败"
        case .invalidVideoURL:
            return "无效的视频 URL"
        }
    }
}
