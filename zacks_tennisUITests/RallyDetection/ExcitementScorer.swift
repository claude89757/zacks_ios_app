//
//  ExcitementScorer.swift
//  zacks_tennisUITests
//
//  Calculate excitement scores for detected rallies
//

import Foundation

/// Scores rallies based on excitement level (0-100)
class ExcitementScorer {

    private let config: ThresholdConfig

    init(config: ThresholdConfig = ThresholdConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Calculate excitement scores for all rallies
    /// - Parameter rallies: Detected rallies to score
    /// - Returns: Rallies with updated excitement scores
    func scoreRallies(_ rallies: [DetectedRally]) -> [DetectedRally] {
        return rallies.map { rally in
            var scoredRally = rally
            scoredRally.excitementScore = calculateScore(for: rally)
            return scoredRally
        }
    }

    /// Calculate excitement score for a single rally
    /// - Parameter rally: Rally to score
    /// - Returns: Excitement score (0-100)
    func calculateScore(for rally: DetectedRally) -> Float {
        // Component 1: Duration score (0-100)
        let durationScore = calculateDurationScore(rally: rally)

        // Component 2: Intensity score (0-100)
        let intensityScore = calculateIntensityScore(rally: rally)

        // Component 3: Hit frequency score (0-100)
        let hitFrequencyScore = calculateHitFrequencyScore(rally: rally)

        // Component 4: Continuity score (0-100)
        let continuityScore = calculateContinuityScore(rally: rally)

        // Weighted combination
        let totalScore =
            durationScore * config.durationWeight +
            intensityScore * config.intensityWeight +
            hitFrequencyScore * config.hitFrequencyWeight +
            continuityScore * config.continuityWeight

        return min(max(totalScore, 0), 100)  // Clamp to 0-100
    }

    // MARK: - Score Components

    /// Calculate duration score
    /// Longer rallies are more exciting up to a point
    private func calculateDurationScore(rally: DetectedRally) -> Float {
        let duration = rally.duration

        // Score increases linearly up to maxScoringDuration, then plateaus
        let normalizedDuration = min(duration / config.maxScoringDuration, 1.0)

        return Float(normalizedDuration) * 100
    }

    /// Calculate intensity score
    /// Higher movement intensity = more exciting
    private func calculateIntensityScore(rally: DetectedRally) -> Float {
        let avgIntensity = rally.avgMovementIntensity
        let peakIntensity = rally.peakMovementIntensity

        // Combine average and peak
        // Average shows sustained action, peak shows explosive moments
        let combinedIntensity = avgIntensity * 0.6 + peakIntensity * 0.4

        // Normalize to 0-1 based on threshold
        let normalized = min(combinedIntensity / config.movementIntensityThreshold, 1.0)

        return normalized * 100
    }

    /// Calculate hit frequency score
    /// More hits per second = more exciting
    private func calculateHitFrequencyScore(rally: DetectedRally) -> Float {
        let hitDensity = rally.hitDensity

        // Normalize based on exciting hit rate
        let normalized = min(hitDensity / config.excitingHitRate, 1.0)

        // Apply curve to reward high hit densities more
        // Use square root to create a curve that rewards higher densities
        let curved = sqrt(normalized)

        return curved * 100
    }

    /// Calculate continuity score
    /// Smooth, continuous rallies are more exciting than choppy ones
    private func calculateContinuityScore(rally: DetectedRally) -> Float {
        return rally.continuity * 100
    }

    // MARK: - Advanced Scoring

    /// Calculate bonus points for special rally characteristics
    func calculateBonusPoints(rally: DetectedRally) -> Float {
        var bonus: Float = 0

        // Bonus 1: Long rally bonus (>20s)
        if rally.duration > 20 {
            bonus += 5
        }

        // Bonus 2: High hit density bonus (>1.5 hits/sec)
        if rally.hitDensity > 1.5 {
            bonus += 5
        }

        // Bonus 3: Very high peak intensity bonus
        if rally.peakMovementIntensity > config.movementIntensityThreshold * 1.5 {
            bonus += 5
        }

        // Bonus 4: Perfect continuity bonus
        if rally.continuity > 0.95 {
            bonus += 3
        }

        return bonus
    }

    /// Apply penalties for rally characteristics that reduce excitement
    func calculatePenalties(rally: DetectedRally) -> Float {
        var penalty: Float = 0

        // Penalty 1: Low detection confidence
        if rally.detectionConfidence < 0.7 {
            penalty += 10
        }

        // Penalty 2: Low average intensity despite high peak (inconsistent)
        if rally.peakMovementIntensity > rally.avgMovementIntensity * 3 {
            penalty += 5
        }

        // Penalty 3: Very short rallies
        if rally.duration < 5 {
            penalty += 15
        }

        // Penalty 4: Low hit count
        if rally.hitCount < 3 {
            penalty += 10
        }

        return penalty
    }

    /// Calculate adjusted score with bonuses and penalties
    func calculateAdjustedScore(for rally: DetectedRally) -> Float {
        let baseScore = calculateScore(for: rally)
        let bonus = calculateBonusPoints(rally: rally)
        let penalty = calculatePenalties(rally: rally)

        let adjusted = baseScore + bonus - penalty

        return min(max(adjusted, 0), 100)  // Clamp to 0-100
    }

    // MARK: - Comparative Scoring

    /// Score rallies relative to each other (normalize to 0-100 range)
    /// This ensures the most exciting rally gets close to 100
    func scoreRalliesComparatively(_ rallies: [DetectedRally]) -> [DetectedRally] {
        guard !rallies.isEmpty else { return [] }

        // Calculate raw scores
        let scoredRallies = rallies.map { rally -> (rally: DetectedRally, rawScore: Float) in
            let score = calculateAdjustedScore(for: rally)
            return (rally, score)
        }

        // Find max score for normalization
        let maxScore = scoredRallies.map { $0.rawScore }.max() ?? 1.0

        // Avoid division by zero
        guard maxScore > 0 else {
            return rallies.map { var r = $0; r.excitementScore = 0; return r }
        }

        // Normalize scores
        return scoredRallies.map { rallyAndScore in
            var rally = rallyAndScore.rally
            let normalizedScore = (rallyAndScore.rawScore / maxScore) * 100
            rally.excitementScore = normalizedScore
            return rally
        }
    }

    // MARK: - Scoring Insights

    /// Generate detailed scoring breakdown for debugging/tuning
    func generateScoringBreakdown(for rally: DetectedRally) -> ScoringBreakdown {
        let durationScore = calculateDurationScore(rally: rally)
        let intensityScore = calculateIntensityScore(rally: rally)
        let hitFrequencyScore = calculateHitFrequencyScore(rally: rally)
        let continuityScore = calculateContinuityScore(rally: rally)
        let bonus = calculateBonusPoints(rally: rally)
        let penalty = calculatePenalties(rally: rally)

        let baseScore =
            durationScore * config.durationWeight +
            intensityScore * config.intensityWeight +
            hitFrequencyScore * config.hitFrequencyWeight +
            continuityScore * config.continuityWeight

        let finalScore = min(max(baseScore + bonus - penalty, 0), 100)

        return ScoringBreakdown(
            durationScore: durationScore,
            intensityScore: intensityScore,
            hitFrequencyScore: hitFrequencyScore,
            continuityScore: continuityScore,
            baseScore: baseScore,
            bonus: bonus,
            penalty: penalty,
            finalScore: finalScore,
            rally: rally
        )
    }
}

// MARK: - Scoring Breakdown Model

/// Detailed breakdown of excitement score components
struct ScoringBreakdown: CustomStringConvertible {
    let durationScore: Float
    let intensityScore: Float
    let hitFrequencyScore: Float
    let continuityScore: Float
    let baseScore: Float
    let bonus: Float
    let penalty: Float
    let finalScore: Float
    let rally: DetectedRally

