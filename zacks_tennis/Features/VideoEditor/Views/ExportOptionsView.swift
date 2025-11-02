//
//  ExportOptionsView.swift
//  zacks_tennis
//
//  导出选项页 - 选择导出格式、质量、回合范围
//

import SwiftUI
import SwiftData
import AVFoundation

struct ExportOptionsView: View {
    let video: Video
    let rallies: [VideoHighlight]
    @Bindable var viewModel: VideoEditorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var exportType: ExportUIType = .highlights
    @State private var exportQuality: ExportUIQuality = .high
    @State private var selectedRallies: Set<UUID> = []
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var currentExportingIndex: Int = 0
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 导出类型
                    exportTypeSection

                    // 导出质量
                    exportQualitySection

                    // 回合选择（仅在导出精选回合时显示）
                    if exportType == .selected {
                        rallySelectionSection
                    }

                    // 预计大小
                    estimatedSizeSection

                    // 导出按钮
                    exportButton
                }
                .padding()
            }
            .navigationTitle("导出选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isExporting {
                    exportProgressOverlay
                }
            }
        }
    }

    // MARK: - Export Type Section

    private var exportTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出类型")
                .font(.headline)

            VStack(spacing: 12) {
                ExportUITypeCard(
                    type: .highlights,
                    isSelected: exportType == .highlights,
                    rallyCount: rallies.filter { $0.excitementScore >= 70 }.count
                )
                .onTapGesture {
                    exportType = .highlights
                }

                ExportUITypeCard(
                    type: .all,
                    isSelected: exportType == .all,
                    rallyCount: rallies.count
                )
                .onTapGesture {
                    exportType = .all
                }

                ExportUITypeCard(
                    type: .selected,
                    isSelected: exportType == .selected,
                    rallyCount: selectedRallies.count
                )
                .onTapGesture {
                    exportType = .selected
                }
            }
        }
    }

    // MARK: - Export Quality Section

    private var exportQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导出质量")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(ExportUIQuality.allCases, id: \.self) { quality in
                    ExportUIQualityCard(
                        quality: quality,
                        isSelected: exportQuality == quality
                    )
                    .onTapGesture {
                        exportQuality = quality
                    }
                }
            }
        }
    }

    // MARK: - Rally Selection Section

    private var rallySelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择回合")
                    .font(.headline)

                Spacer()

                if selectedRallies.count == rallies.count {
                    Button("取消全选") {
                        selectedRallies.removeAll()
                    }
                    .font(.caption)
                } else {
                    Button("全选") {
                        selectedRallies = Set(rallies.map { $0.id })
                    }
                    .font(.caption)
                }
            }

            LazyVStack(spacing: 8) {
                ForEach(rallies) { rally in
                    RallySelectionRow(
                        rally: rally,
                        isSelected: selectedRallies.contains(rally.id)
                    )
                    .onTapGesture {
                        toggleRallySelection(rally)
                    }
                }
            }
        }
    }

    // MARK: - Estimated Size Section

    private var estimatedSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预计大小")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("总时长")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatDuration(estimatedDuration))
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("文件大小")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatFileSize(estimatedSize))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        VStack(spacing: 8) {
            Button {
                startExport()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(canExport ? "开始导出" : (viewModel.isBusy ? "有任务进行中..." : "请选择回合"))
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canExport ? Color.green : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!canExport)

            // 🔥 新增：提示信息
            if viewModel.isBusy {
                Text(viewModel.busyStatusMessage ?? "")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Export Progress Overlay

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: exportProgress)
                    .tint(.green)
                    .frame(width: 200)

                Text("导出中... \(Int(exportProgress * 100))%")
                    .foregroundColor(.white)
                    .font(.headline)

                Text("正在导出 \(currentExportingIndex)/\(exportRallies.count)")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)

                Button("取消") {
                    exportTask?.cancel()
                    isExporting = false
                    exportProgress = 0.0
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)
            }
            .padding(40)
            .background(Color(.systemGray5))
            .cornerRadius(20)
        }
    }

    // MARK: - Computed Properties

    private var canExport: Bool {
        // 🔥 先检查是否有其他任务在进行
        guard viewModel.canStartNewTask else {
            return false
        }

        switch exportType {
        case .highlights:
            return rallies.filter { $0.excitementScore >= 70 }.count > 0
        case .all:
            return !rallies.isEmpty
        case .selected:
            return !selectedRallies.isEmpty
        }
    }

    private var exportRallies: [VideoHighlight] {
        switch exportType {
        case .highlights:
            return rallies.filter { $0.excitementScore >= 70 }
        case .all:
            return rallies
        case .selected:
            return rallies.filter { selectedRallies.contains($0.id) }
        }
    }

    private var estimatedDuration: Double {
        exportRallies.reduce(0) { $0 + $1.duration }
    }

    private var estimatedSize: Int {
        // 根据质量和时长估算文件大小
        let baseRate: Double = switch exportQuality {
        case .low: 1.0  // 1 MB/min
        case .medium: 3.0  // 3 MB/min
        case .high: 8.0  // 8 MB/min
        case .original: 20.0  // 20 MB/min
        }

        let minutes = estimatedDuration / 60.0
        return Int(minutes * baseRate * 1024 * 1024)  // Convert to bytes
    }

    // MARK: - Helper Methods

    private func toggleRallySelection(_ rally: VideoHighlight) {
        if selectedRallies.contains(rally.id) {
            selectedRallies.remove(rally.id)
        } else {
            selectedRallies.insert(rally.id)
        }
    }

    private func startExport() {
        isExporting = true
        exportProgress = 0.0
        currentExportingIndex = 0

        // 启动真实的导出任务
        exportTask = Task {
            await performExport()
        }
    }

    private func performExport() async {
        let ralliesToExport = exportRallies
        let totalCount = ralliesToExport.count

        guard totalCount > 0 else {
            await MainActor.run {
                isExporting = false
            }
            return
        }

        // 获取视频源路径
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = documentsURL.appendingPathComponent(video.originalFilePath)
        let asset = AVAsset(url: videoURL)

        // 获取导出预设
        let exportPreset = exportQuality.avExportPreset

        // 依次导出每个回合
        for (index, rally) in ralliesToExport.enumerated() {
            // 检查是否取消
            if Task.isCancelled {
                break
            }

            await MainActor.run {
                currentExportingIndex = index + 1
            }

            // 创建导出会话
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: exportPreset
            ) else {
                print("⚠️ 无法创建导出会话")
                continue
            }

            // 设置时间范围
            let startTime = CMTime(seconds: rally.startTime, preferredTimescale: 600)
            let endTime = CMTime(seconds: rally.endTime, preferredTimescale: 600)
            exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)

            // 设置输出路径
            let fileName = "\(video.title)_rally_\(rally.rallyNumber)_\(Date().timeIntervalSince1970).mp4"
            let outputURL = documentsURL.appendingPathComponent(fileName)

            // 删除已存在的文件
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4

            // 执行导出
            await exportSession.export()

            // 检查导出状态
            if exportSession.status == .completed {
                print("✅ 成功导出回合 \(rally.rallyNumber)")

                // 更新导出记录到视频模型
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 {
                    let exportedFile = ExportedFile(
                        id: UUID(),
                        filePath: fileName,
                        exportedAt: Date(),
                        type: exportType.typeString,
                        fileSize: fileSize
                    )

                    await MainActor.run {
                        video.addExportedFile(exportedFile)
                    }
                }
            } else if let error = exportSession.error {
                print("❌ 导出失败: \(error.localizedDescription)")
            }

            // 更新进度
            let progress = Double(index + 1) / Double(totalCount)
            await MainActor.run {
                exportProgress = progress
            }
        }

        // 导出完成
        await MainActor.run {
            isExporting = false
            dismiss()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1024.0 / 1024.0
        if megabytes >= 1024 {
            return String(format: "%.1f GB", megabytes / 1024.0)
        } else {
            return String(format: "%.0f MB", megabytes)
        }
    }
}

