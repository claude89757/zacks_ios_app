//
//  DebugConfiguration.swift
//  zacks_tennis
//
//  调试配置模型 - 用于视频处理算法的调试和参数调优
//

import Foundation
import SwiftUI

// MARK: - 调试配置

/// 视频处理调试配置
@Observable
class DebugConfiguration {

    // MARK: - 调试模式开关

    /// 是否启用调试模式
    var isDebugEnabled: Bool = false {
        didSet {
            if isDebugEnabled {
                print("🐛 调试模式已启用")
            } else {
                print("✅ 调试模式已关闭")
            }
        }
    }

    /// 是否显示可视化标注
    var showVisualAnnotations: Bool = true

    /// 是否导出带标注的调试视频
    var exportAnnotatedVideo: Bool = false

    /// 是否仅记录数据（不绘制标注，提升性能）
    var dataOnlyMode: Bool = false

    // MARK: - 网球追踪参数

    /// 网球最小半径（归一化，0-1）
    var ballMinRadius: Double = 0.005 {
        didSet { clampBallMinRadius() }
    }

    /// 网球最大半径（归一化，0-1）
    var ballMaxRadius: Double = 0.04 {
        didSet { clampBallMaxRadius() }
    }

    /// 网球速度阈值（判断移动）
    var ballVelocityThreshold: Double = 0.05 {
        didSet {
            ballVelocityThreshold = max(0.01, min(0.5, ballVelocityThreshold))
        }
    }

    /// 网球检测置信度阈值
    var ballConfidenceThreshold: Double = 0.5 {
        didSet {
            ballConfidenceThreshold = max(0.0, min(1.0, ballConfidenceThreshold))
        }
    }

    /// 轨迹追踪长度（帧数）
    var trajectoryLength: Int = 15 {
        didSet {
            trajectoryLength = max(5, min(30, trajectoryLength))
        }
    }

    // MARK: - 回合检测参数

    /// 最小回合时长（秒）
    var minRallyDuration: Double = 1.5 {
        didSet {
            minRallyDuration = max(0.5, min(10.0, minRallyDuration))
        }
    }

    /// 最大暂停时长（秒）
    var maxPauseDuration: Double = 2.0 {
        didSet {
            maxPauseDuration = max(0.5, min(5.0, maxPauseDuration))
        }
    }

    /// 运动强度阈值（用于回合判断）
    var movementIntensityThreshold: Double = 0.4 {
        didSet {
            movementIntensityThreshold = max(0.1, min(0.9, movementIntensityThreshold))
        }
    }

    // MARK: - 音频分析参数

    /// 音频峰值阈值
    var audioPeakThreshold: Double = 0.4 {
        didSet {
            audioPeakThreshold = max(0.1, min(0.9, audioPeakThreshold))
        }
    }

    /// 音频最小置信度
    var audioMinConfidence: Double = 0.5 {
        didSet {
            audioMinConfidence = max(0.0, min(1.0, audioMinConfidence))
        }
    }

    /// 音频峰值最小间隔（秒）
    var audioMinPeakInterval: Double = 0.2 {
        didSet {
            audioMinPeakInterval = max(0.05, min(1.0, audioMinPeakInterval))
        }
    }

    // MARK: - 采样参数

    /// 帧采样间隔（秒）
    var frameSamplingInterval: Double = 0.1 {
        didSet {
            frameSamplingInterval = max(0.05, min(1.0, frameSamplingInterval))
        }
    }

    /// 计算的采样率（FPS）
    var samplingRate: Double {
        return 1.0 / frameSamplingInterval
    }

    // MARK: - 可视化配置

    /// 是否显示边界框
    var showBoundingBox: Bool = true

    /// 是否显示中心点
    var showCenterDot: Bool = true

    /// 是否显示轨迹线
    var showTrajectory: Bool = true

    /// 是否显示速度箭头
    var showVelocityArrow: Bool = true

    /// 是否显示置信度标签
    var showConfidence: Bool = true

