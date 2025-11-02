//
//  AudioAnalyzer.swift
//  zacks_tennisUITests
//
//  Hybrid audio analysis: Peak detection + FFT spectral analysis
//

import Foundation
import AVFoundation
import Accelerate

/// Audio analyzer for detecting tennis hit sounds
class AudioAnalyzer {

    private let config: ThresholdConfig

    init(config: ThresholdConfig = ThresholdConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Analyze audio track of video to detect hit sounds
    /// - Parameter videoURL: URL of video file
    /// - Returns: Audio analysis result with detected peaks
    func analyze(videoURL: URL) async throws -> AudioAnalysisResult {
        let startTime = Date()

        // Step 1: Load audio track from video
        let asset = AVAsset(url: videoURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioAnalysisError.noAudioTrack
        }

        // Step 2: Extract audio samples
        let (samples, sampleRate) = try await extractAudioSamples(from: asset, track: audioTrack)

        // Step 3: Detect peaks using hybrid approach
        let peaks = detectPeaks(samples: samples, sampleRate: sampleRate)

        let processingTime = Date().timeIntervalSince(startTime)

        return AudioAnalysisResult(
            peaks: peaks,
            processingTime: processingTime,
            sampleRate: sampleRate
        )
    }

    // MARK: - Audio Extraction

    /// Extract audio samples from video asset
    private func extractAudioSamples(from asset: AVAsset, track: AVAssetTrack) async throws -> ([Float], Double) {
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioAnalysisError.cannotCreateReader
        }

        // Configure output settings for linear PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw AudioAnalysisError.cannotStartReading
        }

        var allSamples: [Float] = []
        var sampleRate: Double = 44100.0  // Default

