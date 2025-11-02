//
//  Video.swift
//  zacks_tennis
//
//  视频模型 - 存储用户导入的网球视频和处理结果
//

import Foundation
import SwiftData
import CoreGraphics

@Model
final class Video {
    /// 唯一标识符
    var id: UUID

    /// 视频标题
    var title: String

    /// 原始视频文件路径（本地 Documents 目录）
    var originalFilePath: String

    /// 缩略图路径
    var thumbnailPath: String?

    /// 视频时长（秒）
    var duration: Double

    /// 视频分辨率宽度
    var width: Int

    /// 视频分辨率高度
    var height: Int

    /// 文件大小（字节）
    var fileSize: Int64

    /// 创建时间
    var createdAt: Date

    /// 最后处理时间
    var lastProcessedAt: Date?

    // MARK: - AI 分析状态

    /// AI 分析状态（等待分析/分析中/已完成/已取消/失败）
    var analysisStatus: String

    /// AI 分析进度 (0.0 - 1.0)
    var analysisProgress: Double

    /// 当前分析阶段详细描述（如"正在分析动作... 45%"）
    var currentAnalysisStage: String

    /// 分析任务是否可取消
    var canCancelAnalysis: Bool

    // MARK: - AI 分析结果

    /// 是否已分析
    var isAnalyzed: Bool

    /// 检测到的回合数量（总数）
    var rallyCount: Int

    /// 回合关系（一对多）
    @Relationship(deleteRule: .cascade, inverse: \VideoHighlight.video)
    var highlights: [VideoHighlight]

    /// 平均回合时长（秒）
    var averageRallyDuration: Double

    /// 最长回合时长（秒）
    var longestRallyDuration: Double

    /// 平均击球速度（暂留，未来实现）
    var averageBallSpeed: Double?

    /// 检测到的人数
    var detectedPersonCount: Int

    // MARK: - 导出记录

    /// 导出的片段数量
    var exportedClipsCount: Int

    /// 最后导出时间
    var lastExportedAt: Date?

    /// 导出文件路径列表（JSON 字符串）
    var exportedFilesJSON: String?

    /// 备注
    var notes: String

    /// 标签
    var tags: [String]

    init(
        title: String,
        originalFilePath: String,
        duration: Double,
        width: Int,
        height: Int,
        fileSize: Int64
    ) {
        self.id = UUID()
        self.title = title
        self.originalFilePath = originalFilePath
        self.duration = duration
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.createdAt = Date()

        // 初始化 AI 分析状态
        self.analysisStatus = "等待分析"
        self.analysisProgress = 0.0
        self.currentAnalysisStage = ""
        self.canCancelAnalysis = false

        // 初始化分析结果
        self.isAnalyzed = false
        self.rallyCount = 0
        self.highlights = []
        self.averageRallyDuration = 0.0
        self.longestRallyDuration = 0.0
        self.detectedPersonCount = 0

        // 初始化导出记录
        self.exportedClipsCount = 0

        self.notes = ""
        self.tags = []
    }
}

// MARK: - 导出文件信息
struct ExportedFile: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let exportedAt: Date
    let type: String // top5/top10/custom
    let fileSize: Int64
}

// MARK: - 便利方法
extension Video {
    /// 获取视频分辨率文本
    var resolutionText: String {
        "\(width) × \(height)"
    }

    /// 获取文件大小文本
    var fileSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// 获取时长文本
    var durationText: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 剪辑后总时长（所有回合片段的总时长，单位：秒）
    var totalEditedDuration: Double {
        highlights.reduce(0.0) { $0 + $1.duration }
    }