    /// 是否显示时间戳
    var showTimestamp: Bool = true

    /// 是否显示统计信息
    var showStatistics: Bool = true

    // MARK: - 预设配置

    /// 当前使用的预设名称
    var currentPresetName: String = "平衡"

    // MARK: - Initialization

    init() {
        // 默认使用平衡模式
        applyPreset(.balanced)
    }

    // MARK: - 参数验证

    private func clampBallMinRadius() {
        ballMinRadius = max(0.001, min(0.1, ballMinRadius))
        if ballMinRadius >= ballMaxRadius {
            ballMinRadius = ballMaxRadius - 0.001
        }
    }

    private func clampBallMaxRadius() {
        ballMaxRadius = max(0.01, min(0.2, ballMaxRadius))
        if ballMaxRadius <= ballMinRadius {
            ballMaxRadius = ballMinRadius + 0.001
        }
    }

    // MARK: - 预设管理

    enum Preset {
        case strict       // 严格模式 - 高精度，低误报
        case balanced     // 平衡模式 - 平衡精度和召回率
        case lenient      // 宽松模式 - 高召回率，可能误报
        case custom       // 自定义

        var displayName: String {
            switch self {
            case .strict: return "严格"
            case .balanced: return "平衡"
            case .lenient: return "宽松"
            case .custom: return "自定义"
            }
        }
    }

    /// 应用预设配置
    func applyPreset(_ preset: Preset) {
        currentPresetName = preset.displayName

        switch preset {
        case .strict:
            // 严格模式：减少误报
            ballMinRadius = 0.008
            ballMaxRadius = 0.03
            ballVelocityThreshold = 0.08
            ballConfidenceThreshold = 0.65
            trajectoryLength = 20

            minRallyDuration = 2.5
            maxPauseDuration = 1.5
            movementIntensityThreshold = 0.5

            audioPeakThreshold = 0.6
            audioMinConfidence = 0.7
            audioMinPeakInterval = 0.3

            frameSamplingInterval = 0.1  // 10 fps

        case .balanced:
            // 平衡模式：默认配置
            ballMinRadius = 0.005
            ballMaxRadius = 0.04
            ballVelocityThreshold = 0.05
            ballConfidenceThreshold = 0.5
            trajectoryLength = 15

            minRallyDuration = 1.5
            maxPauseDuration = 2.0
            movementIntensityThreshold = 0.4

            audioPeakThreshold = 0.4
            audioMinConfidence = 0.5
            audioMinPeakInterval = 0.2

            frameSamplingInterval = 0.1  // 10 fps

        case .lenient:
            // 宽松模式：增加召回率
            ballMinRadius = 0.003
            ballMaxRadius = 0.05
            ballVelocityThreshold = 0.03
            ballConfidenceThreshold = 0.4
            trajectoryLength = 10

            minRallyDuration = 1.0
            maxPauseDuration = 2.5
            movementIntensityThreshold = 0.3

            audioPeakThreshold = 0.3
            audioMinConfidence = 0.4
            audioMinPeakInterval = 0.15

            frameSamplingInterval = 0.1  // 10 fps

        case .custom:
            // 保持当前自定义配置
            currentPresetName = "自定义"
        }

        print("📋 已应用预设：\(currentPresetName)")
    }

    // MARK: - 配置导出/导入

