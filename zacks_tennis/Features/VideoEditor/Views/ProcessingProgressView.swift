//
//  ProcessingProgressView.swift
//  zacks_tennis
//
//  视频处理进度视图 - 显示 AI 分析进度和实时回合检测
//

import SwiftUI

struct ProcessingProgressView: View {
    let video: Video
    let processingEngine: VideoProcessingEngine
    @State private var progress: ProcessingProgress?
    @State private var detectedRallies: [VideoHighlight] = []
    @State private var isCancelled = false
    @State private var processingTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    // 🔥 性能优化：将进度四舍五入到10%精度，进一步减少动画触发
    private var roundedProgress: Double {
        let rawProgress = progress?.overallProgress ?? 0
        return (rawProgress * 10).rounded() / 10  // 四舍五入到0.10的倍数
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息
            headerSection

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // 进度圆环
                    progressRingSection

                    // 统计信息
                    statsSection

                    // 实时检测到的回合列表
                    if !detectedRallies.isEmpty {
                        rallyListSection
                    }
                }
                .padding()
            }

            Divider()

            // 底部按钮
            bottomButtons
        }
        .navigationTitle("AI 分析中")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startProcessing()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(1)

            Text(progress?.currentOperation ?? "准备开始分析...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Progress Ring

    private var progressRingSection: some View {
        ZStack {
            // 背景圆环
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                .frame(width: 200, height: 200)

            // 进度圆环（使用 roundedProgress 减少动画触发频率）
            Circle()
                .trim(from: 0, to: roundedProgress)
                .stroke(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: roundedProgress)

            // 中心文字
            VStack(spacing: 4) {
                Text("\(Int((progress?.overallProgress ?? 0) * 100))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                Text("已完成")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // 处理时间
                ProcessingStatCard(
                    icon: "clock.fill",
                    title: "处理时间",
                    value: formatTime(progress?.currentTime ?? 0),
                    subtitle: "/ \(formatTime(progress?.totalDuration ?? 0))",
                    color: .blue
                )

                // 检测回合数
                ProcessingStatCard(
                    icon: "tennisball.fill",
                    title: "检测回合",
                    value: "\(progress?.detectedRalliesCount ?? 0)",
                    subtitle: "个回合",
                    color: .green
                )
            }

            // 当前段进度
            if let progress = progress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("当前处理段")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(progress.segmentProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    ProgressView(value: progress.segmentProgress)
                        .tint(.green)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Rally List Section

    private var rallyListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("实时检测到的回合")
                .font(.headline)

            LazyVStack(spacing: 8) {
                ForEach(detectedRallies) { rally in
                    RallyDetectionCard(rally: rally)
                }
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack(spacing: 16) {
            // 后台运行按钮
            Button {
                // 处理任务会继续在后台运行
                dismiss()
            } label: {
                Label("后台运行", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }

            // 取消按钮
            Button {
                isCancelled = true
                // 取消处理任务
                processingTask?.cancel()
                dismiss()
            } label: {
                Label("取消", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Processing

    private func startProcessing() {
        // 设置进度回调
        processingEngine.onProgressUpdate = { [self] progressUpdate in
            Task { @MainActor in
                self.progress = progressUpdate
            }
        }

        // 设置实时回合检测回调
        processingEngine.onRallyDetected = { [self] rally in
            Task { @MainActor in
                self.detectedRallies.append(rally)
            }
        }

        // 启动真实的处理任务
        processingTask = Task {
            do {
                _ = try await processingEngine.processVideo(video)

                // 处理完成
                await MainActor.run {
                    dismiss()
                }
            } catch {
                // 处理失败
                await MainActor.run {
                    print("处理失败: \(error.localizedDescription)")
                    dismiss()
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Processing Stat Card

struct ProcessingStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Rally Detection Card

struct RallyDetectionCard: View {
    let rally: VideoHighlight

    var body: some View {
        HStack(spacing: 12) {
            // 回合序号
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text("#\(rally.rallyNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(scoreColor)
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(rally.type)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(formatTime(rally.startTime)) - \(formatTime(rally.endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 精彩度评分
            VStack(spacing: 2) {
                Text("\(Int(rally.excitementScore))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(scoreColor)

                Text("精彩度")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var scoreColor: Color {
        if rally.excitementScore >= 80 {
            return .red
        } else if rally.excitementScore >= 60 {
            return .orange
        } else {
            return .green
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProcessingProgressView(
            video: Video(
                title: "网球比赛视频.mp4",
                originalFilePath: "test.mp4",
                duration: 300.0,
                width: 1920,
                height: 1080,
                fileSize: 1024 * 1024 * 100
            ),
            processingEngine: VideoProcessingEngine()
        )
    }
}
