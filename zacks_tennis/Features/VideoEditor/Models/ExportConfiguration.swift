//
//  ExportConfiguration.swift
//  zacks_tennis
//
//  视频导出配置
//

import Foundation
import AVFoundation

/// 导出配置
struct ExportConfiguration {
    /// 导出类型
    let exportType: ExportType

    /// 导出质量预设
    let qualityPreset: String

    /// 回合数量限制（用于 topN 类型）
    let count: Int?

    init(
        exportType: ExportType,
        qualityPreset: String = AVAssetExportPresetHEVCHighestQuality,
        count: Int? = nil
    ) {
        self.exportType = exportType
        self.qualityPreset = qualityPreset
        self.count = count
    }
}

/// 导出类型
enum ExportType {
    /// 最长的 N 个回合
    case longestRallies(Int)

    /// 最精彩的 N 个回合
    case topExciting(Int)

    /// 收藏的所有回合
    case favorites

    /// 自定义选择的回合
    case custom([UUID])

    var displayName: String {
        switch self {
        case .longestRallies(let count):
            return "最长的 \(count) 个回合"
        case .topExciting(let count):
            return "最精彩的 \(count) 个回合"
        case .favorites:
            return "我收藏的回合"
        case .custom(let ids):
            return "自定义选择（\(ids.count) 个）"
        }
    }
}

/// 导出质量选项
enum ExportQuality {
    case highest
    case high
    case medium
    case low

    var presetName: String {
        switch self {
        case .highest:
            return AVAssetExportPresetHEVCHighestQuality
        case .high:
            return AVAssetExportPreset1920x1080
        case .medium:
            return AVAssetExportPreset1280x720
        case .low:
            return AVAssetExportPreset960x540
        }
    }

    var displayName: String {
        switch self {
        case .highest:
            return "最高质量（HEVC）"
        case .high:
            return "高质量（1080p）"
        case .medium:
            return "标准质量（720p）"
        case .low:
            return "节省空间（540p）"
        }
    }
}

/// 导出进度
struct ExportProgress {
    /// 当前正在导出的索引
    var currentIndex: Int

    /// 总数
    var totalCount: Int

    /// 当前文件的导出进度 (0-1)
    var currentFileProgress: Double

    /// 总体进度 (0-1)
    var overallProgress: Double {
        if totalCount == 0 { return 0.0 }
        let completedProgress = Double(currentIndex) / Double(totalCount)
        let currentProgress = currentFileProgress / Double(totalCount)
        return completedProgress + currentProgress
    }

    /// 进度百分比文本
    var percentageText: String {
        String(format: "%.0f%%", overallProgress * 100)
    }

    /// 当前状态文本
    var statusText: String {
        "正在导出第 \(currentIndex + 1)/\(totalCount) 个视频"
    }
}

/// 导出结果
struct ExportResult {
    /// 成功导出的文件 URL 列表
    let successfulExports: [URL]

    /// 失败的回合 ID 列表
    let failedExports: [UUID]

    /// 总用时（秒）
    let totalDuration: TimeInterval

    var isSuccess: Bool {
        !successfulExports.isEmpty && failedExports.isEmpty
    }

    var successCount: Int {
        successfulExports.count
    }

    var failureCount: Int {
        failedExports.count
    }

    var summaryText: String {
        if isSuccess {
            return "成功导出 \(successCount) 个视频"
        } else if successCount > 0 {
            return "成功导出 \(successCount) 个，失败 \(failureCount) 个"
        } else {
            return "导出失败"
        }
    }
}
