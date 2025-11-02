//
//  RallyDetectionTests.swift
//  zacks_tennisUITests
//
//  Comprehensive tests for rally detection algorithm
//

import XCTest

@MainActor
final class RallyDetectionTests: XCTestCase {

    var engine: RallyDetectionEngine!
    var config: ThresholdConfig!

    // MARK: - Setup

    override func setUp() async throws {
        continueAfterFailure = false

        // Use default config for most tests
        config = ThresholdConfig()
        engine = RallyDetectionEngine(config: config)

        // Print test video directory info
        VideoTestLoader.printTestDirectoryInfo()
    }

    override func tearDown() async throws {
        engine = nil
        config = nil
    }

    // MARK: - Basic Functionality Tests

    /// Test that the engine can load and process a video
    func testEngineCanProcessVideo() async throws {
        let testVideos = try loadTestVideos()
        guard let firstVideo = testVideos.first else {
            XCTFail("No test videos found. Please add videos to test_videos folder")
            return
        }

        print("🎾 Testing basic processing with: \(firstVideo.name)")

        let result = try await engine.detectRallies(in: firstVideo.url)

        // Basic assertions
        XCTAssertNotNil(result, "Should return a result")
        XCTAssertGreaterThan(result.processingTime, 0, "Should take some time to process")

        print("✅ Processed successfully")
        print("   Rallies found: \(result.totalRallies)")
        print("   Processing time: \(String(format: "%.2fs", result.processingTime))")

        // Print diagnostic report
        let report = engine.generateDiagnosticReport(result: result)
        print(report)
    }

    /// Test accuracy against ground truth
    func testRallyDetectionAccuracy() async throws {
        let testVideos = try loadTestVideos()
        let videosWithGroundTruth = testVideos.filter { $0.hasGroundTruth }

        guard !videosWithGroundTruth.isEmpty else {
            XCTSkip("No test videos with ground truth found. Add .json files alongside videos")
        }

        print("🎯 Testing accuracy against ground truth")
        print("   Videos with annotations: \(videosWithGroundTruth.count)")

        var allResults: [(detected: RallyDetectionResult, groundTruth: GroundTruthData)] = []

        for testVideo in videosWithGroundTruth {
            print("\n📹 Processing: \(testVideo.name)")

            // Run detection
            let detectionResult = try await engine.detectRallies(in: testVideo.url)

            // Load ground truth
            guard let groundTruth = try GroundTruthParser.parse(testVideo: testVideo) else {
                continue
            }

            // Validate ground truth
            let validationErrors = GroundTruthParser.validate(groundTruth)
            XCTAssert(validationErrors.isEmpty, "Ground truth validation failed: \(validationErrors.joined(separator: ", "))")

            // Print statistics
            GroundTruthParser.printStatistics(groundTruth)

            // Evaluate accuracy
            let metrics = AccuracyEvaluator.evaluate(
                detected: detectionResult.rallies,
                groundTruth: groundTruth.rallies,
                tolerance: 1.0
            )

            print(metrics.report())

            // Generate detailed match analysis
            let matchAnalysis = AccuracyEvaluator.generateMatchAnalysis(
                detected: detectionResult.rallies,
                groundTruth: groundTruth.rallies,
                tolerance: 1.0
            )
            print(matchAnalysis)

            // Assert accuracy requirement
            XCTAssertGreaterThanOrEqual(
                metrics.accuracy,
                0.85,
                "Accuracy should be >= 85% for \(testVideo.name). Got \(String(format: "%.1f%%", metrics.accuracy * 100))"
            )

            // Assert boundary error requirement
            XCTAssertLessThan(
                metrics.averageBoundaryError,
                1.0,
                "Average boundary error should be < 1s for \(testVideo.name). Got \(String(format: "%.2fs", metrics.averageBoundaryError))"
            )

            allResults.append((detectionResult, groundTruth))
        }

        // Batch evaluation
        if !allResults.isEmpty {
            let batchResult = AccuracyEvaluator.evaluateBatch(
                results: allResults,
                tolerance: 1.0
            )

            print("\n" + batchResult.report())

            // Overall accuracy assertion
            XCTAssertGreaterThanOrEqual(
                batchResult.combinedMetrics.accuracy,
                0.85,
                "Overall accuracy across all videos should be >= 85%"
            )
        }
    }