    /// 剪辑后总时长文本
    var totalEditedDurationText: String {
        let totalSeconds = Int(totalEditedDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 精彩回合数量（精彩度 >= 70）
    var excitingRallyCount: Int {
        highlights.filter { $0.excitementScore >= 70 }.count
    }

    /// 精彩率（百分比）
    var excitementRate: Int {
        guard rallyCount > 0 else { return 0 }
        return Int((Double(excitingRallyCount) / Double(rallyCount)) * 100)
    }

    /// 获取导出文件列表
    var exportedFiles: [ExportedFile] {
        get {
            guard let json = exportedFilesJSON,
                  let data = json.data(using: .utf8) else {
                return []
            }
            return (try? JSONDecoder().decode([ExportedFile].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                exportedFilesJSON = json
            }
        }
    }

    /// 获取 Top N 精彩片段（按精彩度排序）
    func getTopHighlights(count: Int) -> [VideoHighlight] {
        return highlights
            .sorted { $0.excitementScore > $1.excitementScore }
            .prefix(count)
            .map { $0 } // Convert ArraySlice to Array
    }

    /// 获取最长的 N 个回合
    func getLongestHighlights(count: Int) -> [VideoHighlight] {
        return highlights
            .sorted { $0.duration > $1.duration }
            .prefix(count)
            .map { $0 }
    }

    /// 获取收藏的回合
    var favoriteHighlights: [VideoHighlight] {
        highlights.filter { $0.isFavorite }
    }

    /// 是否正在处理
    var isProcessing: Bool {
        analysisStatus == "分析中"
    }

    /// 更新统计数据
    func updateStatistics() {
        rallyCount = highlights.count

        if !highlights.isEmpty {
            let durations = highlights.map { $0.duration }
            averageRallyDuration = durations.reduce(0, +) / Double(durations.count)
            longestRallyDuration = durations.max() ?? 0.0
        } else {
            averageRallyDuration = 0.0
            longestRallyDuration = 0.0
        }
    }

    /// 添加导出记录
    func addExportedFile(_ file: ExportedFile) {
        var files = exportedFiles
        files.append(file)
        exportedFiles = files
        exportedClipsCount = files.count
        lastExportedAt = Date()
    }

    // MARK: - AI 分析状态管理（新增）

    /// 更新 AI 分析状态
    func updateAnalysisStatus(_ status: String, progress: Double = 0.0, stage: String = "") {
        self.analysisStatus = status
        self.analysisProgress = progress
        self.currentAnalysisStage = stage

        // 根据状态更新相关标志
        switch status {
        case "分析中":
            self.canCancelAnalysis = true
        case "已完成":
            self.canCancelAnalysis = false
            self.isAnalyzed = true
            self.lastProcessedAt = Date()
        case "失败", "已取消":
            self.canCancelAnalysis = false
        default:
            break
        }
    }

    /// 开始分析
    func startAnalysis() {
        updateAnalysisStatus("分析中", progress: 0.0, stage: "正在准备分析...")
    }

    /// 完成分析
    func completeAnalysis() {
        updateAnalysisStatus("已完成", progress: 1.0, stage: "分析完成")
        updateStatistics()
    }

    /// 取消分析
    func cancelAnalysis() {
        updateAnalysisStatus("已取消", progress: analysisProgress, stage: "已取消分析")
    }

    /// 分析失败
    func failAnalysis(error: String) {
        updateAnalysisStatus("失败", progress: analysisProgress, stage: "分析失败: \(error)")
    }

    /// 是否正在分析
    var isAnalyzing: Bool {
        analysisStatus == "分析中"
    }

    /// 是否正在导入
    var isImporting: Bool {
        analysisStatus == "导入中"
    }

    /// 是否可以编辑（必须分析完成）
    var canEdit: Bool {
        analysisStatus == "已完成" && isAnalyzed
    }

    // MARK: - 视频导入状态管理（新增）

    /// 开始导入
    func startImport() {
        updateAnalysisStatus("导入中", progress: 0.0, stage: "正在从照片库加载视频...")
    }

    /// 更新导入进度
    func updateImportProgress(_ progress: Double, stage: String) {
        updateAnalysisStatus("导入中", progress: progress, stage: stage)
    }

    /// 完成导入，准备分析
    func completeImport() {
        updateAnalysisStatus("等待分析", progress: 0.0, stage: "")
    }

    /// 导入失败
    func failImport(error: String) {
        updateAnalysisStatus("导入失败", progress: analysisProgress, stage: "导入失败: \(error)")
    }
}

// MARK: - File Name Sanitizing

extension String {
    /// Produces a safe file-name component by stripping characters that are illegal on Apple platforms.
    func sanitizedFileComponent(fallback: String = "file") -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:?%*|\"<>")
            .union(.newlines)
            .union(.illegalCharacters)
            .union(.controlCharacters)

        let components = self.components(separatedBy: invalidCharacters)
        let joined = components.filter { !$0.isEmpty }.joined(separator: "_")
        let collapsedSpaces = joined.replacingOccurrences(of: " ", with: "_")
        let trimmed = collapsedSpaces.trimmingCharacters(in: CharacterSet(charactersIn: "._"))

        if trimmed.isEmpty {
            return fallback
        }

        return String(trimmed.prefix(80))
    }
}
