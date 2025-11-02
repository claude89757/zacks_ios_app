//
//  MovementAnalyzer.swift
//  zacks_tennisUITests
//
//  Video movement analysis using Vision framework
//

import Foundation
import AVFoundation
import Vision
import CoreGraphics
import VideoToolbox

/// Analyzes video frames for human movement and pose
class MovementAnalyzer {

    private let config: ThresholdConfig
    private var previousFrame: FrameAnalysis?

    init(config: ThresholdConfig = ThresholdConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Analyze video for movement patterns
    /// - Parameter videoURL: URL of video file
    /// - Returns: Video analysis result with frame-by-frame data
    func analyze(videoURL: URL) async throws -> VideoAnalysisResult {
        let startTime = Date()

        let asset = AVAsset(url: videoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MovementAnalysisError.noVideoTrack
        }

        // Get video properties
        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // Calculate sampling interval based on config
        let analysisInterval = 1.0 / TimeInterval(config.videoAnalysisFPS)

        // Analyze frames at specified intervals
        var frames: [FrameAnalysis] = []
        var currentTime: TimeInterval = 0
        let totalDuration = CMTimeGetSeconds(duration)

        // Reset previous frame tracking
        previousFrame = nil

        while currentTime < totalDuration {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)

            if let frame = try await analyzeFrame(at: cmTime, in: asset) {
                frames.append(frame)
            }

            currentTime += analysisInterval
        }

        let processingTime = Date().timeIntervalSince(startTime)

        return VideoAnalysisResult(
            frames: frames,
            processingTime: processingTime,
            frameRate: config.videoAnalysisFPS
        )
    }

    // MARK: - Frame Analysis

    /// Analyze a single frame for movement
    private func analyzeFrame(at time: CMTime, in asset: AVAsset) async throws -> FrameAnalysis? {
        let timestamp = CMTimeGetSeconds(time)

        // Extract frame image
        guard let pixelBuffer = try await extractFrame(at: time, from: asset) else {
            return nil
        }

        // Perform pose detection
        let (hasPerson, personCount, poseConfidence, keyPoints) = try await detectPose(in: pixelBuffer)

        // Calculate movement intensity
        let movementIntensity = calculateMovementIntensity(
            keyPoints: keyPoints,
            timestamp: timestamp
        )

        // Calculate derived metrics
        let wristVelocity = calculateWristVelocity(
            currentKeyPoints: keyPoints,
            timestamp: timestamp
        )

        let bodyDisplacement = calculateBodyDisplacement(
            currentKeyPoints: keyPoints
        )

        let frame = FrameAnalysis(
            timestamp: timestamp,
            movementIntensity: movementIntensity,
            hasPerson: hasPerson,
            personCount: personCount,
            poseConfidence: poseConfidence,
            keyPoints: keyPoints,
            wristVelocity: wristVelocity,
            bodyDisplacement: bodyDisplacement
        )

        // Update previous frame for velocity calculations
        previousFrame = frame

        return frame
    }

    /// Extract a frame from video at specified time
    private func extractFrame(at time: CMTime, from asset: AVAsset) async throws -> CVPixelBuffer? {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero

        let (image, _) = try await imageGenerator.image(at: time)
        return image.pixelBuffer()
    }

    // MARK: - Pose Detection

    /// Detect human pose in frame using Vision
    private func detectPose(in pixelBuffer: CVPixelBuffer) async throws -> (Bool, Int, Float, [String: CGPoint]?) {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNHumanBodyPoseObservation],
                      !observations.isEmpty else {
                    // No person detected
                    continuation.resume(returning: (false, 0, 0, nil))
                    return
                }

                let personCount = observations.count
                let observation = observations[0]  // Use first person for simplicity

                // Extract key points
                var keyPoints: [String: CGPoint] = [:]
                let jointsToTrack: [VNHumanBodyPoseObservation.JointName] = [
                    .rightWrist, .leftWrist,
                    .rightElbow, .leftElbow,
                    .rightShoulder, .leftShoulder,
                    .neck, .root
                ]

                var totalConfidence: Float = 0
                var confidenceCount: Float = 0

