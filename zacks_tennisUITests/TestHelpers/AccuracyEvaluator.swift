//
//  AccuracyEvaluator.swift
//  zacks_tennisUITests
//
//  Evaluate rally detection accuracy against ground truth
//

import Foundation

/// Evaluates rally detection accuracy
class AccuracyEvaluator {

    // MARK: - Evaluation

    /// Evaluate detection results against ground truth
    /// - Parameters:
    ///   - detected: Detected rallies
    ///   - groundTruth: Ground truth rallies
    ///   - tolerance: Maximum boundary error tolerance (seconds)
    /// - Returns: Accuracy metrics
    static func evaluate(
        detected: [DetectedRally],
        groundTruth: [GroundTruthRally],
        tolerance: TimeInterval = 1.0
    ) -> AccuracyMetrics {
        var truePositives = 0
        var falsePositives = 0
        var falseNegatives = 0
        var boundaryErrors: [TimeInterval] = []

        // Track which ground truth rallies were matched
        var matchedGroundTruth = Set<Int>()

        // For each detected rally, find matching ground truth
        for detectedRally in detected {
            var bestMatch: (index: Int, error: TimeInterval)?

            for (gtIndex, gtRally) in groundTruth.enumerated() {
                if gtRally.matches(detectedRally, tolerance: tolerance) {
                    // Calculate boundary error
                    let startError = abs(detectedRally.startTime - gtRally.startTime)
                    let endError = abs(detectedRally.endTime - gtRally.endTime)
                    let avgError = (startError + endError) / 2.0

                    // Track best match (smallest boundary error)
                    if let current = bestMatch {
                        if avgError < current.error {
                            bestMatch = (gtIndex, avgError)
                        }
                    } else {
                        bestMatch = (gtIndex, avgError)
                    }
                }
            }

            if let match = bestMatch {
                // True positive
                if !matchedGroundTruth.contains(match.index) {
                    truePositives += 1
                    matchedGroundTruth.insert(match.index)
                    boundaryErrors.append(match.error)
                } else {
                    // Already matched - count as false positive
                    falsePositives += 1
                }
            } else {
                // No match found - false positive
                falsePositives += 1
            }
        }

        // Unmatched ground truth rallies are false negatives
        falseNegatives = groundTruth.count - matchedGroundTruth.count

        // Calculate boundary error statistics
        let avgBoundaryError = boundaryErrors.isEmpty ? 0 : boundaryErrors.reduce(0, +) / Double(boundaryErrors.count)
        let maxBoundaryError = boundaryErrors.max() ?? 0

        return AccuracyMetrics(
            truePositives: truePositives,
            falsePositives: falsePositives,
            falseNegatives: falseNegatives,
            averageBoundaryError: avgBoundaryError,
            maxBoundaryError: maxBoundaryError
        )
    }

    // MARK: - Detailed Analysis

    /// Generate detailed match analysis
    /// - Parameters:
    ///   - detected: Detected rallies
    ///   - groundTruth: Ground truth rallies
    ///   - tolerance: Boundary tolerance
    /// - Returns: Match analysis report
    static func generateMatchAnalysis(
        detected: [DetectedRally],
        groundTruth: [GroundTruthRally],
        tolerance: TimeInterval = 1.0
    ) -> String {
        var report = """
        Rally Detection Match Analysis
        ═══════════════════════════════════════════
        Tolerance: ±\(String(format: "%.1fs", tolerance))

        """

        var matchedPairs: [(detected: DetectedRally, groundTruth: GroundTruthRally, error: TimeInterval)] = []
        var unmatchedDetected: [DetectedRally] = []
        var matchedGTIndices = Set<Int>()

        // Find matches
        for detectedRally in detected {
            var bestMatch: (index: Int, gt: GroundTruthRally, error: TimeInterval)?

            for (gtIndex, gtRally) in groundTruth.enumerated() {
                if gtRally.matches(detectedRally, tolerance: tolerance) {
                    let startError = abs(detectedRally.startTime - gtRally.startTime)
                    let endError = abs(detectedRally.endTime - gtRally.endTime)
                    let avgError = (startError + endError) / 2.0

                    if let current = bestMatch {
                        if avgError < current.error {
                            bestMatch = (gtIndex, gtRally, avgError)
                        }
                    } else {
                        bestMatch = (gtIndex, gtRally, avgError)
                    }
                }
            }

            if let match = bestMatch, !matchedGTIndices.contains(match.index) {
                matchedPairs.append((detectedRally, match.gt, match.error))
                matchedGTIndices.insert(match.index)
            } else {
                unmatchedDetected.append(detectedRally)
            }
        }

        let unmatchedGroundTruth = groundTruth.enumerated().filter { !matchedGTIndices.contains($0.offset) }.map { $0.element }

        // Report matches
        report += """
        ✅ TRUE POSITIVES (\(matchedPairs.count)):
        ───────────────────────────────────────────

        """

        for (index, match) in matchedPairs.enumerated() {
            let startError = abs(match.detected.startTime - match.groundTruth.startTime)
            let endError = abs(match.detected.endTime - match.groundTruth.endTime)

            report += """
            \(index + 1). Detected: \(String(format: "%6.1f", match.detected.startTime))s - \(String(format: "%6.1f", match.detected.endTime))s
               Ground Truth: \(String(format: "%6.1f", match.groundTruth.startTime))s - \(String(format: "%6.1f", match.groundTruth.endTime))s
               Start Error: \(String(format: "%+.2fs", startError)) | End Error: \(String(format: "%+.2fs", endError)) | Avg: \(String(format: "%.2fs", match.error))

            """
        }

        // Report false positives
        report += """

        ❌ FALSE POSITIVES (\(unmatchedDetected.count)):
        ───────────────────────────────────────────

        """

        for (index, rally) in unmatchedDetected.enumerated() {
            report += """
            \(index + 1). \(String(format: "%6.1f", rally.startTime))s - \(String(format: "%6.1f", rally.endTime))s (Duration: \(String(format: "%.1fs", rally.duration)))
               Score: \(String(format: "%.1f", rally.excitementScore)) | Confidence: \(String(format: "%.2f", rally.detectionConfidence))

            """
        }

        // Report false negatives
        report += """

        ⚠️  FALSE NEGATIVES (\(unmatchedGroundTruth.count)):
        ───────────────────────────────────────────

        """

        for (index, rally) in unmatchedGroundTruth.enumerated() {
            report += """
            \(index + 1). \(String(format: "%6.1f", rally.startTime))s - \(String(format: "%6.1f", rally.endTime))s (Duration: \(String(format: "%.1fs", rally.duration)))

            """
        }

        return report
    }

