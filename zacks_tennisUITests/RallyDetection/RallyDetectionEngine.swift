//
//  RallyDetectionEngine.swift
//  zacks_tennisUITests
//
//  Main rally detection engine - orchestrates all components
//

import Foundation
import AVFoundation

/// Main engine for detecting tennis rallies in video
class RallyDetectionEngine {

    // Component analyzers
    private let audioAnalyzer: AudioAnalyzer
    private let movementAnalyzer: MovementAnalyzer
    private let temporalAnalyzer: TemporalAnalyzer
    private let featureFusion: FeatureFusion
    private let excitementScorer: ExcitementScorer

    private let config: ThresholdConfig

    // MARK: - Initialization

    init(config: ThresholdConfig = ThresholdConfig()) {
        self.config = config
        self.audioAnalyzer = AudioAnalyzer(config: config)
        self.movementAnalyzer = MovementAnalyzer(config: config)
        self.temporalAnalyzer = TemporalAnalyzer(config: config)
        self.featureFusion = FeatureFusion(config: config)
        self.excitementScorer = ExcitementScorer(config: config)
    }

    // MARK: - Public API

    /// Detect rallies in a tennis video
    /// - Parameter videoURL: URL of the video file
    /// - Returns: Rally detection result with all detected rallies
    func detectRallies(in videoURL: URL) async throws -> RallyDetectionResult {
        let startTime = Date()

        print("🎾 Rally Detection Started")
        print("📹 Video: \(videoURL.lastPathComponent)")
        print("⚙️  Config: \(config.enableParallelProcessing ? "Parallel" : "Sequential") processing")
        print("")

        // Step 1: Analyze audio and video (potentially in parallel)
        let (audioResult, videoResult) = try await analyzeAudioAndVideo(videoURL: videoURL)

        print("✅ Analysis complete:")
        print("   - Audio: \(audioResult.peaks.count) peaks detected in \(String(format: "%.2fs", audioResult.processingTime))")
        print("   - Video: \(videoResult.frames.count) frames analyzed in \(String(format: "%.2fs", videoResult.processingTime))")
        print("")

        // Step 2: Detect rally candidates using temporal analysis
        print("🔍 Detecting rally candidates...")
        let candidateRallies = temporalAnalyzer.detectRallies(
            videoResult: videoResult,
            audioResult: audioResult
        )
        print("   Found \(candidateRallies.count) candidate rallies")
        print("")

        // Step 3: Refine rallies using feature fusion
        print("🔧 Refining rallies with feature fusion...")
        let refinedRallies = featureFusion.refineRallies(
            candidateRallies,
            videoResult: videoResult,
            audioResult: audioResult
        )
        print("   \(refinedRallies.count) rallies after fusion filtering")
        print("")

        // Step 4: Calculate excitement scores
        print("⭐ Calculating excitement scores...")
        let scoredRallies = excitementScorer.scoreRalliesComparatively(refinedRallies)
        print("   Scored \(scoredRallies.count) rallies")
        print("")

        // Step 5: Sort by excitement score
        let sortedRallies = scoredRallies.sorted { $0.excitementScore > $1.excitementScore }

        let processingTime = Date().timeIntervalSince(startTime)

        print("✅ Rally Detection Complete!")
        print("   Total time: \(String(format: "%.2fs", processingTime))")
        print("   Rallies detected: \(sortedRallies.count)")
        if let topRally = sortedRallies.first {
            print("   Top rally: \(String(format: "%.1fs", topRally.startTime)) - \(String(format: "%.1fs", topRally.endTime)) (score: \(String(format: "%.1f", topRally.excitementScore)))")
        }
        print("")

        return RallyDetectionResult(
            rallies: sortedRallies,
            videoURL: videoURL,
            processingTime: processingTime
        )
    }

    // MARK: - Audio and Video Analysis

    /// Analyze audio and video, potentially in parallel
    private func analyzeAudioAndVideo(videoURL: URL) async throws -> (AudioAnalysisResult, VideoAnalysisResult) {
        if config.enableParallelProcessing {
            // Parallel processing
            async let audioResult = audioAnalyzer.analyze(videoURL: videoURL)
            async let videoResult = movementAnalyzer.analyze(videoURL: videoURL)

            return try await (audioResult, videoResult)
        } else {
            // Sequential processing
            let audioResult = try await audioAnalyzer.analyze(videoURL: videoURL)
            let videoResult = try await movementAnalyzer.analyze(videoURL: videoURL)

            return (audioResult, videoResult)
        }
    }