                for jointName in jointsToTrack {
                    if let point = try? observation.recognizedPoint(jointName),
                       point.confidence > self.config.poseConfidenceThreshold {
                        keyPoints[jointName.rawValue.description] = CGPoint(
                            x: CGFloat(point.location.x),
                            y: CGFloat(point.location.y)
                        )
                        totalConfidence += point.confidence
                        confidenceCount += 1
                    }
                }

                let avgConfidence = confidenceCount > 0 ? totalConfidence / confidenceCount : 0

                continuation.resume(returning: (
                    true,
                    personCount,
                    avgConfidence,
                    keyPoints.isEmpty ? nil : keyPoints
                ))
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Movement Calculations

    /// Calculate movement intensity based on pose key points
    private func calculateMovementIntensity(keyPoints: [String: CGPoint]?, timestamp: TimeInterval) -> Float {
        guard let currentPoints = keyPoints,
              let previousPoints = previousFrame?.keyPoints else {
            return 0
        }

        // Calculate displacement of key joints
        var totalDisplacement: CGFloat = 0
        var pointCount: CGFloat = 0

        for (jointName, currentPos) in currentPoints {
            if let previousPos = previousPoints[jointName] {
                let dx = currentPos.x - previousPos.x
                let dy = currentPos.y - previousPos.y
                let displacement = sqrt(dx * dx + dy * dy)
                totalDisplacement += displacement
                pointCount += 1
            }
        }

        guard pointCount > 0 else { return 0 }

        // Average displacement across tracked joints
        let avgDisplacement = totalDisplacement / pointCount

        // Normalize to 0-1 range
        // Typical tennis movements: 0.05-0.3 in normalized coordinates per frame at 5fps
        // Scale factor to map typical movements to 0-1
        let normalized = Float(min(avgDisplacement / 0.3, 1.0))

        return normalized
    }

    /// Calculate wrist velocity (indicator of racket swing)
    private func calculateWristVelocity(currentKeyPoints: [String: CGPoint]?, timestamp: TimeInterval) -> Float? {
        guard let currentPoints = currentKeyPoints,
              let previousPoints = previousFrame?.keyPoints,
              let previousTimestamp = previousFrame?.timestamp else {
            return nil
        }

        let deltaTime = timestamp - previousTimestamp
        guard deltaTime > 0 else { return nil }

        // Check right wrist (most players are right-handed)
        var maxVelocity: CGFloat = 0

        for wristKey in ["rightWrist", "leftWrist"] {
            if let currentWrist = currentPoints[wristKey],
               let previousWrist = previousPoints[wristKey] {
                let dx = currentWrist.x - previousWrist.x
                let dy = currentWrist.y - previousWrist.y
                let displacement = sqrt(dx * dx + dy * dy)
                let velocity = displacement / CGFloat(deltaTime)
                maxVelocity = max(maxVelocity, velocity)
            }
        }

        return Float(maxVelocity)
    }

    /// Calculate body center displacement
    private func calculateBodyDisplacement(currentKeyPoints: [String: CGPoint]?) -> Float? {
        guard let currentPoints = currentKeyPoints,
              let previousPoints = previousFrame?.keyPoints else {
            return nil
        }

        // Use root (hip center) or neck as body center
        let bodyCenterKeys = ["root", "neck"]

        for key in bodyCenterKeys {
            if let currentCenter = currentPoints[key],
               let previousCenter = previousPoints[key] {
                let dx = currentCenter.x - previousCenter.x
                let dy = currentCenter.y - previousCenter.y
                return Float(sqrt(dx * dx + dy * dy))
            }
        }

        return nil
    }
}

// MARK: - Helper Extensions

extension CGImage {
    /// Convert CGImage to CVPixelBuffer
    func pixelBuffer() -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}

// MARK: - Errors

enum MovementAnalysisError: Error, CustomStringConvertible {
    case noVideoTrack
    case cannotExtractFrame
    case poseDetectionFailed

    var description: String {
        switch self {
        case .noVideoTrack:
            return "Video has no video track"
        case .cannotExtractFrame:
            return "Cannot extract frame from video"
        case .poseDetectionFailed:
            return "Pose detection failed"
        }
    }
}
