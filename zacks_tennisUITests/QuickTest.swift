//
//  QuickTest.swift
//  zacks_tennisUITests
//
//  Quick test for real tennis video
//

import XCTest
import AVFoundation

@MainActor
final class QuickTest: XCTestCase {

    /// Quick test with the actual video
    func testRealTennisVideo() async throws {
        print("\n" + "="*60)
        print("🎾 网球视频回合检测算法 - 快速测试")
        print("="*60 + "\n")

        // Locate the video file
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let videoPath = projectRoot
            .appendingPathComponent("zacks_tennisTests")
            .appendingPathComponent("test_videos")
            .appendingPathComponent("10-26-2025-过滤后的对拉.MOV")

        guard FileManager.default.fileExists(atPath: videoPath.path) else {
            XCTFail("视频文件未找到: \(videoPath.path)")
            return
        }

        print("📹 视频文件: \(videoPath.lastPathComponent)")

        // Get video info
        let asset = AVAsset(url: videoPath)
        let duration = try await asset.load(.duration)
        let videoDuration = CMTimeGetSeconds(duration)

        print("   时长: \(String(format: "%.1f", videoDuration))秒 (\(String(format: "%.1f", videoDuration/60))分钟)")
        print("")

        // Create engine with default config
        print("⚙️  初始化检测引擎...")
        let config = ThresholdConfig()
        let engine = RallyDetectionEngine(config: config)
        print("   配置: 默认模式")
        print("   视频分析帧率: \(config.videoAnalysisFPS) fps")
        print("   运动强度阈值: \(config.movementIntensityThreshold)")
        print("   音频阈值: \(config.audioAmplitudeThreshold)")
        print("")

        // Run detection
        print("🚀 开始检测...")
        print("   预计处理时间: \(String(format: "%.1f", videoDuration * 0.5))秒 (根据30分钟<10分钟的目标估算)")
        print("")

        let startTime = Date()

        do {
            let result = try await engine.detectRallies(in: videoPath)
            let processingTime = Date().timeIntervalSince(startTime)

            print("\n" + "="*60)
            print("✅ 检测完成!")
            print("="*60 + "\n")

            print("📊 基本统计:")
            print("   总处理时间: \(String(format: "%.2f", processingTime))秒")
            print("   处理速率: \(String(format: "%.1f", videoDuration/processingTime))x 实时")
            print("   检测到回合数: \(result.totalRallies)")
            print("")

            if result.totalRallies > 0 {
                print("   平均回合时长: \(String(format: "%.1f", result.averageRallyDuration))秒")

                if let longest = result.longestRally {
                    print("   最长回合: \(String(format: "%.1f", longest.duration))秒 (位于 \(String(format: "%.1f", longest.startTime))s)")
                }

                if let topExciting = result.topExcitingRally {
                    print("   最精彩回合评分: \(String(format: "%.1f", topExciting.excitementScore))")
                }
                print("")

                // Print top 5 rallies
                print("🏆 前5个最精彩回合:")
                print("   " + "-"*58)
                print("   #  | 开始时间  | 结束时间  | 时长   | 评分  | 击球数")
                print("   " + "-"*58)

                for (index, rally) in result.topRallies(count: 5).enumerated() {
                    print(String(format: "   %-2d | %8.1fs | %8.1fs | %5.1fs | %5.1f | %3d",
                        index + 1,
                        rally.startTime,
                        rally.endTime,
                        rally.duration,
                        rally.excitementScore,
                        rally.hitCount
                    ))
                }
                print("   " + "-"*58)
                print("")

                // Generate full diagnostic report
                let report = engine.generateDiagnosticReport(result: result)
                print(report)

                // Generate scoring breakdown for top rally
                if let topRally = result.topExcitingRally {
                    print("\n📈 最精彩回合详细评分:")
                    print("-"*60)
                    let breakdown = engine.generateScoringBreakdown(for: topRally)
                    print(breakdown)
                }

                // Performance check
                print("\n✅ 性能验收:")
                let targetProcessingTime = (videoDuration / 1800.0) * 600.0  // 30min video in 10min
                let passPerformance = processingTime < targetProcessingTime
                print("   目标: \(String(format: "%.1f", videoDuration))秒视频 < \(String(format: "%.1f", targetProcessingTime))秒处理")
                print("   实际: \(String(format: "%.2f", processingTime))秒")
                print("   结果: \(passPerformance ? "✅ 通过" : "❌ 未通过")")

                // Generate ground truth template
                print("\n📝 生成标注数据模板...")
                let template = GroundTruthParser.generateTemplate(for: videoPath)

                let templatePath = videoPath.deletingPathExtension().appendingPathExtension("json").path
                print("   保存到: \(templatePath)")
                print("\n模板内容:")
                print("-"*60)
                print(template)
                print("-"*60)
                print("\n💡 提示: 请根据视频实际内容修改回合时间和评分")

            } else {
                print("⚠️  警告: 未检测到任何回合")
                print("\n可能原因:")
                print("   1. 视频质量较差")
                print("   2. 无音频轨道")
                print("   3. 阈值设置过高")
                print("\n建议调整:")
                print("   - 降低 movementIntensityThreshold (当前: \(config.movementIntensityThreshold))")
                print("   - 降低 audioAmplitudeThreshold (当前: \(config.audioAmplitudeThreshold))")
                print("   - 减小 minRallyDuration (当前: \(config.minRallyDuration)秒)")
            }

        } catch {
            print("\n❌ 检测失败:")
            print("   错误: \(error)")
            print("   详细: \(error.localizedDescription)")
            throw error
        }

        print("\n" + "="*60)
        print("测试完成")
        print("="*60 + "\n")
    }
}
