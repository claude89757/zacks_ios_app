//
//  BallVisualizationEngine.swift
//  zacks_tennis
//
//  网球可视化引擎 - 在视频帧上绘制网球检测结果，方便调试和调优
//

import Foundation
import CoreImage
import CoreGraphics
import UIKit
import AVFoundation

// MARK: - 可视化配置

/// 可视化样式配置
struct VisualizationStyle: Sendable {
    // 颜色配置
    var boundingBoxColor: CIColor = CIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.8)  // 绿色框
    var centerDotColor: CIColor = CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)    // 红色点
    var trajectoryColor: CIColor = CIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.7)   // 蓝色轨迹
    var velocityArrowColor: CIColor = CIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 0.9) // 黄色箭头
    var textColor: CIColor = CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)          // 白色文字
    var textBackgroundColor: CIColor = CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6) // 黑色半透明背景

    // 线宽和大小
    var boundingBoxLineWidth: CGFloat = 3.0
    var centerDotRadius: CGFloat = 6.0
    var trajectoryLineWidth: CGFloat = 2.0
    var velocityArrowLineWidth: CGFloat = 2.5
    var velocityArrowScale: CGFloat = 100.0  // 速度向量显示比例

    // 文字配置
    var fontSize: CGFloat = 20.0
    var fontName: String = "Helvetica-Bold"

    // 显示开关
    var showBoundingBox: Bool = true
    var showCenterDot: Bool = true
    var showTrajectory: Bool = true
    var showVelocityArrow: Bool = true
    var showConfidence: Bool = true
    var showTimestamp: Bool = true
    var showStatistics: Bool = true

    static let `default` = VisualizationStyle()
}

// MARK: - 可视化引擎

