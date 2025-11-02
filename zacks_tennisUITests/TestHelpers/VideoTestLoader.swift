//
//  VideoTestLoader.swift
//  zacks_tennisUITests
//
//  Load test videos for rally detection validation
//

import Foundation
import XCTest

/// Loads test videos for algorithm validation
class VideoTestLoader {

    /// Test video information
    struct TestVideo {
        let url: URL
        let name: String
        let duration: TimeInterval
        let groundTruthURL: URL?  // Optional ground truth annotation file

        var hasGroundTruth: Bool { groundTruthURL != nil }
    }

    // MARK: - Public API

    /// Load all test videos from a directory
    /// - Parameter directory: Directory containing test videos (default: Documents/TestVideos)
    /// - Returns: Array of test videos
    static func loadTestVideos(from directory: URL? = nil) throws -> [TestVideo] {
        let testDir = directory ?? defaultTestDirectory()

        guard FileManager.default.fileExists(atPath: testDir.path) else {
            print("⚠️  Test video directory not found: \(testDir.path)")
            print("   Please add test videos to this directory")
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: testDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let videoExtensions = ["mp4", "mov", "m4v"]
        let videoURLs = contents.filter { url in
            videoExtensions.contains(url.pathExtension.lowercased())
        }

        var testVideos: [TestVideo] = []

        for videoURL in videoURLs {
            // Look for corresponding ground truth file
            let baseName = videoURL.deletingPathExtension().lastPathComponent
            let groundTruthURL = testDir
                .appendingPathComponent(baseName)
                .appendingPathExtension("json")

            let hasGroundTruth = FileManager.default.fileExists(atPath: groundTruthURL.path)

            let video = TestVideo(
                url: videoURL,
                name: baseName,
                duration: 0,  // Could be extracted if needed
                groundTruthURL: hasGroundTruth ? groundTruthURL : nil
            )

            testVideos.append(video)
        }

        print("📹 Loaded \(testVideos.count) test videos")
        print("   \(testVideos.filter { $0.hasGroundTruth }.count) have ground truth annotations")

        return testVideos
    }

    /// Load a specific test video by name
    /// - Parameter name: Name of the test video (without extension)
    /// - Returns: Test video if found
    static func loadTestVideo(named name: String) throws -> TestVideo? {
        let videos = try loadTestVideos()
        return videos.first { $0.name == name }
    }

    /// Load test video from user-provided path
    /// - Parameter path: File path to video
    /// - Returns: Test video
    static func loadTestVideo(at path: String) -> TestVideo {
        let url = URL(fileURLWithPath: path)
        let name = url.deletingPathExtension().lastPathComponent

        // Look for ground truth file in same directory
        let groundTruthURL = url.deletingPathExtension().appendingPathExtension("json")
        let hasGroundTruth = FileManager.default.fileExists(atPath: groundTruthURL.path)

        return TestVideo(
            url: url,
            name: name,
            duration: 0,
            groundTruthURL: hasGroundTruth ? groundTruthURL : nil
        )
    }

    // MARK: - Directory Management

    /// Get default test video directory
    static func defaultTestDirectory() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: documentsPath).appendingPathComponent("TestVideos")
    }

    /// Create test video directory if it doesn't exist
    static func ensureTestDirectoryExists() throws {
        let testDir = defaultTestDirectory()
        if !FileManager.default.fileExists(atPath: testDir.path) {
            try FileManager.default.createDirectory(
                at: testDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("✅ Created test video directory: \(testDir.path)")
        }
    }

    /// Get README for test video directory
    static func printTestDirectoryInfo() {
        let testDir = defaultTestDirectory()
        print("""

        📂 Test Video Directory
        ═══════════════════════════════════════════
        Location: \(testDir.path)

        To add test videos:
        1. Place .mp4, .mov, or .m4v files in this directory
        2. Optionally add ground truth JSON files with same name
           (e.g., video.mp4 → video.json)

        Ground Truth JSON Format:
        {
          "video": "video.mp4",
          "rallies": [
            {
              "startTime": 12.5,
              "endTime": 28.3,
              "excitementScore": 75  // optional
            }
          ]
        }
        ═══════════════════════════════════════════

        """)
    }
}
