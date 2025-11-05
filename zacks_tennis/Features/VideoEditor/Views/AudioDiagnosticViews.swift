//
//  AudioDiagnosticViews.swift
//  zacks_tennis
//
//  Created by Claude on 2025-01-05.
//  音频诊断可视化组件 - 用于排查音频峰值检测问题
//

import SwiftUI
import Charts

// MARK: - 主诊断视图

/// 音频诊断主视图
struct AudioDiagnosticMainView: View {
    let diagnosticData: AudioDiagnosticData

    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var showCopiedAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 导出操作按钮区域
                exportActionsView

                // 1. 全局统计卡片
                GlobalStatsCard(data: diagnosticData)

                // 2. RMS 时间序列图
                RMSTimeSeriesChart(rmsData: diagnosticData.rmsTimeSeries)

                // 3. 候选峰值散点图
                CandidatePeaksScatterChart(
                    allCandidates: diagnosticData.allCandidatePeaks,
                    finalPeaks: diagnosticData.finalPeaks
                )

                // 4. 过滤阶段统计
                FilteringStagesChart(stats: diagnosticData.filteringStats)

                // 5. 拒绝原因分布
                RejectionReasonsChart(rejectionReasons: diagnosticData.filteringStats.rejectionReasons)
            }
            .padding()
        }
        .navigationTitle("音频诊断分析")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("已复制", isPresented: $showCopiedAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("JSON 数据已复制到剪贴板")
        }
    }

    // MARK: - Export Actions View

    private var exportActionsView: some View {
        VStack(spacing: 12) {
            Text("导出诊断数据")
                .font(.headline)

            HStack(spacing: 12) {
                // 复制 JSON 按钮
                Button {
                    copyJSONToClipboard()
                } label: {
                    Label("复制 JSON", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                // 分享文件按钮
                Button {
                    shareJSONFile()
                } label: {
                    Label("分享文件", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    /// 复制 JSON 数据到剪贴板
    private func copyJSONToClipboard() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let jsonData = try encoder.encode(diagnosticData)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("❌ [AudioDiagnostic] JSON 字符串转换失败")
                return
            }

            UIPasteboard.general.string = jsonString
            showCopiedAlert = true
            print("✅ [AudioDiagnostic] JSON 数据已复制到剪贴板 (\(jsonString.count) 字符)")
        } catch {
            print("❌ [AudioDiagnostic] JSON 编码失败: \(error.localizedDescription)")
        }
    }

    /// 分享 JSON 文件
    private func shareJSONFile() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let jsonData = try encoder.encode(diagnosticData)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("❌ [AudioDiagnostic] JSON 字符串转换失败")
                return
            }

            // 创建临时文件
            let fileName = "\(diagnosticData.videoInfo.fileName.sanitizedFileComponent(fallback: "diagnostic"))_audio_diagnostic.json"
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileURL = tempDirectory.appendingPathComponent(fileName)

            // 如果文件已存在，先删除
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }

            // 写入文件
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

            shareURL = fileURL
            showingShareSheet = true

            print("✅ [AudioDiagnostic] 准备分享文件: \(fileURL.path)")
        } catch {
            print("❌ [AudioDiagnostic] 文件创建失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - 全局统计卡片

struct GlobalStatsCard: View {
    let data: AudioDiagnosticData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("全局音频特征")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatItem(label: "视频时长", value: String(format: "%.1fs", data.videoInfo.duration))
                StatItem(label: "RMS 均值", value: String(format: "%.3f", data.audioFeatures.overallRMSMean))
                StatItem(label: "RMS 最大值", value: String(format: "%.3f", data.audioFeatures.overallRMSMax))
                StatItem(label: "RMS P90", value: String(format: "%.3f", data.audioFeatures.overallRMSP90))
                StatItem(label: "峰值振幅(最大)", value: String(format: "%.3f", data.audioFeatures.maxPeakAmplitude))
                StatItem(label: "峰值振幅(中位)", value: String(format: "%.3f", data.audioFeatures.medianPeakAmplitude))

                StatItem(label: "候选峰值数", value: "\(data.filteringStats.totalCandidates)", highlight: true)
                StatItem(label: "最终保留数", value: "\(data.filteringStats.finalCount)", highlight: true)
                StatItem(label: "整体通过率", value: String(format: "%.1f%%", data.overallPassRate * 100), highlight: true)
            }

            // 配置信息
            HStack {
                Text("配置:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(data.configuration.presetName)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                Spacer()
                Text("Threshold: \(String(format: "%.2f", data.configuration.peakThreshold))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Confidence: \(String(format: "%.2f", data.configuration.minimumConfidence))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(highlight ? .title3.bold() : .body)
                .foregroundColor(highlight ? .blue : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(highlight ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - RMS 时间序列图

struct RMSTimeSeriesChart: View {
    let rmsData: [RMSDataPoint]

    // 采样数据以避免过多点
    var sampledData: [RMSDataPoint] {
        guard rmsData.count > 500 else { return rmsData }
        let step = rmsData.count / 500
        return stride(from: 0, to: rmsData.count, by: step).map { rmsData[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RMS 时间序列")
                    .font(.headline)
                Spacer()
                Text("\(rmsData.count) 采样点")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if sampledData.isEmpty {
                Text("无 RMS 数据")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(sampledData, id: \.time) { dataPoint in
                    LineMark(
                        x: .value("时间", dataPoint.time),
                        y: .value("RMS", dataPoint.rms)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    // 标记峰值点
                    if let peakAmp = dataPoint.peakAmplitude, peakAmp > 0.1 {
                        PointMark(
                            x: .value("时间", dataPoint.time),
                            y: .value("RMS", dataPoint.rms)
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(30)
                    }
                }
                .chartYScale(domain: 0...0.5)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6))
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 候选峰值散点图

struct CandidatePeaksScatterChart: View {
    let allCandidates: [CandidatePeakData]
    let finalPeaks: [CandidatePeakData]

    // 采样以避免过多点
    var sampledCandidates: [CandidatePeakData] {
        guard allCandidates.count > 200 else { return allCandidates }
        // 保留所有通过的峰值 + 采样拒绝的峰值
        let passed = allCandidates.filter { $0.passedFiltering }
        let rejected = allCandidates.filter { !$0.passedFiltering }
        let rejectedSample = stride(from: 0, to: rejected.count, by: max(1, rejected.count / 100))
            .map { rejected[$0] }
        return passed + rejectedSample
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("候选峰值分布 (振幅 vs 置信度)")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("通过 (\(finalPeaks.count))")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.5)).frame(width: 8, height: 8)
                        Text("拒绝 (\(allCandidates.count - finalPeaks.count))")
                            .font(.caption)
                    }
                }
            }

            if sampledCandidates.isEmpty {
                Text("无候选峰值数据")
                    .foregroundColor(.secondary)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(sampledCandidates) { candidate in
                    PointMark(
                        x: .value("振幅", candidate.amplitude),
                        y: .value("置信度", candidate.confidence)
                    )
                    .foregroundStyle(candidate.passedFiltering ? Color.green : Color.red.opacity(0.5))
                    .symbolSize(candidate.passedFiltering ? 60 : 30)
                }
                .chartXScale(domain: 0...1)
                .chartYScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .frame(height: 250)
            }

            Text("💡 绿色点表示通过过滤的峰值，红色点表示被拒绝的候选")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 过滤阶段统计

struct FilteringStagesChart: View {
    let stats: FilteringStatistics

    var stageData: [(stage: String, count: Int, rate: Double)] {
        let total = Double(stats.totalCandidates)
        guard total > 0 else { return [] }

        return [
            ("候选峰值", stats.totalCandidates, 1.0),
            ("振幅阈值", stats.passedAmplitudeThreshold, Double(stats.passedAmplitudeThreshold) / total),
            ("持续时间", stats.passedDurationCheck, Double(stats.passedDurationCheck) / total),
            ("置信度", stats.passedConfidenceThreshold, Double(stats.passedConfidenceThreshold) / total),
            ("自适应过滤", stats.passedAdaptiveFiltering, Double(stats.passedAdaptiveFiltering) / total),
            ("后处理", stats.afterPostProcessing, Double(stats.afterPostProcessing) / total),
            ("最终保留", stats.finalCount, Double(stats.finalCount) / total)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("过滤阶段漏斗")
                .font(.headline)

            if stageData.isEmpty {
                Text("无过滤统计数据")
                    .foregroundColor(.secondary)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(stageData, id: \.stage) { data in
                    BarMark(
                        x: .value("数量", data.count),
                        y: .value("阶段", data.stage)
                    )
                    .foregroundStyle(by: .value("阶段", data.stage))
                    .annotation(position: .trailing) {
                        HStack(spacing: 4) {
                            Text("\(data.count)")
                                .font(.caption)
                            Text("(\(String(format: "%.1f%%", data.rate * 100)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartXScale(domain: 0...(stats.totalCandidates * 11 / 10))  // 10% padding
                .chartLegend(.hidden)
                .frame(height: 250)
            }

            Text("💡 从上到下显示候选峰值如何被逐层过滤")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 拒绝原因分布

struct RejectionReasonsChart: View {
    let rejectionReasons: [String: Int]

    var sortedReasons: [(reason: String, count: Int)] {
        rejectionReasons.map { (reason: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(10)  // 只显示前10个原因
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拒绝原因分布 (Top 10)")
                .font(.headline)

            if sortedReasons.isEmpty {
                Text("所有候选峰值都通过了过滤 🎉")
                    .foregroundColor(.green)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(sortedReasons, id: \.reason) { data in
                    BarMark(
                        x: .value("数量", data.count),
                        y: .value("原因", data.reason)
                    )
                    .foregroundStyle(Color.orange)
                    .annotation(position: .trailing) {
                        Text("\(data.count)")
                            .font(.caption)
                    }
                }
                .chartXScale(domain: 0...(sortedReasons.first?.count ?? 10) * 11 / 10)  // 10% padding
                .frame(height: max(200, CGFloat(sortedReasons.count) * 40))
            }

            Text("💡 了解为什么候选峰值被拒绝，帮助调整阈值参数")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview("音频诊断主视图") {
    NavigationStack {
        AudioDiagnosticMainView(diagnosticData: createSampleDiagnosticData())
    }
}

// MARK: - Preview Helper

private func createSampleDiagnosticData() -> AudioDiagnosticData {
    let videoInfo = VideoDiagnosticInfo(
        fileName: "test_match.mp4",
        duration: 120.0,
        sampleRate: 44100,
        channelCount: 2
    )

    let audioFeatures = AudioGlobalFeatures(
        overallRMSMean: 0.08,
        overallRMSStdDev: 0.03,
        overallRMSMax: 0.25,
        overallRMSMedian: 0.07,
        overallRMSP90: 0.15,
        maxPeakAmplitude: 0.45,
        medianPeakAmplitude: 0.18,
        dominantFrequencyRange: "1000-3000 Hz",
        estimatedSNR: nil
    )

    // 生成模拟候选峰值
    var allCandidates: [CandidatePeakData] = []
    for i in 0..<50 {
        let amplitude = Double.random(in: 0.05...0.5)
        let confidence = Double.random(in: 0.1...0.9)
        let passed = amplitude > 0.25 && confidence > 0.5

        let breakdown = ConfidenceBreakdown(
            amplitudeScore: amplitude * 0.33,
            crestFactorScore: 0.15,
            energyConcentrationScore: 0.10,
            frequencyRangeScore: 0.12,
            highFreqEnergyScore: 0.10,
            otherFeaturesScore: 0.02
        )

        let spectralFeatures = SpectralFeatures(
            dominantFrequency: 2000,
            spectralCentroid: 1500,
            spectralRolloff: 3500,
            lowFreqEnergy: 0.2,
            primaryHitRangeEnergy: 0.4,
            highFreqEnergy: 0.3,
            mfccMean: [1.0, 0.5, 0.3, 0.2, 0.1]
        )

        allCandidates.append(CandidatePeakData(
            time: Double(i) * 2.0,
            amplitude: amplitude,
            rms: amplitude * 0.7,
            duration: 0.05,
            confidence: confidence,
            confidenceBreakdown: breakdown,
            spectralFeatures: spectralFeatures,
            passedFiltering: passed,
            rejectionReason: passed ? nil : "置信度过低",
            rejectionStage: passed ? nil : "置信度过滤"
        ))
    }

    let finalPeaks = allCandidates.filter { $0.passedFiltering }

    // 生成 RMS 时间序列
    var rmsData: [RMSDataPoint] = []
    for i in 0..<200 {
        rmsData.append(RMSDataPoint(
            time: Double(i) * 0.6,
            rms: 0.05 + Double.random(in: 0...0.15),
            peakAmplitude: i % 10 == 0 ? Double.random(in: 0.2...0.4) : nil
        ))
    }

    let stats = FilteringStatistics(
        totalCandidates: 50,
        passedAmplitudeThreshold: 35,
        passedDurationCheck: 30,
        passedConfidenceThreshold: 20,
        passedAdaptiveFiltering: 18,
        afterPostProcessing: 15,
        finalCount: finalPeaks.count,
        rejectionReasons: [
            "振幅低于阈值": 15,
            "置信度过低": 10,
            "持续时间不符": 5,
            "自适应过滤": 2,
            "后处理合并": 3
        ],
        averageConfidence: 0.65,
        medianConfidence: 0.62
    )

    let config = AudioConfigSnapshot(
        peakThreshold: 0.25,
        minimumConfidence: 0.50,
        minimumPeakInterval: 0.18,
        presetName: "default"
    )

    return AudioDiagnosticData(
        videoInfo: videoInfo,
        audioFeatures: audioFeatures,
        allCandidatePeaks: allCandidates,
        finalPeaks: finalPeaks,
        filteringStats: stats,
        rmsTimeSeries: rmsData,
        spectralSamples: nil,
        configuration: config,
        timestamp: Date()
    )
}