    /// 导出当前配置为 JSON
    func exportToJSON() -> String? {
        let config: [String: Any] = [
            "preset": currentPresetName,
            "ball_tracking": [
                "min_radius": ballMinRadius,
                "max_radius": ballMaxRadius,
                "velocity_threshold": ballVelocityThreshold,
                "confidence_threshold": ballConfidenceThreshold,
                "trajectory_length": trajectoryLength
            ],
            "rally_detection": [
                "min_duration": minRallyDuration,
                "max_pause": maxPauseDuration,
                "movement_threshold": movementIntensityThreshold
            ],
            "audio_analysis": [
                "peak_threshold": audioPeakThreshold,
                "min_confidence": audioMinConfidence,
                "min_interval": audioMinPeakInterval
            ],
            "sampling": [
                "frame_interval": frameSamplingInterval,
                "sampling_rate": samplingRate
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return jsonString
    }

    /// 从 JSON 导入配置
    func importFromJSON(_ jsonString: String) -> Bool {
        guard let jsonData = jsonString.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return false
        }

        // 解析配置
        if let ballConfig = config["ball_tracking"] as? [String: Any] {
            ballMinRadius = ballConfig["min_radius"] as? Double ?? ballMinRadius
            ballMaxRadius = ballConfig["max_radius"] as? Double ?? ballMaxRadius
            ballVelocityThreshold = ballConfig["velocity_threshold"] as? Double ?? ballVelocityThreshold
            ballConfidenceThreshold = ballConfig["confidence_threshold"] as? Double ?? ballConfidenceThreshold
            trajectoryLength = ballConfig["trajectory_length"] as? Int ?? trajectoryLength
        }

        if let rallyConfig = config["rally_detection"] as? [String: Any] {
            minRallyDuration = rallyConfig["min_duration"] as? Double ?? minRallyDuration
            maxPauseDuration = rallyConfig["max_pause"] as? Double ?? maxPauseDuration
            movementIntensityThreshold = rallyConfig["movement_threshold"] as? Double ?? movementIntensityThreshold
        }

        if let audioConfig = config["audio_analysis"] as? [String: Any] {
            audioPeakThreshold = audioConfig["peak_threshold"] as? Double ?? audioPeakThreshold
            audioMinConfidence = audioConfig["min_confidence"] as? Double ?? audioMinConfidence
            audioMinPeakInterval = audioConfig["min_interval"] as? Double ?? audioMinPeakInterval
        }

        if let samplingConfig = config["sampling"] as? [String: Any] {
            frameSamplingInterval = samplingConfig["frame_interval"] as? Double ?? frameSamplingInterval
        }

        currentPresetName = "自定义"
        print("✅ 配置导入成功")
        return true
    }

    // MARK: - 重置

    /// 重置为默认配置
    func reset() {
        applyPreset(.balanced)
    }

    // MARK: - 调试信息

    /// 获取当前配置的调试描述
    func debugDescription() -> String {
        return """
        ====== 调试配置 ======
        预设: \(currentPresetName)
        调试模式: \(isDebugEnabled ? "启用" : "禁用")

        [网球追踪]
        - 半径范围: \(String(format: "%.3f", ballMinRadius)) - \(String(format: "%.3f", ballMaxRadius))
        - 速度阈值: \(String(format: "%.2f", ballVelocityThreshold))
        - 置信度阈值: \(String(format: "%.2f", ballConfidenceThreshold))
        - 轨迹长度: \(trajectoryLength) 帧

        [回合检测]
        - 最小时长: \(String(format: "%.1f", minRallyDuration)) 秒
        - 最大暂停: \(String(format: "%.1f", maxPauseDuration)) 秒
        - 运动阈值: \(String(format: "%.2f", movementIntensityThreshold))

        [音频分析]
        - 峰值阈值: \(String(format: "%.2f", audioPeakThreshold))
        - 最小置信度: \(String(format: "%.2f", audioMinConfidence))
        - 峰值间隔: \(String(format: "%.2f", audioMinPeakInterval)) 秒

        [采样配置]
        - 采样间隔: \(String(format: "%.2f", frameSamplingInterval)) 秒
        - 采样率: \(String(format: "%.1f", samplingRate)) FPS
        =====================
        """
    }

    /// 打印调试信息
    func printDebugInfo() {
        print(debugDescription())
    }
}

// MARK: - 预设视图助手

extension DebugConfiguration {
    /// 获取所有预设选项
    static var allPresets: [Preset] {
        return [.strict, .balanced, .lenient]
    }
}
