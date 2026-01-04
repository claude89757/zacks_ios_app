//
//  ExportState.swift
//  zacks_tennis
//
//  视频导出状态和错误类型
//

import Foundation

/// 导出状态枚举 - 统一管理导出生命周期
enum ExportState: Equatable {
    /// 空闲状态
    case idle

    /// 准备中（验证文件、初始化）
    case preparing

    /// 导出中（0.0-1.0）
    case exporting(progress: Double)

    /// 编码中（合并视频时）
    case encoding(progress: Double)

    /// 保存到相册中
    case savingToPhotos

    /// 完成（成功数量）
    case completed(count: Int)

    /// 失败
    case failed(error: ExportError)

    /// 已取消
    case cancelled

    // MARK: - Computed Properties

    /// 是否正在活跃执行
    var isActive: Bool {
        switch self {
        case .preparing, .exporting, .encoding, .savingToPhotos:
            return true
        default:
            return false
        }
    }

    /// 当前进度值 (0.0 - 1.0)
    var progress: Double {
        switch self {
        case .exporting(let p), .encoding(let p):
            return p
        case .completed:
            return 1.0
        case .savingToPhotos:
            return 0.95
        default:
            return 0.0
        }
    }

    /// 是否已完成（成功或失败）
    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    /// 是否成功完成
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    /// 显示文本
    var displayText: String {
        switch self {
        case .idle:
            return "准备就绪"
        case .preparing:
            return "正在准备..."
        case .exporting(let p):
            return "导出中 \(Int(p * 100))%"
        case .encoding(let p):
            return "编码中 \(Int(p * 100))%"
        case .savingToPhotos:
            return "正在保存到相册..."
        case .completed(let count):
            if count == 1 {
                return "导出成功"
            } else {
                return "成功导出 \(count) 个视频"
            }
        case .failed(let error):
            return error.localizedDescription
        case .cancelled:
            return "已取消"
        }
    }

    /// 状态图标名称
    var iconName: String {
        switch self {
        case .idle, .preparing:
            return "circle.dotted"
        case .exporting, .encoding:
            return "arrow.triangle.2.circlepath"
        case .savingToPhotos:
            return "photo.on.rectangle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }
}

// MARK: - Equatable conformance for ExportError

extension ExportState {
    static func == (lhs: ExportState, rhs: ExportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.preparing, .preparing),
             (.savingToPhotos, .savingToPhotos),
             (.cancelled, .cancelled):
            return true
        case (.exporting(let p1), .exporting(let p2)),
             (.encoding(let p1), .encoding(let p2)):
            return p1 == p2
        case (.completed(let c1), .completed(let c2)):
            return c1 == c2
        case (.failed(let e1), .failed(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

/// 导出错误枚举
enum ExportError: LocalizedError, Equatable {
    /// 源文件不存在
    case sourceFileNotFound(path: String)

    /// 时间范围无效
    case invalidTimeRange(start: Double, end: Double)

    /// 无法创建导出会话
    case exportSessionCreationFailed

    /// 导出会话失败
    case exportSessionFailed(reason: String)

    /// 导出超时
    case timeout

    /// 用户取消
    case cancelled

    /// 相册权限被拒绝
    case photoLibraryAccessDenied

    /// 文件验证失败
    case fileVerificationFailed

    /// 存储空间不足
    case insufficientStorage

    /// 找不到视频轨道
    case noVideoTrack

    /// 未知错误
    case unknownError(message: String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .sourceFileNotFound(let path):
            return "源视频不存在: \(path)"
        case .invalidTimeRange(let start, let end):
            return "时间范围无效 (\(String(format: "%.1f", start))s - \(String(format: "%.1f", end))s)"
        case .exportSessionCreationFailed:
            return "无法创建导出会话"
        case .exportSessionFailed(let reason):
            return "导出失败: \(reason)"
        case .timeout:
            return "导出超时，请重试"
        case .cancelled:
            return "导出已取消"
        case .photoLibraryAccessDenied:
            return "需要相册权限才能保存视频"
        case .fileVerificationFailed:
            return "导出文件验证失败，可能已损坏"
        case .insufficientStorage:
            return "存储空间不足"
        case .noVideoTrack:
            return "找不到视频轨道"
        case .unknownError(let message):
            return message
        }
    }

    /// 用户友好的恢复建议
    var recoverySuggestion: String? {
        switch self {
        case .sourceFileNotFound:
            return "请确认视频文件未被删除或移动"
        case .invalidTimeRange:
            return "请选择有效的片段时间范围"
        case .exportSessionCreationFailed, .exportSessionFailed:
            return "请重试，如果问题持续请重启应用"
        case .timeout:
            return "视频可能过长，请尝试分批导出"
        case .cancelled:
            return nil
        case .photoLibraryAccessDenied:
            return "请在设置中允许访问相册"
        case .fileVerificationFailed:
            return "请重试导出"
        case .insufficientStorage:
            return "请清理一些空间后重试"
        case .noVideoTrack:
            return "视频文件可能已损坏"
        case .unknownError:
            return "请重试，如果问题持续请联系支持"
        }
    }
}

/// 导出任务配置
struct ExportTaskConfiguration: Sendable {
    /// 视频ID
    let videoId: UUID

    /// 视频原始文件路径
    let videoFilePath: String

    /// 视频标题（用于生成文件名）
    let videoTitle: String

    /// 要导出的精彩片段列表
    let highlights: [HighlightInfo]

    /// 导出质量
    let quality: ExportQuality

    /// 是否合并为单个视频
    let mergeIntoSingle: Bool

    /// 导出名称前缀
    let exportNamePrefix: String

    /// 超时时间（秒）
    let timeoutSeconds: TimeInterval

    /// 默认超时时间：10分钟
    static let defaultTimeout: TimeInterval = 600

    init(
        videoId: UUID,
        videoFilePath: String,
        videoTitle: String,
        highlights: [HighlightInfo],
        quality: ExportQuality = .high,
        mergeIntoSingle: Bool = true,
        exportNamePrefix: String = "highlight",
        timeoutSeconds: TimeInterval = ExportTaskConfiguration.defaultTimeout
    ) {
        self.videoId = videoId
        self.videoFilePath = videoFilePath
        self.videoTitle = videoTitle
        self.highlights = highlights
        self.quality = quality
        self.mergeIntoSingle = mergeIntoSingle
        self.exportNamePrefix = exportNamePrefix
        self.timeoutSeconds = timeoutSeconds
    }
}

/// 精彩片段信息（用于导出配置，轻量级）
struct HighlightInfo: Sendable {
    let id: UUID
    let startTime: Double
    let endTime: Double

    var duration: Double {
        endTime - startTime
    }
}
