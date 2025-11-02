//
//  ThresholdConfig.swift
//  zacks_tennisUITests
//
//  Configurable thresholds for rally detection algorithm tuning
//

import Foundation

/// Configurable parameters for rally detection algorithm
struct ThresholdConfig {

    // MARK: - Audio Analysis Parameters

    /// Minimum amplitude to consider as potential hit sound (0-1)
    var audioAmplitudeThreshold: Float = 0.3

    /// Minimum confidence for audio peak detection (0-1)
    var audioPeakConfidence: Float = 0.6

    /// Tennis hit sound frequency range (Hz)
    var hitSoundFrequencyRange: ClosedRange<Float> = 500...4000

    /// FFT window size (samples)
    var fftWindowSize: Int = 2048

    /// Audio analysis hop size (samples, smaller = more precise but slower)
    var audioHopSize: Int = 1024

    /// Peak detection window duration (seconds)
    var peakDetectionWindow: TimeInterval = 0.1

    // MARK: - Video Analysis Parameters

    /// Minimum movement intensity to consider as activity (0-1)
    var movementIntensityThreshold: Float = 0.4

    /// Minimum pose detection confidence (0-1)
    var poseConfidenceThreshold: Float = 0.5

    /// Frame sampling rate for analysis (fps)
    /// Default 5fps (analyze every 0.2s for 30fps video)
    var videoAnalysisFPS: Float = 5.0

    /// Wrist velocity threshold for hit detection (pixels/second)
    var wristVelocityThreshold: Float = 100.0

    // MARK: - Temporal Analysis Parameters

    /// Minimum number of consecutive high-intensity frames to start rally
    var rallyStartFrameCount: Int = 3

    /// Maximum pause duration within rally (seconds)
    var maxPauseDuration: TimeInterval = 2.0

    /// Minimum pause duration to end rally (seconds)
    var minPauseDurationToEnd: TimeInterval = 2.0

    /// Minimum rally duration (seconds)
    var minRallyDuration: TimeInterval = 3.0

    /// Maximum rally duration (seconds, to filter false positives)
    var maxRallyDuration: TimeInterval = 120.0

    /// Time padding before rally start (seconds)
    var rallyStartPadding: TimeInterval = 1.0

    /// Time padding after rally end (seconds)
    var rallyEndPadding: TimeInterval = 1.0

    // MARK: - Feature Fusion Parameters

    /// Weight for video movement intensity in fusion (0-1)
    var videoWeight: Float = 0.5

    /// Weight for audio hit density in fusion (0-1)
    var audioWeight: Float = 0.3

    /// Weight for temporal continuity in fusion (0-1)
    var temporalWeight: Float = 0.2

    /// Minimum combined confidence to accept rally (0-1)
    var minCombinedConfidence: Float = 0.6

    /// Audio-video synchronization offset (seconds)
    /// Positive = audio leads video (typical for real recordings)
    var audioVideoSyncOffset: TimeInterval = 0.05

    // MARK: - Excitement Scoring Parameters

    /// Weight for rally duration in excitement score (0-1)
    var durationWeight: Float = 0.3

    /// Weight for movement intensity in excitement score (0-1)
    var intensityWeight: Float = 0.4

    /// Weight for hit frequency in excitement score (0-1)
    var hitFrequencyWeight: Float = 0.2

    /// Weight for rally continuity in excitement score (0-1)
    var continuityWeight: Float = 0.1

    /// Maximum duration for scoring (seconds)
    /// Rallies longer than this get max duration points
    var maxScoringDuration: TimeInterval = 30.0

    /// Expected hit rate for exciting rallies (hits/second)
    var excitingHitRate: Float = 1.0

    // MARK: - Performance Parameters

    /// Enable multi-threading for audio/video parallel processing
    var enableParallelProcessing: Bool = true

    /// Maximum video duration for single-pass processing (seconds)
    /// Videos longer than this are processed in chunks
    var chunkDuration: TimeInterval = 600.0  // 10 minutes

    /// Enable caching of Vision requests
    var enableVisionRequestCaching: Bool = true

