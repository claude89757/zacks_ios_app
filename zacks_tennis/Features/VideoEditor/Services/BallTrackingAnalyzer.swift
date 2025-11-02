//
//  BallTrackingAnalyzer.swift
//  zacks_tennis
//
//  网球追踪分析器 - 使用 Vision 框架检测和追踪网球移动
//  核心原理：网球在打回合时一定会移动，休息时静止或不在视野
//

import Foundation
import Vision
import CoreImage
import AVFoundation
import CoreMedia
import UIKit

// MARK: - 网球检测数据结构

/// 单次网球检测结果
struct BallDetection: Sendable {
    let boundingBox: CGRect      // 网球位置框（归一化坐标 0-1）
    let center: CGPoint          // 中心坐标（归一化）
    let velocity: CGVector       // 移动速度（归一化单位/秒）
    let confidence: Double       // 检测置信度 (0-1)
    let timestamp: Double        // 时间戳（秒）
    let trajectory: [CGPoint]?   // 历史轨迹点（最近15帧，归一化坐标）

    /// 计算网球移动距离（归一化单位）
    var movementMagnitude: Double {
        return sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
    }

    /// 判断网球是否在快速移动
    func isMoving(threshold: Double = 0.05) -> Bool {
        return movementMagnitude > threshold
    }
}

/// 帧级别的网球分析结果
struct BallAnalysisResult: Sendable {
    let timestamp: Double
    let detections: [BallDetection]  // 可能检测到多个网球
    let primaryBall: BallDetection?  // 主要网球（最高置信度/最快速度）
    let hasBall: Bool               // 是否检测到网球
    let averageConfidence: Double   // 平均置信度

    init(timestamp: Double, detections: [BallDetection]) {
        self.timestamp = timestamp
        self.detections = detections
        self.hasBall = !detections.isEmpty
        self.averageConfidence = detections.isEmpty ? 0.0 : detections.map(\.confidence).reduce(0, +) / Double(detections.count)

        // 选择主要网球：优先选择移动最快的，其次置信度最高的
        self.primaryBall = detections.max { a, b in
            let aScore = a.movementMagnitude * 0.7 + a.confidence * 0.3
            let bScore = b.movementMagnitude * 0.7 + b.confidence * 0.3
            return aScore < bScore
        }
    }
}

// MARK: - 网球追踪配置

/// 网球检测参数配置
struct BallTrackingConfiguration: Sendable {
    // Vision 轨迹检测参数
    var trajectoryLength: Int = 15                    // 追踪历史帧数
    var objectMinNormalizedRadius: Float = 0.005      // 网球最小半径（归一化）
    var objectMaxNormalizedRadius: Float = 0.04       // 网球最大半径（归一化）

    // 颜色过滤参数（HSV空间）
    var enableColorFiltering: Bool = true             // 是否启用颜色过滤
    var hueRangeLower: Float = 20.0                   // 黄绿色范围下限（度）
    var hueRangeUpper: Float = 70.0                   // 黄绿色范围上限（度）
    var saturationMin: Float = 0.3                    // 最小饱和度
    var brightnessMin: Float = 0.4                    // 最小亮度

    // 运动检测参数
    var velocityThreshold: Double = 0.05              // 最小速度阈值（判断移动）
    var confidenceThreshold: Double = 0.5             // 最小置信度阈值

    // 性能优化参数
    var maxDetectionsPerFrame: Int = 3                // 每帧最多检测网球数
    var enableGPUAcceleration: Bool = true            // 启用GPU加速

    /// 预设配置
    static let `default` = BallTrackingConfiguration()

    static let strict = BallTrackingConfiguration(
        trajectoryLength: 20,
        objectMinNormalizedRadius: 0.008,
        objectMaxNormalizedRadius: 0.03,
        velocityThreshold: 0.08,
        confidenceThreshold: 0.65
    )

    static let lenient = BallTrackingConfiguration(
        trajectoryLength: 10,
        objectMinNormalizedRadius: 0.003,
        objectMaxNormalizedRadius: 0.05,
        velocityThreshold: 0.03,
        confidenceThreshold: 0.4
    )
}

// MARK: - 网球追踪分析器