    /// Test processing speed requirement
    func testProcessingSpeed() async throws {
        let testVideos = try loadTestVideos()
        guard let testVideo = testVideos.first else {
            XCTSkip("No test videos found")
        }

        print("⏱️  Testing processing speed")
        print("   Target: 30-minute video in < 10 minutes")
        print("   Test video: \(testVideo.name)")

        // Measure processing time
        let startTime = Date()
        let result = try await engine.detectRallies(in: testVideo.url)
        let processingTime = Date().timeIntervalSince(startTime)

        print("   Processing time: \(String(format: "%.2fs", processingTime))")

        // For a 30-minute (1800s) video, processing should take < 600s (10 minutes)
        // Scale requirement based on actual video duration
        let videoDuration = try await getVideoDuration(testVideo.url)
        let expectedMaxTime = (videoDuration / 1800.0) * 600.0  // Scale to video length

        print("   Video duration: \(String(format: "%.1fs", videoDuration))")
        print("   Max allowed time: \(String(format: "%.2fs", expectedMaxTime))")

        XCTAssertLessThan(
            processingTime,
            expectedMaxTime,
            "Processing should complete within time budget"
        )

        // Print rate
        let processingRate = videoDuration / processingTime
        print("   Processing rate: \(String(format: "%.1fx", processingRate)) realtime")
    }

    /// Test excitement scoring is reasonable
    func testExcitementScoringIsReasonable() async throws {
        let testVideos = try loadTestVideos()
        guard let testVideo = testVideos.first else {
            XCTSkip("No test videos found")
        }

        print("⭐ Testing excitement scoring")

        let result = try await engine.detectRallies(in: testVideo.url)

        guard !result.rallies.isEmpty else {
            XCTSkip("No rallies detected in test video")
        }

        // Check all scores are in valid range
        for rally in result.rallies {
            XCTAssertGreaterThanOrEqual(rally.excitementScore, 0, "Score should be >= 0")
            XCTAssertLessThanOrEqual(rally.excitementScore, 100, "Score should be <= 100")
        }

        // Check scores are distributed (not all the same)
        let scores = result.rallies.map { $0.excitementScore }
        let uniqueScores = Set(scores)
        XCTAssertGreaterThan(uniqueScores.count, 1, "Scores should vary between rallies")

        // Top rally should have highest score
        if let topRally = result.topExcitingRally {
            let isTopScore = result.rallies.allSatisfy { $0.excitementScore <= topRally.excitementScore }
            XCTAssertTrue(isTopScore, "Top rally should have highest score")

            // Print scoring breakdown for top rally
            let breakdown = engine.generateScoringBreakdown(for: topRally)
            print(breakdown)
        }

        print("   Score range: \(String(format: "%.1f", scores.min() ?? 0)) - \(String(format: "%.1f", scores.max() ?? 0))")
        print("   Average score: \(String(format: "%.1f", scores.reduce(0, +) / Float(scores.count)))")
    }

    // MARK: - Component Tests

    /// Test audio analyzer independently
    func testAudioAnalyzer() async throws {
        let testVideos = try loadTestVideos()
        guard let testVideo = testVideos.first else {
            XCTSkip("No test videos found")
        }

        print("🔊 Testing AudioAnalyzer")

        let analyzer = AudioAnalyzer(config: config)
        let result = try await analyzer.analyze(videoURL: testVideo.url)

        XCTAssertGreaterThan(result.peaks.count, 0, "Should detect some audio peaks")
        XCTAssertGreaterThan(result.sampleRate, 0, "Should have valid sample rate")

        let hitSounds = result.peaks.filter { $0.isLikelyHitSound }
        print("   Total peaks: \(result.peaks.count)")
        print("   Hit sounds: \(hitSounds.count)")
        print("   Processing time: \(String(format: "%.2fs", result.processingTime))")
    }