/// 网球可视化引擎 - 使用 Core Graphics 绘制标注
actor BallVisualizationEngine: BallVisualizing {

    // MARK: - Properties

    private let style: VisualizationStyle
    private let context: CIContext

    // 统计信息
    private var totalFramesVisualized: Int = 0

    // MARK: - Initialization

    init(style: VisualizationStyle = .default) {
        self.style = style

        // 创建 CIContext with Metal support for better performance
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: metalDevice)
        } else {
            self.context = CIContext()
        }
    }

    // MARK: - Public API

    /// 在视频帧上绘制网球检测结果
    /// - Parameters:
    ///   - pixelBuffer: 原始视频帧
    ///   - result: 网球分析结果
    ///   - audioEvents: 可选的音频事件时间点（用于标注击球声）
    /// - Returns: 带标注的新 pixel buffer
    func visualize(
        pixelBuffer: CVPixelBuffer,
        result: BallAnalysisResult,
        audioEvents: [Double]? = nil
    ) async -> CVPixelBuffer? {

        totalFramesVisualized += 1

        // 创建可变的 pixel buffer 副本
        guard let annotatedBuffer = createMutableCopy(of: pixelBuffer) else {
            return nil
        }

        // 获取图像尺寸
        let width = CVPixelBufferGetWidth(annotatedBuffer)
        let height = CVPixelBufferGetHeight(annotatedBuffer)
        let size = CGSize(width: width, height: height)

        // 锁定 pixel buffer 进行绘制
        CVPixelBufferLockBaseAddress(annotatedBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(annotatedBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(annotatedBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(annotatedBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let cgContext = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        // 绘制所有检测到的网球
        for detection in result.detections {
            drawDetection(detection, in: cgContext, imageSize: size)
        }

        // 绘制时间戳
        if style.showTimestamp {
            drawTimestamp(result.timestamp, in: cgContext, imageSize: size)
        }

        // 绘制统计信息
        if style.showStatistics {
            drawStatistics(result: result, in: cgContext, imageSize: size)
        }

        // 绘制音频事件标记
        if let audioEvents = audioEvents, !audioEvents.isEmpty {
            let isAudioEvent = audioEvents.contains { abs($0 - result.timestamp) < 0.1 }
            if isAudioEvent {
                drawAudioEventMarker(in: cgContext, imageSize: size)
            }
        }

        return annotatedBuffer
    }

    /// 批量可视化多帧
    func visualizeBatch(
        frames: [(CVPixelBuffer, BallAnalysisResult)],
        audioEvents: [Double]? = nil
    ) async -> [CVPixelBuffer] {

        var visualizedFrames: [CVPixelBuffer] = []

        for (buffer, result) in frames {
            if let annotated = await visualize(pixelBuffer: buffer, result: result, audioEvents: audioEvents) {
                visualizedFrames.append(annotated)
            }
        }

        return visualizedFrames
    }

    /// 获取统计信息
    func getStatistics() async -> Int {
        return totalFramesVisualized
    }

    // MARK: - Private Drawing Methods

    /// 绘制单个网球检测结果
    private func drawDetection(_ detection: BallDetection, in context: CGContext, imageSize: CGSize) {
        // 转换归一化坐标到像素坐标
        let pixelBox = convertToPixelCoordinates(detection.boundingBox, imageSize: imageSize)
        let pixelCenter = convertToPixelCoordinates(detection.center, imageSize: imageSize)

        // 绘制边界框
        if style.showBoundingBox {
            drawBoundingBox(pixelBox, confidence: detection.confidence, in: context)
        }

        // 绘制中心点
        if style.showCenterDot {
            drawCenterDot(at: pixelCenter, in: context)
        }

        // 绘制轨迹线
        if style.showTrajectory, let trajectory = detection.trajectory, trajectory.count > 1 {
            let pixelTrajectory = trajectory.map { convertToPixelCoordinates($0, imageSize: imageSize) }
            drawTrajectory(pixelTrajectory, in: context)
        }

        // 绘制速度向量箭头
        if style.showVelocityArrow && detection.movementMagnitude > 0.01 {
            drawVelocityArrow(from: pixelCenter, velocity: detection.velocity, in: context, imageSize: imageSize)
        }

        // 绘制置信度标签
        if style.showConfidence {
            drawConfidenceLabel(detection.confidence, near: pixelBox, in: context)
        }
    }

    /// 绘制边界框
    private func drawBoundingBox(_ rect: CGRect, confidence: Double, in context: CGContext) {
        context.saveGState()

        // 根据置信度调整透明度
        let alpha = 0.5 + confidence * 0.5
        context.setStrokeColor(
            red: style.boundingBoxColor.red,
            green: style.boundingBoxColor.green,
            blue: style.boundingBoxColor.blue,
            alpha: alpha
        )
        context.setLineWidth(style.boundingBoxLineWidth)

        context.stroke(rect)

        context.restoreGState()
    }

    /// 绘制中心点
    private func drawCenterDot(at point: CGPoint, in context: CGContext) {
        context.saveGState()

        context.setFillColor(
            red: style.centerDotColor.red,
            green: style.centerDotColor.green,
            blue: style.centerDotColor.blue,
            alpha: style.centerDotColor.alpha
        )

        let dotRect = CGRect(
            x: point.x - style.centerDotRadius,
            y: point.y - style.centerDotRadius,
            width: style.centerDotRadius * 2,
            height: style.centerDotRadius * 2
        )

        context.fillEllipse(in: dotRect)

        context.restoreGState()
    }

    /// 绘制轨迹线
    private func drawTrajectory(_ points: [CGPoint], in context: CGContext) {
        guard points.count > 1 else { return }

        context.saveGState()

        context.setStrokeColor(
            red: style.trajectoryColor.red,
            green: style.trajectoryColor.green,
            blue: style.trajectoryColor.blue,
            alpha: style.trajectoryColor.alpha
        )
        context.setLineWidth(style.trajectoryLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }

        context.strokePath()

        context.restoreGState()
    }

    /// 绘制速度向量箭头
    private func drawVelocityArrow(from point: CGPoint, velocity: CGVector, in context: CGContext, imageSize: CGSize) {
        context.saveGState()

        // 计算箭头终点（速度向量缩放）
        let scale = style.velocityArrowScale
        let endPoint = CGPoint(
            x: point.x + CGFloat(velocity.dx) * scale,
            y: point.y - CGFloat(velocity.dy) * scale  // Y轴反转
        )

        // 绘制箭头线
        context.setStrokeColor(
            red: style.velocityArrowColor.red,
            green: style.velocityArrowColor.green,
            blue: style.velocityArrowColor.blue,
            alpha: style.velocityArrowColor.alpha
        )
        context.setLineWidth(style.velocityArrowLineWidth)
        context.setLineCap(.round)

        context.move(to: point)
        context.addLine(to: endPoint)
        context.strokePath()

        // 绘制箭头头部
        let arrowHeadLength: CGFloat = 15.0
        let arrowHeadAngle: CGFloat = .pi / 6

        let angle = atan2(endPoint.y - point.y, endPoint.x - point.x)

        let arrowPoint1 = CGPoint(
            x: endPoint.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: endPoint.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )

        let arrowPoint2 = CGPoint(
            x: endPoint.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: endPoint.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )

        context.move(to: endPoint)
        context.addLine(to: arrowPoint1)
        context.move(to: endPoint)
        context.addLine(to: arrowPoint2)
        context.strokePath()

        context.restoreGState()
    }

    /// 绘制置信度标签
    private func drawConfidenceLabel(_ confidence: Double, near rect: CGRect, in context: CGContext) {
        let text = String(format: "%.0f%%", confidence * 100)

        // 创建文字属性
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: style.fontName, size: style.fontSize) ?? UIFont.systemFont(ofSize: style.fontSize, weight: .bold),
            .foregroundColor: UIColor(
                red: style.textColor.red,
                green: style.textColor.green,
                blue: style.textColor.blue,
                alpha: style.textColor.alpha
            )
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        // 计算标签位置（边界框右上角）
        let padding: CGFloat = 4.0
        let labelRect = CGRect(
            x: rect.maxX + 5,
            y: rect.minY - textSize.height - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // 绘制背景
        context.saveGState()
        context.setFillColor(
            red: style.textBackgroundColor.red,
            green: style.textBackgroundColor.green,
            blue: style.textBackgroundColor.blue,
            alpha: style.textBackgroundColor.alpha
        )
        context.fill(labelRect)
        context.restoreGState()

        // 绘制文字
        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )

        // 翻转坐标系以正确显示文字
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: labelRect.maxY + labelRect.minY)
        context.scaleBy(x: 1.0, y: -1.0)

        attributedString.draw(in: textRect)

        context.restoreGState()
    }

    /// 绘制时间戳
    private func drawTimestamp(_ timestamp: Double, in context: CGContext, imageSize: CGSize) {
        let text = String(format: "[时间] %02d:%05.2f", Int(timestamp) / 60, timestamp.truncatingRemainder(dividingBy: 60))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: style.fontName, size: style.fontSize) ?? UIFont.systemFont(ofSize: style.fontSize, weight: .bold),
            .foregroundColor: UIColor(
                red: style.textColor.red,
                green: style.textColor.green,
                blue: style.textColor.blue,
                alpha: style.textColor.alpha
            )
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let padding: CGFloat = 8.0
        let labelRect = CGRect(
            x: padding,
            y: padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // 绘制背景
        context.saveGState()
        context.setFillColor(
            red: style.textBackgroundColor.red,
            green: style.textBackgroundColor.green,
            blue: style.textBackgroundColor.blue,
            alpha: style.textBackgroundColor.alpha
        )
        context.fill(labelRect)
        context.restoreGState()

        // 绘制文字
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: labelRect.maxY + labelRect.minY)
        context.scaleBy(x: 1.0, y: -1.0)

        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)

        context.restoreGState()
    }

    /// 绘制统计信息
    private func drawStatistics(result: BallAnalysisResult, in context: CGContext, imageSize: CGSize) {
        let text = String(format: "检测: %d | 置信度: %.0f%%", result.detections.count, result.averageConfidence * 100)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: style.fontName, size: style.fontSize - 2) ?? UIFont.systemFont(ofSize: style.fontSize - 2, weight: .medium),
            .foregroundColor: UIColor(
                red: style.textColor.red,
                green: style.textColor.green,
                blue: style.textColor.blue,
                alpha: style.textColor.alpha
            )
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let padding: CGFloat = 8.0
        let labelRect = CGRect(
            x: padding,
            y: imageSize.height - textSize.height - padding * 3,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // 绘制背景
        context.saveGState()
        context.setFillColor(
            red: style.textBackgroundColor.red,
            green: style.textBackgroundColor.green,
            blue: style.textBackgroundColor.blue,
            alpha: style.textBackgroundColor.alpha
        )
        context.fill(labelRect)
        context.restoreGState()

        // 绘制文字
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: labelRect.maxY + labelRect.minY)
        context.scaleBy(x: 1.0, y: -1.0)

        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)

        context.restoreGState()
    }

    /// 绘制音频事件标记
    private func drawAudioEventMarker(in context: CGContext, imageSize: CGSize) {
        context.saveGState()

        // 绘制竖线
        context.setStrokeColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.8)
        context.setLineWidth(4.0)

        let x = imageSize.width / 2
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: imageSize.height))
        context.strokePath()

        // 绘制标签
        let text = "🔊 击球声"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: style.fontSize, weight: .bold),
            .foregroundColor: UIColor.white
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let padding: CGFloat = 8.0
        let labelRect = CGRect(
            x: x + 10,
            y: imageSize.height / 2 - textSize.height / 2 - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.8)
        context.fill(labelRect)

        context.textMatrix = .identity
        context.translateBy(x: 0, y: labelRect.maxY + labelRect.minY)
        context.scaleBy(x: 1.0, y: -1.0)

        let textRect = CGRect(
            x: labelRect.origin.x + padding,
            y: labelRect.origin.y + padding,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)

        context.restoreGState()
    }

    // MARK: - Helper Methods

    /// 创建可变的 pixel buffer 副本
    private func createMutableCopy(of pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var newPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            nil,
            &newPixelBuffer
        )

        guard status == kCVReturnSuccess, let newBuffer = newPixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(newBuffer, [])

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(newBuffer, [])
        }

        if let sourceData = CVPixelBufferGetBaseAddress(pixelBuffer),
           let destData = CVPixelBufferGetBaseAddress(newBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let totalBytes = bytesPerRow * height
            memcpy(destData, sourceData, totalBytes)
        }

        return newBuffer
    }

    /// 转换归一化坐标到像素坐标
    private func convertToPixelCoordinates(_ normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        return CGRect(
            x: normalizedRect.origin.x * imageSize.width,
            y: (1.0 - normalizedRect.origin.y - normalizedRect.height) * imageSize.height,  // Y轴翻转
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }

    /// 转换归一化点到像素坐标
    private func convertToPixelCoordinates(_ normalizedPoint: CGPoint, imageSize: CGSize) -> CGPoint {
        return CGPoint(
            x: normalizedPoint.x * imageSize.width,
            y: (1.0 - normalizedPoint.y) * imageSize.height  // Y轴翻转
        )
    }
}