/// 网球追踪分析器 - 基于 Vision 框架的轨迹检测
actor BallTrackingAnalyzer: BallTracking {

    // MARK: - Properties

    private let configuration: BallTrackingConfiguration
    private var trajectoryRequest: VNDetectTrajectoriesRequest?
    private var isVisionAvailable: Bool = true

    // 历史轨迹缓存（用于平滑和速度计算）
    private var trajectoryCache: [UUID: [TrajectoryPoint]] = [:]
    private struct TrajectoryPoint {
        let position: CGPoint
        let timestamp: Double
    }

    // 性能统计
    private var totalFramesProcessed: Int = 0
    private var totalDetections: Int = 0

    // MARK: - Initialization

    init(configuration: BallTrackingConfiguration = BallTrackingConfiguration()) {
        self.configuration = configuration

        let setup = Self.makeTrajectoryRequest(configuration: configuration)
        self.trajectoryRequest = setup.request
        self.isVisionAvailable = setup.isAvailable
    }

    /// 生成 Vision 轨迹检测请求（在初始化阶段使用，避免访问 actor 隔离的 self）
    private nonisolated static func makeTrajectoryRequest(
        configuration: BallTrackingConfiguration
    ) -> (request: VNDetectTrajectoriesRequest?, isAvailable: Bool) {
        #if targetEnvironment(simulator)
        // 模拟器可能不支持某些 Vision 功能
        print("⚠️ BallTrackingAnalyzer: Running on simulator, some features may be limited")
        return (nil, false)
        #else
        guard #available(iOS 14.0, *) else {
            print("⚠️ BallTrackingAnalyzer: iOS 14.0+ required for trajectory detection")
            return (nil, false)
        }

        let spacing = CMTime(value: 1, timescale: 10) // 每 0.1 秒分析一次，即 10fps

        do {
            let request = try VNDetectTrajectoriesRequest(
                frameAnalysisSpacing: spacing,
                trajectoryLength: configuration.trajectoryLength
            )

            // 设置对象大小范围（过滤噪音）
            request.objectMinimumNormalizedRadius = configuration.objectMinNormalizedRadius
            request.objectMaximumNormalizedRadius = configuration.objectMaxNormalizedRadius

            // iOS 15+ 可设置目标帧时间
            if #available(iOS 15.0, *) {
                request.targetFrameTime = CMTime(value: 1, timescale: 30) // 30fps
            }

            print("✅ BallTrackingAnalyzer: Vision trajectory detection initialized")
            return (request, true)
        } catch {
            print("❌ BallTrackingAnalyzer: failed to create trajectory request – \(error)")
            return (nil, false)
        }
        #endif
    }

    // MARK: - Public API

    /// 分析单帧图像，检测网球
    func analyze(pixelBuffer: CVPixelBuffer, timestamp: Double) async -> BallAnalysisResult {
        totalFramesProcessed += 1

        // 如果 Vision 不可用，使用降级方案
        guard isVisionAvailable, let request = trajectoryRequest else {
            return await fallbackAnalysis(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }

        // 执行 Vision 轨迹检测
        let detections = await performVisionDetection(pixelBuffer: pixelBuffer, timestamp: timestamp, request: request)

        totalDetections += detections.count

        return BallAnalysisResult(timestamp: timestamp, detections: detections)
    }

    /// 批量分析多帧（优化性能）
    func analyzeBatch(frames: [(CVPixelBuffer, Double)]) async -> [BallAnalysisResult] {
        var results: [BallAnalysisResult] = []

        for (pixelBuffer, timestamp) in frames {
            let result = await analyze(pixelBuffer: pixelBuffer, timestamp: timestamp)
            results.append(result)
        }

        return results
    }

    /// 获取性能统计信息
    func getStatistics() async -> (framesProcessed: Int, totalDetections: Int, avgDetectionsPerFrame: Double) {
        let avg = totalFramesProcessed > 0 ? Double(totalDetections) / Double(totalFramesProcessed) : 0.0
        return (totalFramesProcessed, totalDetections, avg)
    }

    /// 重置统计信息
    func resetStatistics() {
        totalFramesProcessed = 0
        totalDetections = 0
        trajectoryCache.removeAll()
    }

    // MARK: - Vision Detection

    /// 执行 Vision 轨迹检测
    private func performVisionDetection(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        request: VNDetectTrajectoriesRequest
    ) async -> [BallDetection] {

        return await withCheckedContinuation { continuation in
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )

            do {
                try handler.perform([request])

                guard let observations = request.results as? [VNTrajectoryObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // 转换 Vision 结果为 BallDetection
                let detections = observations.compactMap { observation -> BallDetection? in
                    return self.convertObservationToDetection(observation, timestamp: timestamp)
                }.prefix(configuration.maxDetectionsPerFrame).map { $0 }

                continuation.resume(returning: detections)

            } catch {
                print("❌ Vision detection error: \(error)")
                continuation.resume(returning: [])
            }
        }
    }

    /// 将 Vision 观测结果转换为 BallDetection
    private func convertObservationToDetection(
        _ observation: VNTrajectoryObservation,
        timestamp: Double
    ) -> BallDetection? {

        // 获取轨迹点（detectedPoints 是数组，不是可选）
        let detectedPoints = observation.detectedPoints
        guard let lastPoint = detectedPoints.last else {
            return nil
        }

        // 计算边界框（假设网球半径）
        let radius = CGFloat(configuration.objectMinNormalizedRadius + configuration.objectMaxNormalizedRadius) / 2
        let center = CGPoint(x: lastPoint.x, y: lastPoint.y)
        let boundingBox = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        // 计算速度（基于轨迹）
        let velocity = calculateVelocity(from: detectedPoints, timestamp: timestamp)

        // 提取轨迹点（归一化坐标）
        let trajectoryPoints = detectedPoints.map { CGPoint(x: $0.x, y: $0.y) }

        // 计算置信度（基于轨迹连续性和长度）
        let confidence = calculateConfidence(detectedPoints: detectedPoints, velocity: velocity.magnitude)

        // 过滤低置信度检测
        guard confidence >= configuration.confidenceThreshold else {
            return nil
        }

        return BallDetection(
            boundingBox: boundingBox,
            center: center,
            velocity: velocity.vector,
            confidence: confidence,
            timestamp: timestamp,
            trajectory: trajectoryPoints
        )
    }

    /// 计算速度向量
    private func calculateVelocity(
        from points: [VNPoint],
        timestamp: Double
    ) -> (vector: CGVector, magnitude: Double) {

        guard points.count >= 2 else {
            return (CGVector.zero, 0.0)
        }

        // 使用最近的几个点计算平均速度（更平滑）
        let recentPoints = points.suffix(min(5, points.count))
        guard let first = recentPoints.first, let last = recentPoints.last else {
            return (CGVector.zero, 0.0)
        }

        let dx = last.x - first.x
        let dy = last.y - first.y

        // 假设轨迹长度对应的时间（基于配置的轨迹长度和采样率）
        let timeSpan = Double(recentPoints.count) * 0.1  // 假设每帧0.1秒

        let vx = dx / timeSpan
        let vy = dy / timeSpan

        let magnitude = sqrt(vx * vx + vy * vy)

        return (CGVector(dx: vx, dy: vy), magnitude)
    }

    /// 计算检测置信度
    private func calculateConfidence(detectedPoints: [VNPoint], velocity: Double) -> Double {
        // 基于多个因素计算置信度

        // 1. 轨迹长度（更长的轨迹更可信）- 30%
        let lengthScore = min(Double(detectedPoints.count) / Double(configuration.trajectoryLength), 1.0)

        // 2. 运动平滑性（轨迹越平滑越可信）- 30%
        let smoothnessScore = calculateSmoothness(points: detectedPoints)

        // 3. 速度合理性（网球速度通常在特定范围）- 20%
        let velocityScore: Double
        if velocity < 0.01 {
            velocityScore = 0.3  // 几乎静止，可能不是打球
        } else if velocity > 0.5 {
            velocityScore = 0.7  // 速度过快，可能是误检
        } else {
            velocityScore = 1.0  // 合理范围
        }

        // 4. 基础置信度 - 20%
        let baseConfidence = 0.8

        let totalConfidence = lengthScore * 0.3 +
                            smoothnessScore * 0.3 +
                            velocityScore * 0.2 +
                            baseConfidence * 0.2

        return min(max(totalConfidence, 0.0), 1.0)
    }

    /// 计算轨迹平滑度（基于方向变化）
    private func calculateSmoothness(points: [VNPoint]) -> Double {
        guard points.count >= 3 else { return 1.0 }

        var totalAngleChange: Double = 0.0

        for i in 1..<(points.count - 1) {
            let p1 = points[i - 1]
            let p2 = points[i]
            let p3 = points[i + 1]

            let v1 = CGVector(dx: p2.x - p1.x, dy: p2.y - p1.y)
            let v2 = CGVector(dx: p3.x - p2.x, dy: p3.y - p2.y)

            let angle = abs(angleBetween(v1, v2))
            totalAngleChange += angle
        }

        let avgAngleChange = totalAngleChange / Double(points.count - 2)

        // 角度变化越小越平滑（转换为0-1分数）
        // 假设平均角度变化 < 30度为平滑
        let smoothness = max(0.0, 1.0 - avgAngleChange / (Double.pi / 6))

        return smoothness
    }

    /// 计算两个向量之间的角度
    private func angleBetween(_ v1: CGVector, _ v2: CGVector) -> Double {
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let mag2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)

        guard mag1 > 0, mag2 > 0 else { return 0.0 }

        let cosAngle = dot / (mag1 * mag2)
        return acos(min(max(cosAngle, -1.0), 1.0))
    }

    // MARK: - Fallback Analysis

    /// 降级方案：基于颜色和形状的简单检测
    private func fallbackAnalysis(pixelBuffer: CVPixelBuffer, timestamp: Double) async -> BallAnalysisResult {
        // 模拟器或 Vision 不可用时的简单实现
        // TODO: 实现基于颜色过滤的检测（可选）

        // 目前返回空结果
        return BallAnalysisResult(timestamp: timestamp, detections: [])
    }
}

// MARK: - Helper Extensions

extension CGVector {
    var magnitude: Double {
        return sqrt(dx * dx + dy * dy)
    }
}
