//
//  AnalysisDebugExporter.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  调试数据导出服务 - 用于算法优化和问题排查
//

import Foundation
import UIKit
import SwiftData

/// 分析调试数据导出器
@MainActor
class AnalysisDebugExporter {

    // MARK: - Public Methods

    /// 生成完整的调试 JSON 数据
    /// - Parameter video: 视频对象
    /// - Returns: 调试数据结构
    static func generateDebugData(from video: Video) -> AnalysisDebugData {
        let videoInfo = VideoInfo(
            fileName: video.title,
            duration: video.duration,
            rallyCount: video.rallyCount,
            totalHitCount: video.highlights.reduce(0) { $0 + ($1.metadata?.estimatedHitCount ?? 0) },
            resolution: "\(Int(video.width))x\(Int(video.height))",
            fileSize: video.fileSize,
            averageRallyDuration: video.averageRallyDuration,
            longestRallyDuration: video.longestRallyDuration,
            excitingRallyCount: video.excitingRallyCount,
            excitementRate: video.excitementRate
        )

        let rallies = video.highlights.enumerated().map { index, highlight in
            RallyDebugData(
                index: index + 1,
                startTime: highlight.startTime,
                endTime: highlight.endTime,
                duration: highlight.duration,
                hitCount: highlight.metadata?.estimatedHitCount ?? 0,
                excitementScore: highlight.excitementScore,
                detectionConfidence: highlight.detectionConfidence,
                type: highlight.type,
                hitTimestamps: highlight.audioPeakTimestamps,
                metadata: highlight.metadata.map { metadata in
                    RallyMetadata(
                        maxMovementIntensity: metadata.maxMovementIntensity,
                        avgMovementIntensity: metadata.avgMovementIntensity,
                        hasAudioPeaks: metadata.hasAudioPeaks,
                        poseConfidenceAvg: metadata.poseConfidenceAvg,
                        playerCount: metadata.playerCount
                    )
                }
            )
        }

        // 提取所有击球事件（从回合的 metadata 中）
        let hitEvents = extractHitEvents(from: video)

        // 尝试从 Video.debugDataJSON 读取运行时调试数据
        var intervalStats: IntervalStatisticsData? = nil
        var bayesianPoints: [BayesianChangePointData]? = nil

        if let debugJSON = video.debugDataJSON,
           let debugData = try? JSONDecoder().decode(RuntimeDebugData.self, from: debugJSON.data(using: .utf8) ?? Data()) {
            // 转换间隔统计
            if let stats = debugData.intervalStatistics {
                intervalStats = IntervalStatisticsData(
                    mean: stats.mean,
                    stdDev: stats.stdDev,
                    median: stats.median,
                    percentile75: stats.percentile75,
                    percentile90: stats.percentile90,
                    percentile95: stats.percentile95,
                    rallyBoundaryThreshold: stats.rallyBoundaryThreshold,
                    maxHitInterval: stats.maxHitInterval,
                    totalIntervals: stats.totalIntervals
                )
            }

            // 转换贝叶斯变化点
            if let points = debugData.bayesianChangePoints {
                bayesianPoints = points.map { point in
                    BayesianChangePointData(
                        time: point.time,
                        probability: point.probability,
                        runLength: point.runLength,
                        isChangePoint: point.isChangePoint
                    )
                }
            }
        }

        // 配置信息（使用默认值，因为当前配置存储在分析引擎中）
        let configuration = ConfigurationData(
            audioAnalysis: AudioAnalysisConfig(
                peakThreshold: 0.25,
                minimumConfidence: 0.50,
                minimumPeakInterval: 0.18
            ),
            rallyDetection: RallyDetectionConfig(
                minRallyDuration: 3.0,
                audioConfidenceThreshold: 0.50,
                maxHitInterval: 5.5,
                minHitCount: 3,
                preHitPadding: 1.5,
                postHitPadding: 1.8
            ),
            bayesianCPD: BayesianCPDConfig(
                hazardRate: 0.05,
                withinRallyMean: 2.5,
                withinRallyStdDev: 0.8,
                betweenRallyMean: 10.0,
                betweenRallyStdDev: 3.0,
                minRallyLength: 3,
                confidenceThreshold: 0.55
            )
        )

        return AnalysisDebugData(
            videoInfo: videoInfo,
            rallies: rallies,
            hitEvents: hitEvents,
            intervalStatistics: intervalStats,  // 从 Video.debugDataJSON 读取
            bayesianChangePoints: bayesianPoints,  // 从 Video.debugDataJSON 读取
            configuration: configuration,
            analysisTimestamp: Date()
        )
    }