    // MARK: - Batch Evaluation

    /// Evaluate multiple test videos
    /// - Parameter results: Array of (detection result, ground truth) pairs
    /// - Returns: Combined accuracy metrics
    static func evaluateBatch(
        results: [(detected: RallyDetectionResult, groundTruth: GroundTruthData)],
        tolerance: TimeInterval = 1.0
    ) -> BatchEvaluationResult {
        var allMetrics: [AccuracyMetrics] = []
        var videoMetrics: [(video: String, metrics: AccuracyMetrics)] = []

        for (detectionResult, groundTruth) in results {
            let metrics = evaluate(
                detected: detectionResult.rallies,
                groundTruth: groundTruth.rallies,
                tolerance: tolerance
            )

            allMetrics.append(metrics)
            videoMetrics.append((groundTruth.videoURL.lastPathComponent, metrics))
        }

        // Combine metrics
        let totalTP = allMetrics.reduce(0) { $0 + $1.truePositives }
        let totalFP = allMetrics.reduce(0) { $0 + $1.falsePositives }
        let totalFN = allMetrics.reduce(0) { $0 + $1.falseNegatives }

        let allBoundaryErrors = allMetrics.flatMap { metrics -> [TimeInterval] in
            // Reconstruct boundary errors (simplified - actual count based on TP)
            Array(repeating: metrics.averageBoundaryError, count: metrics.truePositives)
        }

        let avgBoundaryError = allBoundaryErrors.isEmpty ? 0 : allBoundaryErrors.reduce(0, +) / Double(allBoundaryErrors.count)
        let maxBoundaryError = allBoundaryErrors.max() ?? 0

        let combinedMetrics = AccuracyMetrics(
            truePositives: totalTP,
            falsePositives: totalFP,
            falseNegatives: totalFN,
            averageBoundaryError: avgBoundaryError,
            maxBoundaryError: maxBoundaryError
        )

        return BatchEvaluationResult(
            combinedMetrics: combinedMetrics,
            perVideoMetrics: videoMetrics
        )
    }

    // MARK: - Performance Metrics

    /// Calculate additional performance metrics
    /// - Parameter metrics: Accuracy metrics
    /// - Returns: Extended performance report
    static func generatePerformanceReport(_ metrics: AccuracyMetrics) -> String {
        return """
        \(metrics.report())

        Additional Metrics:
        ═══════════════════════════════════════════
        Pass Criteria (85% accuracy): \(metrics.accuracy >= 0.85 ? "✅ PASS" : "❌ FAIL")
        Boundary Error < 1s: \(metrics.averageBoundaryError < 1.0 ? "✅ PASS" : "❌ FAIL")
        """
    }
}

// MARK: - Batch Evaluation Result

/// Result of batch evaluation across multiple videos
struct BatchEvaluationResult {
    let combinedMetrics: AccuracyMetrics
    let perVideoMetrics: [(video: String, metrics: AccuracyMetrics)]

    /// Generate summary report
    func report() -> String {
        var output = """
        Batch Evaluation Summary
        ═══════════════════════════════════════════
        Videos Evaluated: \(perVideoMetrics.count)

        Combined Results:
        \(combinedMetrics.report())

        Per-Video Results:
        ───────────────────────────────────────────

        """

        for (video, metrics) in perVideoMetrics {
            output += """
            📹 \(video)
               Accuracy: \(String(format: "%.1f%%", metrics.accuracy * 100))
               Precision: \(String(format: "%.1f%%", metrics.precision * 100))
               Recall: \(String(format: "%.1f%%", metrics.recall * 100))
               Avg Boundary Error: \(String(format: "%.2fs", metrics.averageBoundaryError))

            """
        }

        return output
    }
}
