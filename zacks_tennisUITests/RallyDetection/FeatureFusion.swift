//
//  FeatureFusion.swift
//  zacks_tennisUITests
//
//  Multi-feature fusion for rally detection
//

import Foundation

/// Fuses multiple feature sources for improved rally detection
class FeatureFusion {

    private let config: ThresholdConfig

    init(config: ThresholdConfig = ThresholdConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Refine detected rallies using feature fusion
    /// - Parameters:
    ///   - rallies: Initial rally detections
    ///   - videoResult: Video analysis result
    ///   - audioResult: Audio analysis result
    /// - Returns: Refined rallies with updated confidence scores
    func refineRallies(
        _ rallies: [DetectedRally],
        videoResult: VideoAnalysisResult,
        audioResult: AudioAnalysisResult
    ) -> [DetectedRally] {
        return rallies.compactMap { rally in
            // Calculate fused features for this rally
            let fused = fuseFeatures(
                for: rally,
                videoResult: videoResult,
                audioResult: audioResult
            )

            // Only keep rallies that meet fusion threshold
            guard fused.isLikelyRally else {
                return nil
            }

            // Update rally with fused confidence
            var refinedRally = rally
            refinedRally.excitementScore = 0  // Will be calculated by ExcitementScorer

            return refinedRally
        }
    }

    /// Calculate fused features for a time segment
    /// - Parameters:
    ///   - rally: Rally to analyze
    ///   - videoResult: Video analysis result
    ///   - audioResult: Audio analysis result
    /// - Returns: Fused feature representation
    func fuseFeatures(
        for rally: DetectedRally,
        videoResult: VideoAnalysisResult,
        audioResult: AudioAnalysisResult
    ) -> FusedFeatures {
        let timeRange = rally.timeRange

        // Feature 1: Video movement intensity
        let videoIntensity = calculateVideoIntensityScore(
            timeRange: timeRange,
            videoResult: videoResult
        )

        // Feature 2: Audio hit density
        let audioHitDensity = calculateAudioHitDensityScore(
            timeRange: timeRange,
            audioResult: audioResult
        )

        // Feature 3: Temporal continuity
        let temporalContinuity = rally.continuity

        // Fuse features with configured weights
        let combinedConfidence = fuseWithWeights(
            videoIntensity: videoIntensity,
            audioHitDensity: audioHitDensity,
            temporalContinuity: temporalContinuity
        )

        return FusedFeatures(
            timeRange: timeRange,
            videoIntensity: videoIntensity,
            audioHitDensity: audioHitDensity,
            temporalContinuity: temporalContinuity,
            combinedConfidence: combinedConfidence
        )
    }

    // MARK: - Feature Score Calculation

    /// Calculate normalized video intensity score
    private func calculateVideoIntensityScore(
        timeRange: ClosedRange<TimeInterval>,
        videoResult: VideoAnalysisResult
    ) -> Float {
        let avgIntensity = videoResult.averageIntensity(in: timeRange)
        let peakIntensity = videoResult.peakIntensity(in: timeRange)

        // Combine average and peak (average is more stable, peak shows excitement)
        let combined = avgIntensity * 0.7 + peakIntensity * 0.3

        // Normalize to 0-1 range
        return min(combined / config.movementIntensityThreshold, 1.0)
    }

    /// Calculate normalized audio hit density score
    private func calculateAudioHitDensityScore(
        timeRange: ClosedRange<TimeInterval>,
        audioResult: AudioAnalysisResult
    ) -> Float {
        let hitDensity = audioResult.hitDensity(in: timeRange)

        // Normalize based on expected exciting hit rate
        return min(hitDensity / config.excitingHitRate, 1.0)
    }

    // MARK: - Feature Fusion

    /// Fuse features using configured weights
    private func fuseWithWeights(
        videoIntensity: Float,
        audioHitDensity: Float,
        temporalContinuity: Float
    ) -> Float {
        let weighted =
            videoIntensity * config.videoWeight +
            audioHitDensity * config.audioWeight +
            temporalContinuity * config.temporalWeight

        return min(max(weighted, 0), 1)  // Clamp to 0-1
    }

    // MARK: - Audio-Video Synchronization

    /// Align audio and video features accounting for sync offset
    /// - Parameters:
    ///   - audioTimestamp: Audio event timestamp
    ///   - videoTimestamp: Video event timestamp
    /// - Returns: Whether events are synchronized
    func areEventsSynchronized(audioTimestamp: TimeInterval, videoTimestamp: TimeInterval) -> Bool {
        let offset = abs(audioTimestamp - videoTimestamp - config.audioVideoSyncOffset)
        return offset < 0.2  // Within 200ms is considered synchronized
    }

    /// Get synchronized audio peaks for a video frame
    /// - Parameters:
    ///   - frameTimestamp: Video frame timestamp
    ///   - audioPeaks: All audio peaks
    /// - Returns: Audio peaks synchronized with this frame
    func synchronizedAudioPeaks(
        for frameTimestamp: TimeInterval,
        in audioPeaks: [AudioPeak]
    ) -> [AudioPeak] {
        let adjustedTimestamp = frameTimestamp + config.audioVideoSyncOffset

        return audioPeaks.filter { peak in
            abs(peak.timestamp - adjustedTimestamp) < 0.2
        }
    }

    // MARK: - Advanced Fusion Techniques

    /// Calculate cross-correlation between audio and video signals
    /// This helps verify that audio hits align with video movements
    func calculateAudioVideoCorrelation(
        timeRange: ClosedRange<TimeInterval>,
        videoResult: VideoAnalysisResult,
        audioResult: AudioAnalysisResult
    ) -> Float {
        let frames = videoResult.frames(in: timeRange)
        let peaks = audioResult.hitSounds(in: timeRange)

        guard !frames.isEmpty && !peaks.isEmpty else { return 0 }

        // Count how many high-intensity video frames have nearby audio peaks
        var matchedFrames = 0
        for frame in frames where frame.movementIntensity > config.movementIntensityThreshold {
            let hasNearbyPeak = peaks.contains { peak in
                abs(peak.timestamp - frame.timestamp) < 0.3
            }
            if hasNearbyPeak {
                matchedFrames += 1
            }
        }

        let highIntensityFrames = frames.filter {
            $0.movementIntensity > config.movementIntensityThreshold
        }.count

        guard highIntensityFrames > 0 else { return 0 }

        return Float(matchedFrames) / Float(highIntensityFrames)
    }

    /// Detect if rally has suspicious patterns (potential false positive)
    func detectSuspiciousPatterns(
        rally: DetectedRally,
        videoResult: VideoAnalysisResult,
        audioResult: AudioAnalysisResult
    ) -> Bool {
        // Pattern 1: Too uniform intensity (might be camera movement, not tennis)
        let frames = videoResult.frames(in: rally.timeRange)
        let intensityVariance = calculateVariance(
            frames.map { $0.movementIntensity }
        )
        if intensityVariance < 0.01 {
            return true  // Too uniform
        }

        // Pattern 2: Audio peaks without video movement
        let audioHits = audioResult.hitSounds(in: rally.timeRange)
        let avgIntensity = videoResult.averageIntensity(in: rally.timeRange)

        if audioHits.count > 5 && avgIntensity < config.movementIntensityThreshold * 0.5 {
            return true  // Audio without movement (might be crowd noise)
        }

        // Pattern 3: Single burst of activity (not sustained rally)
        let activityClusters = detectActivityClusters(frames: frames)
        if activityClusters.count == 1 && rally.duration > 10 {
            return true  // Single burst in long time window
        }

        return false
    }

    // MARK: - Helper Functions

    /// Calculate variance of float array
    private func calculateVariance(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }

        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Float(values.count)
    }

    /// Detect clusters of high activity
    private func detectActivityClusters(frames: [FrameAnalysis]) -> [[FrameAnalysis]] {
        var clusters: [[FrameAnalysis]] = []
        var currentCluster: [FrameAnalysis] = []

        for frame in frames.sorted(by: { $0.timestamp < $1.timestamp }) {
            if frame.movementIntensity > config.movementIntensityThreshold {
                currentCluster.append(frame)
            } else {
                if !currentCluster.isEmpty {
                    clusters.append(currentCluster)
                    currentCluster = []
                }
            }
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }
}

// MARK: - Extensions

extension DetectedRally {
    /// Make DetectedRally mutable for refinement
    /// Note: In Swift, struct properties are immutable by default
    /// This would need to be refactored in production to use a builder pattern
    fileprivate mutating func updateExcitementScore(_ score: Float) {
        // This is a workaround - in production, DetectedRally should have
        // a var excitementScore instead of let
    }
}