    // MARK: - Batch Processing

    /// Process multiple videos in batch
    /// - Parameter videoURLs: Array of video URLs to process
    /// - Returns: Array of rally detection results
    func batchDetectRallies(in videoURLs: [URL]) async throws -> [RallyDetectionResult] {
        var results: [RallyDetectionResult] = []

        for (index, videoURL) in videoURLs.enumerated() {
            print("📊 Processing video \(index + 1)/\(videoURLs.count)")
            let result = try await detectRallies(in: videoURL)
            results.append(result)
        }

        return results
    }

    // MARK: - Chunked Processing (for long videos)

    /// Detect rallies in a long video by processing in chunks
    /// - Parameter videoURL: URL of the video file
    /// - Returns: Rally detection result
    func detectRalliesWithChunking(in videoURL: URL) async throws -> RallyDetectionResult {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)

        // Check if chunking is needed
        guard totalDuration > config.chunkDuration else {
            // Video is short enough, process normally
            return try await detectRallies(in: videoURL)
        }

        print("📹 Video is long (\(String(format: "%.1f", totalDuration))s), using chunked processing")

        var allRallies: [DetectedRally] = []
        var currentTime: TimeInterval = 0

        while currentTime < totalDuration {
            let chunkEnd = min(currentTime + config.chunkDuration, totalDuration)

            print("   Processing chunk: \(String(format: "%.1f", currentTime))s - \(String(format: "%.1f", chunkEnd))s")

            // For simplicity in test code, we still process the whole video
            // In production, you'd want to extract and process only the chunk
            let result = try await detectRallies(in: videoURL)

            // Filter rallies to only those in this chunk
            let chunkRallies = result.rallies.filter { rally in
                rally.startTime >= currentTime && rally.startTime < chunkEnd
            }

            allRallies.append(contentsOf: chunkRallies)

            currentTime = chunkEnd
        }

        // Re-score rallies comparatively across all chunks
        let scoredRallies = excitementScorer.scoreRalliesComparatively(allRallies)

        return RallyDetectionResult(
            rallies: scoredRallies,
            videoURL: videoURL,
            processingTime: 0  // TODO: track total time
        )
    }

    // MARK: - Diagnostics

    /// Generate detailed diagnostic report
    func generateDiagnosticReport(result: RallyDetectionResult) -> String {
        var report = """
        Rally Detection Diagnostic Report
        ═════════════════════════════════════
        Video: \(result.videoURL.lastPathComponent)
        Processing Time: \(String(format: "%.2fs", result.processingTime))
        Total Rallies: \(result.totalRallies)
        Average Duration: \(String(format: "%.2fs", result.averageRallyDuration))

        """

        if let longest = result.longestRally {
            report += """
            Longest Rally: \(String(format: "%.2fs", longest.duration)) at \(String(format: "%.1fs", longest.startTime))

            """
        }

        if let topExciting = result.topExcitingRally {
            report += """
            Most Exciting Rally: Score \(String(format: "%.1f", topExciting.excitementScore)) at \(String(format: "%.1fs", topExciting.startTime))

            """
        }

        report += """
        Top 5 Rallies by Excitement:
        ────────────────────────────────────

        """

        for (index, rally) in result.topRallies(count: 5).enumerated() {
            report += """
            \(index + 1). Time: \(String(format: "%6.1fs", rally.startTime)) - \(String(format: "%6.1fs", rally.endTime)) | Duration: \(String(format: "%5.1fs", rally.duration)) | Score: \(String(format: "%5.1f", rally.excitementScore))
               Hits: \(rally.hitCount) | Density: \(String(format: "%.2f", rally.hitDensity)) hits/s | Intensity: \(String(format: "%.2f", rally.avgMovementIntensity))

            """
        }

        return report
    }

    /// Generate scoring breakdown for a specific rally
    func generateScoringBreakdown(for rally: DetectedRally) -> String {
        let breakdown = excitementScorer.generateScoringBreakdown(for: rally)
        return breakdown.description
    }
}

// MARK: - DetectedRally Extension for Mutability

extension DetectedRally {
    /// Create a new rally with updated excitement score
    func withExcitementScore(_ score: Float) -> DetectedRally {
        var newRally = self
        newRally.excitementScore = score
        return newRally
    }
}

// Note: DetectedRally.excitementScore needs to be var instead of let
// This requires updating the model definition
