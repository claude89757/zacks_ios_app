//
//  GroundTruthParser.swift
//  zacks_tennisUITests
//
//  Parse ground truth annotations for rally detection validation
//

import Foundation

/// Parses ground truth annotation files
class GroundTruthParser {

    // MARK: - JSON Structure

    private struct GroundTruthJSON: Codable {
        let video: String
        let rallies: [RallyJSON]
        let metadata: [String: String]?

        struct RallyJSON: Codable {
            let startTime: Double
            let endTime: Double
            let excitementScore: Float?
            let notes: String?
        }
    }

    // MARK: - Public API

    /// Parse ground truth data from JSON file
    /// - Parameter url: URL of JSON file
    /// - Returns: Ground truth data
    static func parse(from url: URL) throws -> GroundTruthData {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        let json = try decoder.decode(GroundTruthJSON.self, from: data)

        let rallies = json.rallies.map { rallyJSON in
            GroundTruthRally(
                startTime: rallyJSON.startTime,
                endTime: rallyJSON.endTime,
                excitementScore: rallyJSON.excitementScore,
                notes: rallyJSON.notes
            )
        }

        let metadata = json.metadata ?? [:]

        // Get video URL (assume same directory)
        let videoURL = url.deletingLastPathComponent().appendingPathComponent(json.video)

        return GroundTruthData(
            videoURL: videoURL,
            rallies: rallies,
            metadata: metadata
        )
    }

    /// Parse ground truth from test video
    /// - Parameter testVideo: Test video with ground truth file
    /// - Returns: Ground truth data if available
    static func parse(testVideo: VideoTestLoader.TestVideo) throws -> GroundTruthData? {
        guard let groundTruthURL = testVideo.groundTruthURL else {
            return nil
        }

        return try parse(from: groundTruthURL)
    }

    // MARK: - Ground Truth Creation

    /// Create ground truth JSON template
    /// - Parameters:
    ///   - videoName: Name of video file
    ///   - rallies: Array of ground truth rallies
    ///   - outputURL: Where to save JSON file
    static func createGroundTruthFile(
        videoName: String,
        rallies: [GroundTruthRally],
        outputURL: URL
    ) throws {
        let json = GroundTruthJSON(
            video: videoName,
            rallies: rallies.map { rally in
                GroundTruthJSON.RallyJSON(
                    startTime: rally.startTime,
                    endTime: rally.endTime,
                    excitementScore: rally.excitementScore,
                    notes: rally.notes
                )
            },
            metadata: ["created": ISO8601DateFormatter().string(from: Date())]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(json)
        try data.write(to: outputURL)

        print("✅ Created ground truth file: \(outputURL.path)")
    }

    /// Generate ground truth template for a video
    /// - Parameter videoURL: Video to create template for
    /// - Returns: Template file content as string
    static func generateTemplate(for videoURL: URL) -> String {
        let videoName = videoURL.lastPathComponent

        return """
        {
          "video": "\(videoName)",
          "rallies": [
            {
              "startTime": 10.0,
              "endTime": 25.5,
              "excitementScore": 80,
              "notes": "Example rally - replace with actual data"
            }
          ],
          "metadata": {
            "annotator": "Your Name",
            "date": "\(ISO8601DateFormatter().string(from: Date()))",
            "notes": "Ground truth annotations for rally detection"
          }
        }
        """
    }

    // MARK: - Validation

    /// Validate ground truth data for consistency
    /// - Parameter groundTruth: Ground truth to validate
    /// - Returns: Validation errors (empty if valid)
    static func validate(_ groundTruth: GroundTruthData) -> [String] {
        var errors: [String] = []

        // Check video file exists
        if !FileManager.default.fileExists(atPath: groundTruth.videoURL.path) {
            errors.append("Video file not found: \(groundTruth.videoURL.path)")
        }

        // Validate each rally
        for (index, rally) in groundTruth.rallies.enumerated() {
            // Check time ordering
            if rally.startTime >= rally.endTime {
                errors.append("Rally \(index + 1): startTime must be < endTime")
            }

            // Check time values are reasonable
            if rally.startTime < 0 {
                errors.append("Rally \(index + 1): startTime must be >= 0")
            }

            // Check excitement score range if provided
            if let score = rally.excitementScore {
                if score < 0 || score > 100 {
                    errors.append("Rally \(index + 1): excitementScore must be 0-100")
                }
            }
        }

        // Check for overlapping rallies
        for i in 0..<groundTruth.rallies.count {
            for j in (i + 1)..<groundTruth.rallies.count {
                let rally1 = groundTruth.rallies[i]
                let rally2 = groundTruth.rallies[j]

                let overlaps = rally1.timeRange.overlaps(rally2.timeRange)
                if overlaps {
                    errors.append("Rallies \(i + 1) and \(j + 1) overlap")
                }
            }
        }

        return errors
    }

    /// Print ground truth statistics
    /// - Parameter groundTruth: Ground truth to analyze
    static func printStatistics(_ groundTruth: GroundTruthData) {
        print("""

        Ground Truth Statistics
        ═══════════════════════════════════════════
        Video: \(groundTruth.videoURL.lastPathComponent)
        Total Rallies: \(groundTruth.rallies.count)

        Rally Durations:
        """)

        let durations = groundTruth.rallies.map { $0.duration }
        if !durations.isEmpty {
            let avgDuration = durations.reduce(0, +) / Double(durations.count)
            let minDuration = durations.min() ?? 0
            let maxDuration = durations.max() ?? 0

            print("""
              Min: \(String(format: "%.1fs", minDuration))
              Max: \(String(format: "%.1fs", maxDuration))
              Avg: \(String(format: "%.1fs", avgDuration))
            """)
        }

        let withScores = groundTruth.rallies.filter { $0.excitementScore != nil }
        print("""

        Excitement Scores: \(withScores.count)/\(groundTruth.rallies.count) annotated
        ═══════════════════════════════════════════

        """)
    }
}