    /// 将调试数据编码为 JSON 字符串
    /// - Parameter debugData: 调试数据
    /// - Returns: JSON 字符串
    static func encodeToJSON(_ debugData: AnalysisDebugData) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(debugData)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw DebugExporterError.encodingFailed
        }

        return jsonString
    }

    /// 复制调试数据到剪贴板
    /// - Parameter video: 视频对象
    /// - Returns: 是否成功，以及数据大小（字节）
    static func copyToClipboard(video: Video) -> (success: Bool, dataSize: Int) {
        do {
            let debugData = generateDebugData(from: video)
            let jsonString = try encodeToJSON(debugData)

            UIPasteboard.general.string = jsonString

            let dataSize = jsonString.utf8.count
            print("📋 [DebugExporter] 已复制调试数据到剪贴板，大小: \(formatBytes(dataSize))")

            return (true, dataSize)
        } catch {
            print("❌ [DebugExporter] 复制失败: \(error)")
            return (false, 0)
        }
    }

    /// 导出调试数据为文件
    /// - Parameter video: 视频对象
    /// - Returns: 临时文件 URL（如果成功）
    static func exportToFile(video: Video) -> URL? {
        do {
            let debugData = generateDebugData(from: video)
            let jsonString = try encodeToJSON(debugData)

            // 创建临时文件
            let fileName = "\(video.title.replacingOccurrences(of: ".", with: "_"))_debug.json"
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileURL = tempDirectory.appendingPathComponent(fileName)

            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

            print("💾 [DebugExporter] 已导出调试数据到: \(fileURL.path)")

            return fileURL
        } catch {
            print("❌ [DebugExporter] 导出失败: \(error)")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// 从视频中提取所有击球事件
    private static func extractHitEvents(from video: Video) -> [HitEventData] {
        var hitEvents: [HitEventData] = []

        for highlight in video.highlights {
            // 从 metadata 中提取击球时间戳
            guard let timestamps = highlight.metadata?.audioPeakTimestamps, !timestamps.isEmpty else {
                continue
            }

            // 为每个击球点创建事件（使用相对时间转换为绝对时间）
            for relativeTime in timestamps {
                let absoluteTime = highlight.startTime + relativeTime

                // 注意：当前 metadata 不包含详细的音频特征
                // 这里使用占位符数据，实际需要从分析引擎获取
                let audioFeatures = AudioFeatures(
                    amplitude: 0.0,
                    frequency: 0.0,
                    spectralCentroid: 0.0,
                    spectralRolloff: 0.0,
                    spectralContrast: 0.0,
                    spectralFlux: 0.0,
                    highFreqEnergyRatio: 0.0,
                    energyInHitRange: 0.0,
                    crestFactor: 0.0,
                    attackTime: 0.0,
                    eventDuration: 0.0,
                    mfccCoefficients: nil,
                    mfccVariance: nil
                )

                hitEvents.append(HitEventData(
                    time: absoluteTime,
                    confidence: highlight.detectionConfidence,
                    audioFeatures: audioFeatures
                ))
            }
        }

        return hitEvents.sorted { $0.time < $1.time }
    }

    /// 格式化字节大小
    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Errors

enum DebugExporterError: Error {
    case encodingFailed
    case fileCreationFailed

    var localizedDescription: String {
        switch self {
        case .encodingFailed:
            return "JSON 编码失败"
        case .fileCreationFailed:
            return "文件创建失败"
        }
    }
}

// MARK: - Video Extension for Hit Events

extension Video {
    /// 获取所有击球事件（按时间排序）
    var allHitEvents: [(time: Double, confidence: Double)] {
        var events: [(time: Double, confidence: Double)] = []

        for highlight in highlights {
            guard let timestamps = highlight.metadata?.audioPeakTimestamps else { continue }

            for relativeTime in timestamps {
                let absoluteTime = highlight.startTime + relativeTime
                events.append((absoluteTime, highlight.detectionConfidence))
            }
        }

        return events.sorted { $0.time < $1.time }
    }
}