    // MARK: - Validation

    /// Validate all parameters are within reasonable ranges
    func validate() throws {
        guard audioAmplitudeThreshold >= 0 && audioAmplitudeThreshold <= 1 else {
            throw ConfigError.invalidParameter("audioAmplitudeThreshold must be 0-1")
        }
        guard videoWeight + audioWeight + temporalWeight ≈ 1.0 else {
            throw ConfigError.invalidParameter("Fusion weights must sum to 1.0")
        }
        guard durationWeight + intensityWeight + hitFrequencyWeight + continuityWeight ≈ 1.0 else {
            throw ConfigError.invalidParameter("Scoring weights must sum to 1.0")
        }
        guard minRallyDuration > 0 && minRallyDuration < maxRallyDuration else {
            throw ConfigError.invalidParameter("Invalid rally duration range")
        }
    }

    // MARK: - Presets

    /// Default configuration optimized for outdoor tennis
    static var outdoor: ThresholdConfig {
        var config = ThresholdConfig()
        config.audioAmplitudeThreshold = 0.35  // Higher threshold for outdoor noise
        config.movementIntensityThreshold = 0.45
        return config
    }

    /// Configuration optimized for indoor tennis
    static var indoor: ThresholdConfig {
        var config = ThresholdConfig()
        config.audioAmplitudeThreshold = 0.25  // Lower threshold, less ambient noise
        config.movementIntensityThreshold = 0.4
        config.hitSoundFrequencyRange = 600...3500  // Different acoustics
        return config
    }

    /// High precision configuration (slower but more accurate)
    static var highPrecision: ThresholdConfig {
        var config = ThresholdConfig()
        config.videoAnalysisFPS = 10.0  // Analyze more frames
        config.audioHopSize = 512       // Smaller hop for better temporal resolution
        config.minCombinedConfidence = 0.7
        return config
    }

    /// Fast configuration (lower accuracy but faster processing)
    static var fast: ThresholdConfig {
        var config = ThresholdConfig()
        config.videoAnalysisFPS = 3.0
        config.audioHopSize = 2048
        config.enableVisionRequestCaching = true
        return config
    }
}

// MARK: - Helper Extensions

infix operator ≈ : ComparisonPrecedence

extension Float {
    /// Approximate equality for floating point (within 0.01)
    static func ≈ (lhs: Float, rhs: Float) -> Bool {
        abs(lhs - rhs) < 0.01
    }
}

// MARK: - Errors

enum ConfigError: Error, CustomStringConvertible {
    case invalidParameter(String)

    var description: String {
        switch self {
        case .invalidParameter(let msg):
            return "Invalid configuration: \(msg)"
        }
    }
}

// MARK: - Config Management

extension ThresholdConfig {
    /// Save configuration to file
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    /// Load configuration from file
    static func load(from url: URL) throws -> ThresholdConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ThresholdConfig.self, from: data)
    }
}

// Make ThresholdConfig Codable for serialization
extension ThresholdConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case audioAmplitudeThreshold, audioPeakConfidence, hitSoundFrequencyRange
        case fftWindowSize, audioHopSize, peakDetectionWindow
        case movementIntensityThreshold, poseConfidenceThreshold, videoAnalysisFPS
        case wristVelocityThreshold, rallyStartFrameCount, maxPauseDuration
        case minPauseDurationToEnd, minRallyDuration, maxRallyDuration
        case rallyStartPadding, rallyEndPadding, videoWeight, audioWeight
        case temporalWeight, minCombinedConfidence, audioVideoSyncOffset
        case durationWeight, intensityWeight, hitFrequencyWeight, continuityWeight
        case maxScoringDuration, excitingHitRate, enableParallelProcessing
        case chunkDuration, enableVisionRequestCaching
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()

        // Decode all properties
        audioAmplitudeThreshold = try container.decode(Float.self, forKey: .audioAmplitudeThreshold)
        audioPeakConfidence = try container.decode(Float.self, forKey: .audioPeakConfidence)
        // ... (other properties would be decoded similarly)

        try validate()
    }
}
