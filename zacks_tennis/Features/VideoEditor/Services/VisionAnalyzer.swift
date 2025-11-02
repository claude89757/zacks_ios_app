//
//  VisionAnalyzer.swift
//  zacks_tennis
//
//  Vision 框架集成 - 人体姿态检测和运动分析
//  使用 Apple Vision 框架检测网球运动员的姿态和动作
//

import Foundation
import Vision
import AVFoundation
import CoreImage

/// Vision 分析器 - 负责人体姿态检测和运动分析
actor VisionAnalyzer: FrameAnalyzing {

    // MARK: - Properties

    /// Vision 请求配置（可选，因为模拟器可能不支持）
    private let poseRequest: VNDetectHumanBodyPoseRequest?

    /// Vision 是否可用
    private let isVisionAvailable: Bool

    /// 上一帧的关键点（用于计算运动速度）
    private var previousKeyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]?

    /// 上一帧的时间戳
    private var previousTimestamp: Double = 0

    // MARK: - Initialization

    init() {
        #if targetEnvironment(simulator)
        // 模拟器上 Vision 姿态检测不可用（会导致 "Unable to setup request" 错误）
        // 直接禁用以避免错误日志
        print("⚠️ VisionAnalyzer: Running on Simulator - Vision pose detection disabled")
        print("   Human pose detection will be skipped (simulator limitation)")
        self.poseRequest = nil
        self.isVisionAvailable = false
        #else
        // 真机上正常初始化 Vision
        let request = VNDetectHumanBodyPoseRequest()

        // 检查支持的 revisions
        let supportedRevisions = VNDetectHumanBodyPoseRequest.supportedRevisions

        if supportedRevisions.contains(VNDetectHumanBodyPoseRequestRevision1) {
            request.revision = VNDetectHumanBodyPoseRequestRevision1
            print("✅ VisionAnalyzer: Successfully initialized with Revision1")
        } else {
            print("⚠️ VisionAnalyzer: Revision1 not supported, using default revision")
            print("   Supported revisions: \(supportedRevisions)")
        }

        self.poseRequest = request
        self.isVisionAvailable = true
        #endif
    }

    // MARK: - Public Methods

    /// 分析单帧图像，检测人体姿态
    /// - Parameters:
    ///   - pixelBuffer: 视频帧的像素缓冲区
    ///   - timestamp: 当前帧的时间戳
    /// - Returns: 帧分析结果
    func analyzeFrame(
        pixelBuffer: CVPixelBuffer,
        timestamp: Double
    ) async throws -> FrameAnalysisResult {

        // 检查 Vision 是否可用
        guard let poseRequest = poseRequest, isVisionAvailable else {
            // Vision 不可用（模拟器限制），使用模拟数据以便开发测试
            return generateMockFrameResult(timestamp: timestamp)
        }

        // 创建图像请求处理器
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        // 执行姿态检测
        try handler.perform([poseRequest])

        // 处理检测结果
        guard let observations = poseRequest.results,
              let observation = observations.first else {
            // 未检测到人体
            return FrameAnalysisResult(
                hasPerson: false,
                confidence: 0.0,
                movementIntensity: 0.0,
                keyPoints: nil,
                timestamp: timestamp
            )
        }

        // 提取关键点
        let keyPoints = try extractKeyPoints(from: observation)

        // 计算运动强度
        let movementIntensity = calculateMovementIntensity(
            currentKeyPoints: keyPoints,
            previousKeyPoints: previousKeyPoints,
            timeDelta: timestamp - previousTimestamp
        )

        // 更新上一帧数据
        previousKeyPoints = keyPoints
        previousTimestamp = timestamp

        // 计算整体置信度
        let confidence = observation.confidence

        // 转换 keyPoints 类型：VNHumanBodyPoseObservation.JointName -> String
        let keyPointsDict = convertKeyPointsToDict(keyPoints)

        return FrameAnalysisResult(
            hasPerson: true,
            confidence: Double(confidence),
            movementIntensity: movementIntensity,
            keyPoints: keyPointsDict,
            timestamp: timestamp
        )
    }

    /// 批量分析多帧图像
    /// - Parameter frames: 帧数据数组（像素缓冲区和时间戳）
    /// - Returns: 分析结果数组
    func analyzeFrames(
        _ frames: [(pixelBuffer: CVPixelBuffer, timestamp: Double)]
    ) async throws -> [FrameAnalysisResult] {
        var results: [FrameAnalysisResult] = []

        for frame in frames {
            let result = try await analyzeFrame(
                pixelBuffer: frame.pixelBuffer,
                timestamp: frame.timestamp
            )
            results.append(result)
        }

        return results
    }

    /// 重置分析器状态（用于处理新视频）
    func reset() {
        previousKeyPoints = nil
        previousTimestamp = 0
    }

    // MARK: - Private Methods - Key Point Extraction

    /// 从观察结果中提取关键点
    private func extractKeyPoints(
        from observation: VNHumanBodyPoseObservation
    ) throws -> [VNHumanBodyPoseObservation.JointName: CGPoint] {

        var keyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

        // 定义我们关心的关键点（网球运动主要涉及上半身）
        let relevantJoints: [VNHumanBodyPoseObservation.JointName] = [
            // 躯干
            .neck,
            .root,

            // 左臂
            .leftShoulder,
            .leftElbow,
            .leftWrist,

            // 右臂
            .rightShoulder,
            .rightElbow,
            .rightWrist,

            // 腿部（用于判断移动和重心）
            .leftHip,
            .rightHip,
            .leftKnee,
            .rightKnee,
            .leftAnkle,
            .rightAnkle
        ]

        // 提取每个关键点的位置
        for joint in relevantJoints {
            if let recognizedPoint = try? observation.recognizedPoint(joint),
               recognizedPoint.confidence > 0.3 { // 置信度阈值
                keyPoints[joint] = recognizedPoint.location
            }
        }

        return keyPoints
    }

    // MARK: - Private Methods - Movement Analysis

    /// 计算运动强度
    /// - Parameters:
    ///   - currentKeyPoints: 当前帧关键点
    ///   - previousKeyPoints: 上一帧关键点
    ///   - timeDelta: 时间差（秒）
    /// - Returns: 运动强度（0-1）
    private func calculateMovementIntensity(
        currentKeyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint],
        previousKeyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]?,
        timeDelta: Double
    ) -> Double {

        guard let previousKeyPoints = previousKeyPoints,
              timeDelta > 0 else {
            return 0.0
        }

        // 计算主要关键点的移动距离
        var totalMovement: Double = 0
        var validPointCount: Int = 0

        // 优先权重：手腕 > 肘 > 肩（网球运动手臂动作最重要）
        let jointWeights: [VNHumanBodyPoseObservation.JointName: Double] = [
            .leftWrist: 2.0,
            .rightWrist: 2.0,
            .leftElbow: 1.5,
            .rightElbow: 1.5,
            .leftShoulder: 1.0,
            .rightShoulder: 1.0,
            .neck: 0.8,
            .root: 0.5
        ]

        for (joint, currentPoint) in currentKeyPoints {
            guard let previousPoint = previousKeyPoints[joint],
                  let weight = jointWeights[joint] else {
                continue
            }

            // 计算欧几里得距离
            let dx = currentPoint.x - previousPoint.x
            let dy = currentPoint.y - previousPoint.y
            let distance = sqrt(dx * dx + dy * dy)

            // 加权累加
            totalMovement += distance * weight
            validPointCount += 1
        }

        guard validPointCount > 0 else {
            return 0.0
        }

        // 平均运动距离
        let avgMovement = totalMovement / Double(validPointCount)

        // 计算速度（距离/时间）
        let velocity = avgMovement / timeDelta

        // 归一化到 0-1 范围
        // 网球挥拍速度约为 0.1-0.3 屏幕宽度/秒（经验值）
        // 这里使用 sigmoid 函数进行平滑归一化
        let normalizedIntensity = sigmoid(velocity * 5.0)

        return min(1.0, normalizedIntensity)
    }

    /// 检测特定的网球动作类型
    /// - Parameter keyPoints: 关键点字典
    /// - Returns: 动作类型（serve, forehand, backhand, none）
    private func detectTennisAction(
        keyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> String? {

        // TODO: 实现具体的动作识别算法
        // 当前版本返回 nil，后续可以基于关键点位置和角度判断
        // 例如：
        // - 发球：手臂高举，肘部高于肩部
        // - 正手：右手（或左手）向前挥拍，肩部旋转
        // - 反手：双手握拍或单手反手，肩部反向旋转

        guard let leftWrist = keyPoints[.leftWrist],
              let rightWrist = keyPoints[.rightWrist],
              let leftShoulder = keyPoints[.leftShoulder],
              let rightShoulder = keyPoints[.rightShoulder] else {
            return nil
        }

        // 简单的发球检测：任一手腕高于对应肩膀
        if leftWrist.y > leftShoulder.y || rightWrist.y > rightShoulder.y {
            return "serve"
        }

        // 其他动作识别可以后续扩展
        return nil
    }

    // MARK: - Mock Data Generation (for Simulator)

    /// 生成模拟的帧分析结果（用于模拟器测试）
    /// - Parameter timestamp: 时间戳
    /// - Returns: 模拟的帧分析结果
    private func generateMockFrameResult(timestamp: Double) -> FrameAnalysisResult {
        // 使用时间戳生成周期性的模拟数据，模拟真实的网球比赛场景

        // 将时间分为不同的阶段来模拟回合
        let cycleLength: Double = 30.0 // 每30秒一个完整周期
        let timeInCycle = timestamp.truncatingRemainder(dividingBy: cycleLength)

        // 模拟场景：
        // 0-5秒: 静止/准备 (低强度)
        // 5-15秒: 激烈回合 (高强度)
        // 15-20秒: 中等回合 (中强度)
        // 20-25秒: 激烈回合 (高强度)
        // 25-30秒: 静止/准备 (低强度)

        let hasPerson: Bool
        let movementIntensity: Double
        let confidence: Double

        if timeInCycle < 5 {
            // 准备阶段
            hasPerson = true
            movementIntensity = Double.random(in: 0.05...0.15)
            confidence = 0.85
        } else if timeInCycle < 15 {
            // 激烈回合1
            hasPerson = true
            movementIntensity = Double.random(in: 0.6...0.9)
            confidence = 0.9
        } else if timeInCycle < 20 {
            // 中等回合
            hasPerson = true
            movementIntensity = Double.random(in: 0.3...0.5)
            confidence = 0.85
        } else if timeInCycle < 25 {
            // 激烈回合2
            hasPerson = true
            movementIntensity = Double.random(in: 0.65...0.95)
            confidence = 0.92
        } else {
            // 准备阶段
            hasPerson = true
            movementIntensity = Double.random(in: 0.05...0.2)
            confidence = 0.8
        }

        // 生成模拟的关键点数据（可选）
        let mockKeyPoints: [String: CGPoint]? = hasPerson ? [
            "leftWrist": CGPoint(x: 0.3 + Double.random(in: -0.1...0.1),
                               y: 0.5 + Double.random(in: -0.1...0.1)),
            "rightWrist": CGPoint(x: 0.7 + Double.random(in: -0.1...0.1),
                                y: 0.5 + Double.random(in: -0.1...0.1)),
            "leftShoulder": CGPoint(x: 0.35, y: 0.3),
            "rightShoulder": CGPoint(x: 0.65, y: 0.3)
        ] : nil

        return FrameAnalysisResult(
            hasPerson: hasPerson,
            confidence: confidence,
            movementIntensity: movementIntensity,
            keyPoints: mockKeyPoints,
            timestamp: timestamp
        )
    }

    // MARK: - Helper Methods

    /// 转换关键点字典类型（VNHumanBodyPoseObservation.JointName -> String）
    private func convertKeyPointsToDict(
        _ keyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        for (joint, point) in keyPoints {
            // 将 JointName 转换为字符串表示
            let jointString = "\(joint.rawValue)"
            result[jointString] = point
        }
        return result
    }

    /// Sigmoid 函数（用于平滑归一化）
    private func sigmoid(_ x: Double) -> Double {
        return 1.0 / (1.0 + exp(-x))
    }

    /// 计算两点之间的距离
    private func distance(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 计算三点形成的角度（用于姿态分析）
    /// - Parameters:
    ///   - point1: 第一个点
    ///   - vertex: 顶点
    ///   - point2: 第二个点
    /// - Returns: 角度（弧度）
    private func angle(
        from point1: CGPoint,
        vertex: CGPoint,
        to point2: CGPoint
    ) -> Double {
        let vector1 = CGPoint(x: point1.x - vertex.x, y: point1.y - vertex.y)
        let vector2 = CGPoint(x: point2.x - vertex.x, y: point2.y - vertex.y)

        let dotProduct = vector1.x * vector2.x + vector1.y * vector2.y
        let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
        let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)

        let cosAngle = dotProduct / (magnitude1 * magnitude2)
        return acos(max(-1.0, min(1.0, cosAngle)))
    }
}

// MARK: - Supporting Types

/// Vision 分析配置
struct VisionAnalyzerConfiguration {
    /// 最小置信度阈值
    let minimumConfidence: Float = 0.3

    /// 关键点检测置信度阈值
    let keyPointConfidenceThreshold: Float = 0.3

    /// 运动强度归一化系数
    let intensityNormalizationFactor: Double = 5.0
}

/// Vision 分析错误
enum VisionAnalyzerError: LocalizedError {
    case noPoseDetected
    case lowConfidence
    case invalidFrame
    case permissionDenied
    case visionNotAvailable

    var errorDescription: String? {
        switch self {
        case .noPoseDetected:
            return "未检测到人体姿态"
        case .lowConfidence:
            return "检测置信度过低"
        case .invalidFrame:
            return "无效的视频帧"
        case .permissionDenied:
            return "缺少相机或照片库权限，请在设置中允许访问"
        case .visionNotAvailable:
            return "Vision 框架不可用，请检查设备兼容性"
        }
    }
}
