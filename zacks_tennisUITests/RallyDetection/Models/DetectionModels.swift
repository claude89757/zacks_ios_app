//
//  DetectionModels.swift
//  zacks_tennisUITests
//
//  Core data models for rally detection algorithm
//

import Foundation
import CoreGraphics
import AVFoundation

// MARK: - Audio Analysis Models

/// Represents a detected audio peak (potential hit sound)
struct AudioPeak {
    let timestamp: TimeInterval      // Time in video (seconds)
    let amplitude: Float             // Peak amplitude (0-1 normalized)
    let frequency: Float             // Dominant frequency in Hz
    let confidence: Float            // Detection confidence (0-1)
    let spectralEnergy: Float        // Energy in 500-4000Hz range

    /// Check if this peak is likely a tennis hit sound
    var isLikelyHitSound: Bool {
        // Tennis hit sounds typically 500-4000Hz with sharp attack
        frequency >= 500 && frequency <= 4000 &&
        amplitude > 0.3 &&
        confidence > 0.6
    }
}

/// Audio analysis result for entire video
struct AudioAnalysisResult {
    let peaks: [AudioPeak]
    let processingTime: TimeInterval
    let sampleRate: Double

    /// Get hit sounds within time range
    func hitSounds(in range: ClosedRange<TimeInterval>) -> [AudioPeak] {
        peaks.filter { range.contains($0.timestamp) && $0.isLikelyHitSound }
    }

    /// Calculate hit density (hits per second) in time range
    func hitDensity(in range: ClosedRange<TimeInterval>) -> Float {
        let hits = hitSounds(in: range)
        let duration = Float(range.upperBound - range.lowerBound)
        return duration > 0 ? Float(hits.count) / duration : 0
    }
}

// MARK: - Video Analysis Models

/// Single frame analysis result
struct FrameAnalysis {
    let timestamp: TimeInterval
    let movementIntensity: Float     // 0-1 normalized movement intensity
    let hasPerson: Bool
    let personCount: Int
    let poseConfidence: Float        // 0-1
    let keyPoints: [String: CGPoint]?  // Joint positions

    // Derived metrics
    let wristVelocity: Float?        // Racket arm wrist speed (pixels/sec)
    let bodyDisplacement: Float?     // Center of mass movement
}

/// Video analysis result for entire video
struct VideoAnalysisResult {
    let frames: [FrameAnalysis]
    let processingTime: TimeInterval
    let frameRate: Float

    /// Get frames in time range
    func frames(in range: ClosedRange<TimeInterval>) -> [FrameAnalysis] {
        frames.filter { range.contains($0.timestamp) }
    }

    /// Calculate average movement intensity in range
    func averageIntensity(in range: ClosedRange<TimeInterval>) -> Float {
        let rangeFrames = frames(in: range)
        guard !rangeFrames.isEmpty else { return 0 }
        let sum = rangeFrames.reduce(0.0) { $0 + $1.movementIntensity }
        return sum / Float(rangeFrames.count)
    }

    /// Find peak movement intensity in range
    func peakIntensity(in range: ClosedRange<TimeInterval>) -> Float {
        frames(in: range).map { $0.movementIntensity }.max() ?? 0
    }
}

// MARK: - Rally Detection Models

/// Temporal state during rally detection
enum RallyState {
    case idle                        // No activity
    case rallyStarting               // Potential rally beginning
    case inRally                     // Active rally
    case rallyEnding                 // Rally winding down

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .rallyStarting: return "Rally Starting"
        case .inRally: return "In Rally"
        case .rallyEnding: return "Rally Ending"
        }
    }
}

/// Detected rally with metadata
struct DetectedRally {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval

    // Computed properties
    var duration: TimeInterval { endTime - startTime }
    var timeRange: ClosedRange<TimeInterval> { startTime...endTime }

    // Detection metadata
    let detectionConfidence: Float   // 0-1 overall confidence
    let avgMovementIntensity: Float  // Average video intensity
    let peakMovementIntensity: Float // Peak video intensity
    let hitCount: Int                // Estimated number of hits
    let hitDensity: Float            // Hits per second
    let continuity: Float            // 0-1 how continuous the rally is

    // Excitement score
    var excitementScore: Float = 0   // 0-100, calculated by ExcitementScorer