    /// Test movement analyzer independently
    func testMovementAnalyzer() async throws {
        let testVideos = try loadTestVideos()
        guard let testVideo = testVideos.first else {
            XCTSkip("No test videos found")
        }

        print("🏃 Testing MovementAnalyzer")

        let analyzer = MovementAnalyzer(config: config)
        let result = try await analyzer.analyze(videoURL: testVideo.url)

        XCTAssertGreaterThan(result.frames.count, 0, "Should analyze some frames")

        let framesWithPerson = result.frames.filter { $0.hasPerson }
        print("   Total frames: \(result.frames.count)")
        print("   Frames with person: \(framesWithPerson.count)")
        print("   Processing time: \(String(format: "%.2fs", result.processingTime))")

        if let avgIntensity = result.frames.map({ $0.movementIntensity }).max() {
            print("   Peak intensity: \(String(format: "%.2f", avgIntensity))")
        }
    }

    // MARK: - Configuration Tests

    /// Test different config presets
    func testConfigurationPresets() async throws {
        let testVideos = try loadTestVideos()
        guard let testVideo = testVideos.first else {
            XCTSkip("No test videos found")
        }

        print("⚙️  Testing configuration presets")

        let configs: [(name: String, config: ThresholdConfig)] = [
            ("Default", ThresholdConfig()),
            ("High Precision", ThresholdConfig.highPrecision),
            ("Fast", ThresholdConfig.fast),
            ("Indoor", ThresholdConfig.indoor),
            ("Outdoor", ThresholdConfig.outdoor)
        ]

        for (name, testConfig) in configs {
            print("\n   Testing \(name) config...")
            let testEngine = RallyDetectionEngine(config: testConfig)

            let startTime = Date()
            let result = try await testEngine.detectRallies(in: testVideo.url)
            let time = Date().timeIntervalSince(startTime)

            print("     Rallies: \(result.totalRallies)")
            print("     Time: \(String(format: "%.2fs", time))")
        }
    }

    // MARK: - Helper Methods

    private func loadTestVideos() throws -> [VideoTestLoader.TestVideo] {
        // Try loading from test_videos folder in project root
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let testVideosDir = projectRoot.appendingPathComponent("test_videos")

        if FileManager.default.fileExists(atPath: testVideosDir.path) {
            print("📂 Loading test videos from: \(testVideosDir.path)")
            return try VideoTestLoader.loadTestVideos(from: testVideosDir)
        }

        // Fallback to default location
        return try VideoTestLoader.loadTestVideos()
    }

    private func getVideoDuration(_ url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}

// MARK: - Performance Tests

extension RallyDetectionTests {

    /// Measure overall processing performance
    func testOverallPerformance() throws {
        let testVideos = try loadTestVideos()
        guard let testVideo = testVideos.first else {
            XCTSkip("No test videos found")
        }

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                _ = try await engine.detectRallies(in: testVideo.url)
            }
        }
    }
}

// MARK: - Manual Test Utilities

extension RallyDetectionTests {

    /// Generate ground truth template for a video
    /// This is a helper for creating ground truth files
    func testGenerateGroundTruthTemplate() throws {
        let testVideos = try loadTestVideos()

        for testVideo in testVideos where !testVideo.hasGroundTruth {
            let template = GroundTruthParser.generateTemplate(for: testVideo.url)

            let outputURL = testVideo.url
                .deletingPathExtension()
                .appendingPathExtension("json")

            print("\n📝 Template for \(testVideo.name):")
            print(template)
            print("\n   Save to: \(outputURL.path)")
        }
    }
}

// Import AVFoundation for video duration
import AVFoundation
