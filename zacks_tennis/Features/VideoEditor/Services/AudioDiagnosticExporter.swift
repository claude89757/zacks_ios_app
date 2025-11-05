//
//  AudioDiagnosticExporter.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  音频诊断数据导出服务 - 自动将诊断数据保存为 JSON 文件
//

import Foundation

/// 音频诊断数据导出器
@MainActor
class AudioDiagnosticExporter {

    // MARK: - Public Methods

    /// 将诊断数据导出为临时 JSON 文件
    /// - Parameters:
    ///   - diagnosticData: 音频诊断数据
    ///   - videoTitle: 视频标题（用于生成文件名）
    /// - Returns: 文件 URL（如果成功）
    static func exportToFile(
        diagnosticData: AudioDiagnosticData,
        videoTitle: String
    ) -> URL? {
        do {
            // 将诊断数据编码为 JSON
            let jsonString = try encodeToJSON(diagnosticData)

            // 生成安全的文件名
            let sanitizedTitle = videoTitle.sanitizedFileComponent(fallback: "video")
            let fileName = "\(sanitizedTitle)_audio_diagnostic.json"

            // 创建临时文件路径
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileURL = tempDirectory.appendingPathComponent(fileName)

            // 如果文件已存在，先删除（确保使用最新数据）
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }

            // 写入文件
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

            let dataSize = jsonString.utf8.count
            print("💾 [AudioDiagnosticExporter] 已导出诊断数据: \(fileURL.path)")
            print("📊 [AudioDiagnosticExporter] 文件大小: \(formatBytes(dataSize))")
            print("📈 [AudioDiagnosticExporter] 候选峰值: \(diagnosticData.allCandidatePeaks.count) 个，最终保留: \(diagnosticData.finalPeaks.count) 个")

            return fileURL
        } catch {
            print("❌ [AudioDiagnosticExporter] 导出失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 从文件路径读取诊断数据
    /// - Parameter filePath: 文件路径
    /// - Returns: 音频诊断数据（如果成功）
    static func loadFromFile(filePath: String) -> AudioDiagnosticData? {
        do {
            let fileURL = URL(fileURLWithPath: filePath)

            // 检查文件是否存在
            guard FileManager.default.fileExists(atPath: filePath) else {
                print("⚠️ [AudioDiagnosticExporter] 文件不存在: \(filePath)")
                return nil
            }

            // 读取文件内容
            let jsonString = try String(contentsOf: fileURL, encoding: .utf8)
            let jsonData = jsonString.data(using: .utf8)!

            // 解码 JSON
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let diagnosticData = try decoder.decode(AudioDiagnosticData.self, from: jsonData)

            print("📂 [AudioDiagnosticExporter] 已加载诊断数据: \(filePath)")
            print("📊 [AudioDiagnosticExporter] 候选峰值: \(diagnosticData.allCandidatePeaks.count) 个，最终保留: \(diagnosticData.finalPeaks.count) 个")

            return diagnosticData
        } catch {
            print("❌ [AudioDiagnosticExporter] 加载失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// 将诊断数据编码为 JSON 字符串
    private static func encodeToJSON(_ diagnosticData: AudioDiagnosticData) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(diagnosticData)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw AudioDiagnosticExporterError.encodingFailed
        }

        return jsonString
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

enum AudioDiagnosticExporterError: Error {
    case encodingFailed
    case fileCreationFailed
    case fileNotFound

    var localizedDescription: String {
        switch self {
        case .encodingFailed:
            return "JSON 编码失败"
        case .fileCreationFailed:
            return "文件创建失败"
        case .fileNotFound:
            return "文件不存在"
        }
    }
}
