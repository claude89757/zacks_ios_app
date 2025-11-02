//
//  TemporalAnalyzer.swift
//  zacks_tennisUITests
//
//  Temporal analysis and rally boundary detection using state machine
//

import Foundation

/// Analyzes temporal patterns to detect rally boundaries
class TemporalAnalyzer {

    private let config: ThresholdConfig

    init(config: ThresholdConfig = ThresholdConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Detect rallies from video and audio analysis results
    /// - Parameters:
    ///   - videoResult: Video analysis result
    ///   - audioResult: Audio analysis result
    /// - Returns: Array of detected rallies with metadata
    func detectRallies(
        videoResult: VideoAnalysisResult,
        audioResult: AudioAnalysisResult
    ) -> [DetectedRally] {
        // Step 1: Run state machine to find candidate rallies
        let candidateRallies = runStateMachine(
            frames: videoResult.frames,
            audioPeaks: audioResult.peaks
        )

        // Step 2: Refine rally boundaries
        let refinedRallies = refineBoundaries(
            rallies: candidateRallies,
            frames: videoResult.frames,
            audioPeaks: audioResult.peaks
        )

        // Step 3: Filter false positives
        let validRallies = filterFalsePositives(
            rallies: refinedRallies,
            frames: videoResult.frames,
            audioPeaks: audioResult.peaks
        )

        // Step 4: Add padding to rally boundaries
        let paddedRallies = addPadding(rallies: validRallies)

        return paddedRallies
    }

    // MARK: - State Machine

    /// Run state machine to detect rally candidates
    private func runStateMachine(
        frames: [FrameAnalysis],
        audioPeaks: [AudioPeak]
    ) -> [CandidateRally] {
        var rallies: [CandidateRally] = []
        var state: RallyState = .idle

        var currentRallyStart: TimeInterval?
        var currentRallyFrames: [FrameAnalysis] = []
        var consecutiveHighFrames = 0
        var lastActivityTime: TimeInterval = 0

        for frame in frames.sorted(by: { $0.timestamp < $1.timestamp }) {
            let isHighIntensity = frame.movementIntensity >= config.movementIntensityThreshold
            let timestamp = frame.timestamp

            // Check for nearby audio peaks (within 0.2s)
            let hasNearbyAudioPeak = audioPeaks.contains { peak in
                abs(peak.timestamp - timestamp) <= 0.2 && peak.isLikelyHitSound
            }

            // Combined activity indicator
            let hasActivity = isHighIntensity || hasNearbyAudioPeak

            switch state {
            case .idle:
                if hasActivity {
                    consecutiveHighFrames = 1
                    state = .rallyStarting
                    currentRallyStart = timestamp
                    currentRallyFrames = [frame]
                    lastActivityTime = timestamp
                }

            case .rallyStarting:
                if hasActivity {
                    consecutiveHighFrames += 1
                    currentRallyFrames.append(frame)
                    lastActivityTime = timestamp

                    // Transition to in_rally if enough consecutive activity
                    if consecutiveHighFrames >= config.rallyStartFrameCount {
                        state = .inRally
                    }
                } else {
                    // Activity stopped before rally started
                    consecutiveHighFrames = 0
                    state = .idle
                    currentRallyStart = nil
                    currentRallyFrames = []
                }

            case .inRally:
                currentRallyFrames.append(frame)

                if hasActivity {
                    lastActivityTime = timestamp
                } else {
                    // Check pause duration
                    let pauseDuration = timestamp - lastActivityTime

                    if pauseDuration >= config.minPauseDurationToEnd {
                        // Rally ended
                        state = .rallyEnding
                    }
                }

            case .rallyEnding:
                // Finalize rally
                if let startTime = currentRallyStart {
                    let endTime = lastActivityTime
                    let duration = endTime - startTime

                    // Check minimum duration
                    if duration >= config.minRallyDuration {
                        let rally = CandidateRally(
                            startTime: startTime,
                            endTime: endTime,
                            frames: currentRallyFrames
                        )
                        rallies.append(rally)
                    }
                }

                // Reset state
                state = .idle
                currentRallyStart = nil
                currentRallyFrames = []
                consecutiveHighFrames = 0

                // Check if new rally starting
                if hasActivity {
                    state = .rallyStarting
                    currentRallyStart = timestamp
                    currentRallyFrames = [frame]
                    consecutiveHighFrames = 1
                    lastActivityTime = timestamp
                }
            }
        }

        // Handle case where video ends during rally
        if state == .inRally, let startTime = currentRallyStart {
            let endTime = lastActivityTime
            let duration = endTime - startTime

            if duration >= config.minRallyDuration {
                let rally = CandidateRally(
                    startTime: startTime,
                    endTime: endTime,
                    frames: currentRallyFrames
                )
                rallies.append(rally)
            }
        }

        return rallies
    }

    // MARK: - Boundary Refinement

    /// Refine rally boundaries using audio cues
    private func refineBoundaries(
        rallies: [CandidateRally],
        frames: [FrameAnalysis],
        audioPeaks: [AudioPeak]
    ) -> [CandidateRally] {
        return rallies.map { rally in
            var refinedStart = rally.startTime
            var refinedEnd = rally.endTime

            // Find first audio peak near start
            let startPeaks = audioPeaks.filter {
                $0.isLikelyHitSound &&
                $0.timestamp >= rally.startTime - 1.0 &&
                $0.timestamp <= rally.startTime + 1.0
            }.sorted(by: { $0.timestamp < $1.timestamp })

            if let firstPeak = startPeaks.first {
                refinedStart = max(rally.startTime - 0.5, firstPeak.timestamp - 0.3)
            }

            // Find last audio peak near end
            let endPeaks = audioPeaks.filter {
                $0.isLikelyHitSound &&
                $0.timestamp >= rally.endTime - 1.0 &&
                $0.timestamp <= rally.endTime + 1.0
            }.sorted(by: { $0.timestamp > $1.timestamp })

            if let lastPeak = endPeaks.first {
                refinedEnd = min(rally.endTime + 0.5, lastPeak.timestamp + 0.3)
            }

            return CandidateRally(
                startTime: refinedStart,
                endTime: refinedEnd,
                frames: rally.frames
            )
        }
    }

    // MARK: - False Positive Filtering

    /// Filter out false positive detections
    private func filterFalsePositives(
        rallies: [CandidateRally],
        frames: [FrameAnalysis],
        audioPeaks: [AudioPeak]
    ) -> [CandidateRally] {
        return rallies.filter { rally in
            // Filter 1: Duration check
            let duration = rally.duration
            guard duration >= config.minRallyDuration &&
                  duration <= config.maxRallyDuration else {
                return false
            }

            // Filter 2: Minimum activity level
            let rallyFrames = frames.filter { rally.timeRange.contains($0.timestamp) }
            let avgIntensity = rallyFrames.isEmpty ? 0 :
                rallyFrames.reduce(0.0) { $0 + $1.movementIntensity } / Float(rallyFrames.count)

            guard avgIntensity >= config.movementIntensityThreshold * 0.7 else {
                return false  // Too low overall intensity
            }

            // Filter 3: Minimum hit count
            let hitCount = audioPeaks.filter {
                $0.isLikelyHitSound && rally.timeRange.contains($0.timestamp)
            }.count

            guard hitCount >= 2 else {
                return false  // Need at least 2 hits for a rally
            }

            // Filter 4: Check continuity (no long gaps)
            let hasLongGap = checkForLongGaps(rally: rally, frames: rallyFrames)
            guard !hasLongGap else {
                return false
            }

            return true
        }
    }

    /// Check if rally has long gaps in activity
    private func checkForLongGaps(rally: CandidateRally, frames: [FrameAnalysis]) -> Bool {
        let sortedFrames = frames.sorted(by: { $0.timestamp < $1.timestamp })

        for i in 0..<sortedFrames.count - 1 {
            let gap = sortedFrames[i + 1].timestamp - sortedFrames[i].timestamp

            // If gap is larger than sampling interval + max pause, it's suspicious
            let maxAllowedGap = 1.0 / TimeInterval(config.videoAnalysisFPS) + config.maxPauseDuration

            if gap > maxAllowedGap {
                return true
            }
        }

        return false
    }

    // MARK: - Padding

    /// Add time padding to rally boundaries for better capture
    private func addPadding(rallies: [CandidateRally]) -> [DetectedRally] {
        return rallies.map { rally in
            let paddedStart = max(0, rally.startTime - config.rallyStartPadding)
            let paddedEnd = rally.endTime + config.rallyEndPadding

            // Calculate metadata
            let metadata = calculateMetadata(rally: rally)

            return DetectedRally(
                startTime: paddedStart,
                endTime: paddedEnd,
                detectionConfidence: metadata.confidence,
                avgMovementIntensity: metadata.avgIntensity,
                peakMovementIntensity: metadata.peakIntensity,
                hitCount: metadata.hitCount,
                hitDensity: metadata.hitDensity,
                continuity: metadata.continuity
            )
        }
    }

    // MARK: - Metadata Calculation

    /// Calculate metadata for a rally
    private func calculateMetadata(rally: CandidateRally) -> RallyMetadata {
        let frames = rally.frames
        let duration = rally.duration

        // Average intensity
        let avgIntensity = frames.isEmpty ? 0 :
            frames.reduce(0.0) { $0 + $1.movementIntensity } / Float(frames.count)

        // Peak intensity
        let peakIntensity = frames.map { $0.movementIntensity }.max() ?? 0

        // Hit count (from frames with high wrist velocity)
        let hitCount = frames.filter { frame in
            (frame.wristVelocity ?? 0) > config.wristVelocityThreshold
        }.count

        // Hit density
        let hitDensity = duration > 0 ? Float(hitCount) / Float(duration) : 0

        // Continuity (how consistent is the activity)
        let continuity = calculateContinuity(frames: frames)

        // Overall confidence
        let intensityScore = min(avgIntensity / config.movementIntensityThreshold, 1.0)
        let hitScore = min(hitDensity / config.excitingHitRate, 1.0)
        let confidence = intensityScore * 0.6 + hitScore * 0.3 + continuity * 0.1

        return RallyMetadata(
            avgIntensity: avgIntensity,
            peakIntensity: peakIntensity,
            hitCount: hitCount,
            hitDensity: hitDensity,
            continuity: continuity,
            confidence: confidence
        )
    }

    /// Calculate rally continuity score
    private func calculateContinuity(frames: [FrameAnalysis]) -> Float {
        guard frames.count > 1 else { return 0 }

        let sortedFrames = frames.sorted(by: { $0.timestamp < $1.timestamp })
        let expectedInterval = 1.0 / TimeInterval(config.videoAnalysisFPS)

        var consistentIntervals = 0
        for i in 0..<sortedFrames.count - 1 {
            let interval = sortedFrames[i + 1].timestamp - sortedFrames[i].timestamp
            if abs(interval - expectedInterval) < expectedInterval * 0.5 {
                consistentIntervals += 1
            }
        }

        return Float(consistentIntervals) / Float(frames.count - 1)
    }
}

// MARK: - Helper Types

/// Candidate rally before final processing
private struct CandidateRally {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let frames: [FrameAnalysis]

    var duration: TimeInterval { endTime - startTime }
    var timeRange: ClosedRange<TimeInterval> { startTime...endTime }
}

/// Rally metadata for internal use
private struct RallyMetadata {
    let avgIntensity: Float
    let peakIntensity: Float
    let hitCount: Int
    let hitDensity: Float
    let continuity: Float
    let confidence: Float
}