    init(startTime: TimeInterval,
         endTime: TimeInterval,
         detectionConfidence: Float,
         avgMovementIntensity: Float,
         peakMovementIntensity: Float,
         hitCount: Int,
         hitDensity: Float,
         continuity: Float) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.detectionConfidence = detectionConfidence
        self.avgMovementIntensity = avgMovementIntensity
        self.peakMovementIntensity = peakMovementIntensity
        self.hitCount = hitCount
        self.hitDensity = hitDensity
        self.continuity = continuity
    }
}

/// Complete rally detection result
struct RallyDetectionResult {
    let rallies: [DetectedRally]
    let videoURL: URL
    let processingTime: TimeInterval

    // Statistics
    var totalRallies: Int { rallies.count }
    var averageRallyDuration: TimeInterval {
        guard !rallies.isEmpty else { return 0 }
        return rallies.reduce(0.0) { $0 + $1.duration } / TimeInterval(rallies.count)
    }
    var longestRally: DetectedRally? {
        rallies.max(by: { $0.duration < $1.duration })
    }
    var topExcitingRally: DetectedRally? {
        rallies.max(by: { $0.excitementScore < $1.excitementScore })
    }

    /// Get top N rallies by excitement score
    func topRallies(count: Int) -> [DetectedRally] {
        Array(rallies.sorted(by: { $0.excitementScore > $1.excitementScore }).prefix(count))
    }
}

// MARK: - Feature Fusion Models

/// Combined features for a time segment
struct FusedFeatures {
    let timeRange: ClosedRange<TimeInterval>
    let videoIntensity: Float        // 0-1
    let audioHitDensity: Float       // hits/sec
    let temporalContinuity: Float    // 0-1
    let combinedConfidence: Float    // 0-1 weighted fusion

    /// Calculate if this segment is likely a rally
    var isLikelyRally: Bool {
        combinedConfidence > 0.6
    }
}

// MARK: - Ground Truth Models (for testing)

/// Ground truth rally annotation for testing
struct GroundTruthRally {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let excitementScore: Float?      // Optional manual excitement rating
    let notes: String?

    var duration: TimeInterval { endTime - startTime }
    var timeRange: ClosedRange<TimeInterval> { startTime...endTime }

    /// Check if detected rally matches this ground truth (within tolerance)
    func matches(_ detected: DetectedRally, tolerance: TimeInterval = 1.0) -> Bool {
        abs(detected.startTime - startTime) <= tolerance &&
        abs(detected.endTime - endTime) <= tolerance
    }
}

/// Ground truth data for a test video
struct GroundTruthData {
    let videoURL: URL
    let rallies: [GroundTruthRally]
    let metadata: [String: Any]
}

// MARK: - Accuracy Evaluation Models

/// Evaluation result for rally detection
struct AccuracyMetrics {
    let truePositives: Int           // Correctly detected rallies
    let falsePositives: Int          // Incorrectly detected rallies
    let falseNegatives: Int          // Missed rallies

    // Computed metrics
    var precision: Float {
        let total = truePositives + falsePositives
        return total > 0 ? Float(truePositives) / Float(total) : 0
    }

    var recall: Float {
        let total = truePositives + falseNegatives
        return total > 0 ? Float(truePositives) / Float(total) : 0
    }

    var f1Score: Float {
        let sum = precision + recall
        return sum > 0 ? 2 * precision * recall / sum : 0
    }

    var accuracy: Float {
        // For rally detection, we use recall as "accuracy"
        // (what % of real rallies did we detect within 1s boundary tolerance)
        recall
    }

    // Boundary error statistics
    let averageBoundaryError: TimeInterval
    let maxBoundaryError: TimeInterval

    /// Generate human-readable report
    func report() -> String {
        """
        Rally Detection Accuracy Report
        ═══════════════════════════════
        True Positives:  \(truePositives)
        False Positives: \(falsePositives)
        False Negatives: \(falseNegatives)

        Precision: \(String(format: "%.1f%%", precision * 100))
        Recall:    \(String(format: "%.1f%%", recall * 100))
        F1 Score:  \(String(format: "%.1f%%", f1Score * 100))
        Accuracy:  \(String(format: "%.1f%%", accuracy * 100))

        Avg Boundary Error: \(String(format: "%.2fs", averageBoundaryError))
        Max Boundary Error: \(String(format: "%.2fs", maxBoundaryError))
        """
    }
}