    var description: String {
        """
        Excitement Score Breakdown
        ═════════════════════════════
        Rally: \(String(format: "%.1fs", rally.startTime)) - \(String(format: "%.1fs", rally.endTime)) (Duration: \(String(format: "%.1fs", rally.duration)))

        Components:
        - Duration:      \(String(format: "%5.1f", durationScore)) (weight: \(String(format: "%.0f%%", ThresholdConfig().durationWeight * 100)))
        - Intensity:     \(String(format: "%5.1f", intensityScore)) (weight: \(String(format: "%.0f%%", ThresholdConfig().intensityWeight * 100)))
        - Hit Frequency: \(String(format: "%5.1f", hitFrequencyScore)) (weight: \(String(format: "%.0f%%", ThresholdConfig().hitFrequencyWeight * 100)))
        - Continuity:    \(String(format: "%5.1f", continuityScore)) (weight: \(String(format: "%.0f%%", ThresholdConfig().continuityWeight * 100)))

        Base Score:      \(String(format: "%5.1f", baseScore))
        Bonus Points:  + \(String(format: "%5.1f", bonus))
        Penalties:     - \(String(format: "%5.1f", penalty))
        ─────────────────────────────
        Final Score:     \(String(format: "%5.1f", finalScore))

        Rally Stats:
        - Avg Intensity: \(String(format: "%.2f", rally.avgMovementIntensity))
        - Peak Intensity: \(String(format: "%.2f", rally.peakMovementIntensity))
        - Hit Count: \(rally.hitCount)
        - Hit Density: \(String(format: "%.2f", rally.hitDensity)) hits/sec
        - Continuity: \(String(format: "%.2f", rally.continuity))
        - Confidence: \(String(format: "%.2f", rally.detectionConfidence))
        """
    }
}
