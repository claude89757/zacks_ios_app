//
//  VideoProcessingService.swift
//  zacks_tennis
//
//  视频处理服务 - 视频导入/导出和辅助工具
//  注意：视频分析功能已迁移到 VideoProcessingEngine
//

import Foundation
import AVFoundation
import UIKit

/// 视频处理服务
@MainActor
@Observable
class VideoProcessingService {
    static let shared = VideoProcessingService()

    var isProcessing = false
    var processingProgress: Double = 0.0
    var currentOperation: String = ""

    private init() {}

    // MARK: - 视频导入

    /// 从 URL 导入视频并创建 Video 模型
    func importVideo(from url: URL, title: String) async throws -> Video {
        let asset = AVAsset(url: url)

        // 获取视频信息
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)

        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let fileSize = try getFileSize(from: url)

        // 复制到 Documents 目录
        let fileName = "\(UUID().uuidString).mp4"
        let destinationURL = getDocumentsDirectory().appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: url, to: destinationURL)

        // 生成缩略图
        let thumbnailPath = try await generateThumbnail(from: asset, videoID: fileName)

        // 创建 Video 模型
        let video = Video(
            title: title,
            originalFilePath: fileName,
            duration: duration.seconds,
            width: Int(naturalSize.width),
            height: Int(naturalSize.height),
            fileSize: fileSize
        )
        video.thumbnailPath = thumbnailPath

        return video
    }

    // MARK: - 视频导出

    // ⚠️ 注意：视频分析功能已迁移到 VideoProcessingEngine
    // 此服务现在只负责：
    // 1. 视频导入（importVideo）
    // 2. 视频导出（exportTopHighlights, exportHighlight）
    // 3. 辅助工具方法（generateThumbnail, getFileSize等）

    /// 导出 Top N 精彩片段
    func exportTopHighlights(from video: Video, count: Int, type: String) async throws -> [ExportedFile] {
        isProcessing = true
        processingProgress = 0.0
        currentOperation = "正在导出精彩片段..."
        defer { isProcessing = false }

        let highlights = video.getTopHighlights(count: count)
        var exportedFiles: [ExportedFile] = []

        for (index, highlight) in highlights.enumerated() {
            let progress = Double(index) / Double(highlights.count)
            await updateProgress(progress, operation: "导出片段 \(index + 1)/\(highlights.count)")

            let exportedFile = try await exportHighlight(
                from: video,
                highlight: highlight,
                fileName: "\(video.title)_highlight_\(index + 1).mp4"
            )
            exportedFiles.append(exportedFile)
        }

        await updateProgress(1.0, operation: "导出完成")

        return exportedFiles
    }

    /// 导出单个精彩片段
    private func exportHighlight(from video: Video, highlight: VideoHighlight, fileName: String) async throws -> ExportedFile {
        let videoURL = getVideoURL(for: video)
        let asset = AVAsset(url: videoURL)

        // 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoError.exportFailed
        }

        // 设置时间范围
        let startTime = CMTime(seconds: highlight.startTime, preferredTimescale: 600)
        let endTime = CMTime(seconds: highlight.endTime, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)

        // 设置输出路径
        let outputURL = getDocumentsDirectory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        // 执行导出
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw VideoError.exportFailed
        }

        let fileSize = try getFileSize(from: outputURL)

        return ExportedFile(
            id: UUID(),
            filePath: fileName,
            exportedAt: Date(),
            type: "highlight",
            fileSize: fileSize
        )
    }

    // MARK: - 辅助方法

    private func generateThumbnail(from asset: AVAsset, videoID: String) async throws -> String {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: time).image

        let image = UIImage(cgImage: cgImage)
        let thumbnailFileName = "\(videoID)_thumbnail.jpg"
        let thumbnailPath = getDocumentsDirectory().appendingPathComponent(thumbnailFileName)

        if let data = image.jpegData(compressionQuality: 0.7) {
            try data.write(to: thumbnailPath)
        }

        return thumbnailFileName
    }

    private func getVideoURL(for video: Video) -> URL {
        getDocumentsDirectory().appendingPathComponent(video.originalFilePath)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getFileSize(from url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    private func updateProgress(_ progress: Double, operation: String) async {
        await MainActor.run {
            self.processingProgress = progress
            self.currentOperation = operation
        }
    }
}

// MARK: - 错误类型
enum VideoError: LocalizedError {
    case noVideoTrack
    case exportFailed
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "无法找到视频轨道"
        case .exportFailed:
            return "视频导出失败"
        case .analysisFailed:
            return "视频分析失败"
        }
    }
}