// MARK: - Export UI Type

enum ExportUIType {
    case highlights, all, selected

    var title: String {
        switch self {
        case .highlights: return "精彩回合"
        case .all: return "全部回合"
        case .selected: return "自选回合"
        }
    }

    var description: String {
        switch self {
        case .highlights: return "导出精彩度 ≥ 70 的回合"
        case .all: return "导出所有检测到的回合"
        case .selected: return "手动选择要导出的回合"
        }
    }

    var icon: String {
        switch self {
        case .highlights: return "star.fill"
        case .all: return "list.bullet"
        case .selected: return "checkmark.circle"
        }
    }

    var typeString: String {
        switch self {
        case .highlights: return "highlights"
        case .all: return "all"
        case .selected: return "selected"
        }
    }
}

// MARK: - Export UI Quality

enum ExportUIQuality: CaseIterable {
    case low, medium, high, original

    var title: String {
        switch self {
        case .low: return "低质量"
        case .medium: return "中等质量"
        case .high: return "高质量"
        case .original: return "原始质量"
        }
    }

    var description: String {
        switch self {
        case .low: return "720p · 适合分享"
        case .medium: return "1080p · 平衡大小与质量"
        case .high: return "1080p · 高比特率"
        case .original: return "保持原始分辨率和质量"
        }
    }

    var icon: String {
        switch self {
        case .low: return "circle.fill"
        case .medium: return "circle.lefthalf.filled"
        case .high: return "circle.righthalf.filled"
        case .original: return "circle"
        }
    }

    var avExportPreset: String {
        switch self {
        case .low: return AVAssetExportPreset1280x720
        case .medium: return AVAssetExportPreset1920x1080
        case .high: return AVAssetExportPresetHighestQuality
        case .original: return AVAssetExportPresetPassthrough
        }
    }
}

// MARK: - Export UI Type Card

struct ExportUITypeCard: View {
    let type: ExportUIType
    let isSelected: Bool
    let rallyCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(type.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 4) {
                Text("\(rallyCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .green : .primary)

                Text("个回合")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Export UI Quality Card

struct ExportUIQualityCard: View {
    let quality: ExportUIQuality
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: quality.icon)
                .font(.title3)
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(quality.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(quality.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Rally Selection Row

struct RallySelectionRow: View {
    let rally: VideoHighlight
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(rally.rallyNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)

                    Text(rally.type)
                        .font(.subheadline)
                }

                HStack(spacing: 8) {
                    Label(rally.durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("精彩度 \(Int(rally.excitementScore))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
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

    ExportOptionsView(video: sampleVideo, rallies: sampleRallies, viewModel: VideoEditorViewModel())
}