        // Get actual sample rate from format description
        if let formatDescriptions = track.formatDescriptions as? [CMFormatDescription],
           let formatDescription = formatDescriptions.first {
            if let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = streamBasicDescription.pointee.mSampleRate
            }
        }

        // Read all samples
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let samples = extractSamples(from: sampleBuffer) {
                allSamples.append(contentsOf: samples)
            }
            CMSampleBufferInvalidate(sampleBuffer)
        }

        reader.cancelReading()

        return (allSamples, sampleRate)
    }

    /// Extract float samples from CMSampleBuffer
    private func extractSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return nil
        }

        // Convert Int16 samples to Float (-1.0 to 1.0)
        let sampleCount = length / MemoryLayout<Int16>.size
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Pointer in
            for i in 0..<sampleCount {
                floatSamples[i] = Float(int16Pointer[i]) / Float(Int16.max)
            }
        }

        return floatSamples
    }

    // MARK: - Peak Detection (Hybrid Approach)

    /// Detect audio peaks using combined peak detection + FFT analysis
    private func detectPeaks(samples: [Float], sampleRate: Double) -> [AudioPeak] {
        var peaks: [AudioPeak] = []

        let hopSize = config.audioHopSize
        let windowSize = config.fftWindowSize
        let windowDuration = TimeInterval(windowSize) / sampleRate

        // Process audio in sliding windows
        var position = 0
        while position + windowSize <= samples.count {
            let window = Array(samples[position..<position + windowSize])
            let timestamp = TimeInterval(position) / sampleRate

            // Method 1: Simple peak detection (fast)
            let peakAmplitude = findPeakAmplitude(in: window)

            // Method 2: FFT spectral analysis (more accurate)
            let (dominantFrequency, spectralEnergy) = analyzeSpectrum(window: window, sampleRate: sampleRate)

            // Hybrid decision: Combine both methods
            if peakAmplitude > config.audioAmplitudeThreshold {
                // Check if frequency is in expected range for tennis hits
                let frequencyInRange = config.hitSoundFrequencyRange.contains(dominantFrequency)

                // Calculate confidence based on both methods
                let amplitudeScore = min(peakAmplitude * 2.0, 1.0)  // Normalize
                let frequencyScore: Float = frequencyInRange ? 1.0 : 0.3
                let energyScore = min(spectralEnergy, 1.0)

                let confidence = (amplitudeScore * 0.4 + frequencyScore * 0.4 + energyScore * 0.2)

                if confidence >= config.audioPeakConfidence {
                    let peak = AudioPeak(
                        timestamp: timestamp,
                        amplitude: peakAmplitude,
                        frequency: dominantFrequency,
                        confidence: confidence,
                        spectralEnergy: spectralEnergy
                    )
                    peaks.append(peak)
                }
            }

            position += hopSize
        }

        // Post-process: Remove peaks too close together (debounce)
        return debouncePeaks(peaks, minimumInterval: 0.1)
    }

    /// Find peak amplitude in audio window
    private func findPeakAmplitude(in window: [Float]) -> Float {
        // Use RMS (Root Mean Square) for better noise immunity
        // Also track peak for sharp transients
        var sumSquares: Float = 0
        var maxAbsolute: Float = 0

        for sample in window {
            let absolute = abs(sample)
            sumSquares += sample * sample
            maxAbsolute = max(maxAbsolute, absolute)
        }

        let rms = sqrt(sumSquares / Float(window.count))

        // Combine RMS and peak (RMS helps with noise, peak helps with transients)
        return rms * 0.6 + maxAbsolute * 0.4
    }

    /// Analyze frequency spectrum using FFT
    private func analyzeSpectrum(window: [Float], sampleRate: Double) -> (frequency: Float, energy: Float) {
        let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(config.fftWindowSize))), Int32(kFFTRadix2))
        defer { vDSP_destroy_fftsetup(fftSetup) }

        guard fftSetup != nil else {
            return (0, 0)
        }

        let halfSize = config.fftWindowSize / 2
        var realParts = [Float](repeating: 0, count: halfSize)
        var imagParts = [Float](repeating: 0, count: halfSize)

        // Apply Hanning window to reduce spectral leakage
        var windowedSamples = [Float](repeating: 0, count: config.fftWindowSize)
        var hanningWindow = [Float](repeating: 0, count: config.fftWindowSize)
        vDSP_hann_window(&hanningWindow, vDSP_Length(config.fftWindowSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(window, 1, hanningWindow, 1, &windowedSamples, 1, vDSP_Length(config.fftWindowSize))

        // Prepare split complex for FFT
        windowedSamples.withUnsafeBytes { samplesPtr in
            realParts.withUnsafeMutableBytes { realPtr in
                imagParts.withUnsafeMutableBytes { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.bindMemory(to: Float.self).baseAddress!,
                        imagp: imagPtr.bindMemory(to: Float.self).baseAddress!
                    )

                    // Perform FFT
                    samplesPtr.bindMemory(to: Float.self).baseAddress.map { basePtr in
                        vDSP_ctoz(
                            UnsafePointer<DSPComplex>(OpaquePointer(basePtr)),
                            2,
                            &splitComplex,
                            1,
                            vDSP_Length(halfSize)
                        )
                    }

                    vDSP_fft_zrip(
                        fftSetup!,
                        &splitComplex,
                        1,
                        vDSP_Length(log2(Float(config.fftWindowSize))),
                        FFTDirection(FFT_FORWARD)
                    )
                }
            }
        }

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&DSPSplitComplex(realp: &realParts, imagp: &imagParts), 1, &magnitudes, 1, vDSP_Length(halfSize))

        // Find dominant frequency in tennis hit range
        let minBin = Int(config.hitSoundFrequencyRange.lowerBound * Float(config.fftWindowSize) / Float(sampleRate))
        let maxBin = Int(config.hitSoundFrequencyRange.upperBound * Float(config.fftWindowSize) / Float(sampleRate))

        let validRange = max(0, minBin)..<min(halfSize, maxBin)
        guard !validRange.isEmpty else { return (0, 0) }

        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0

        vDSP_maxvi(
            Array(magnitudes[validRange]),
            1,
            &maxMagnitude,
            &maxIndex,
            vDSP_Length(validRange.count)
        )

        let actualIndex = validRange.lowerBound + Int(maxIndex)
        let dominantFrequency = Float(actualIndex) * Float(sampleRate) / Float(config.fftWindowSize)

        // Calculate spectral energy in target frequency range
        let energyInRange = magnitudes[validRange].reduce(0, +) / Float(validRange.count)
        let normalizedEnergy = min(sqrt(energyInRange) / 100.0, 1.0)  // Normalize

        return (dominantFrequency, normalizedEnergy)
    }

    /// Remove peaks that are too close together (debouncing)
    private func debouncePeaks(_ peaks: [AudioPeak], minimumInterval: TimeInterval) -> [AudioPeak] {
        var debouncedPeaks: [AudioPeak] = []
        var lastPeakTime: TimeInterval = -.infinity

        for peak in peaks.sorted(by: { $0.timestamp < $1.timestamp }) {
            if peak.timestamp - lastPeakTime >= minimumInterval {
                debouncedPeaks.append(peak)
                lastPeakTime = peak.timestamp
            } else {
                // If peaks are close, keep the one with higher confidence
                if let lastIndex = debouncedPeaks.indices.last,
                   peak.confidence > debouncedPeaks[lastIndex].confidence {
                    debouncedPeaks[lastIndex] = peak
                }
            }
        }

        return debouncedPeaks
    }
}

// MARK: - Errors

enum AudioAnalysisError: Error, CustomStringConvertible {
    case noAudioTrack
    case cannotCreateReader
    case cannotStartReading
    case invalidSampleData

    var description: String {
        switch self {
        case .noAudioTrack:
            return "Video has no audio track"
        case .cannotCreateReader:
            return "Cannot create AVAssetReader"
        case .cannotStartReading:
            return "Cannot start reading audio data"
        case .invalidSampleData:
            return "Invalid audio sample data"
        }
    }
}
