//
//  SimpleHitDetector.swift
//  zacks_tennis
//
//  极简网球击球声检测器
//  三阶段检测：EPD 能量峰值 → 频率验证 → 置信度评分
//  4 维特征：energyRatio, rms, frequencyMatch, peakSharpness
//

import Foundation
import AVFoundation
import Accelerate

// MARK: - SimpleHitDetector

/// 极简网球击球声检测器
/// 使用 EPD (Energy Peak Detection) + 频率验证的两阶段检测
actor SimpleHitDetector: AudioAnalyzing {

    // MARK: - Configuration

    /// 检测配置
    struct Config {
        /// EPD 能量突变阈值（当前能量/前帧能量）
        let energyRatio: Double

        /// 最小置信度阈值
        let confidenceThreshold: Double

        /// 最小峰值间隔（秒）
        let minPeakInterval: Double

        /// 最小有效频率（Hz）- 网球击球声下限
        let minFrequency: Double

        /// 最大有效频率（Hz）- 网球击球声上限
        let maxFrequency: Double

        /// 短窗口大小（毫秒）- EPD 检测窗口
        let windowMs: Double

        /// FFT 大小
        let fftSize: Int

        /// 预设名称
        var presetName: String {
            switch (energyRatio, confidenceThreshold) {
            case (2.5, 0.5): return "default"
            case (2.0, 0.4): return "sensitive"
            case (2.2, 0.45): return "mobile"
            default: return "custom"
            }
        }

        // MARK: - 配置预设

        /// 默认配置（平衡，已优化召回率）
        static let `default` = Config(
            energyRatio: 2.0,              // 从 2.5 降低到 2.0
            confidenceThreshold: 0.35,     // 从 0.5 降低到 0.35
            minPeakInterval: 0.12,         // 从 0.15 降低到 0.12
            minFrequency: 500,             // 保留用于诊断（不再用于过滤）
            maxFrequency: 4000,            // 保留用于诊断（不再用于过滤）
            windowMs: 15.0,
            fftSize: 256
        )

        /// 高召回率配置（更敏感）
        static let sensitive = Config(
            energyRatio: 1.8,              // 从 2.0 降低到 1.8
            confidenceThreshold: 0.30,     // 从 0.4 降低到 0.30
            minPeakInterval: 0.08,         // 从 0.10 降低到 0.08
            minFrequency: 400,
            maxFrequency: 5000,
            windowMs: 15.0,
            fftSize: 256
        )

        /// 手机录制配置
        static let mobile = Config(
            energyRatio: 1.9,              // 从 2.2 降低到 1.9
            confidenceThreshold: 0.32,     // 从 0.45 降低到 0.32
            minPeakInterval: 0.10,         // 从 0.12 降低到 0.10
            minFrequency: 500,
            maxFrequency: 4500,
            windowMs: 15.0,
            fftSize: 256
        )

        /// 从 AudioAnalysisConfiguration 转换
        static func from(_ audioConfig: AudioAnalysisConfiguration) -> Config {
            return Config(
                energyRatio: audioConfig.epdEnergyRatio,
                confidenceThreshold: audioConfig.minimumConfidence,
                minPeakInterval: audioConfig.minimumPeakInterval,
                minFrequency: 500,
                maxFrequency: 4000,
                windowMs: audioConfig.shortWindowMs,
                fftSize: audioConfig.fastFFTSize
            )
        }
    }

    // MARK: - Properties

    private var config: Config
    private var diagnosticCollector: SimpleDiagnosticCollector?

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - AudioAnalyzing Protocol

    /// 分析音频轨道
    func analyzeAudio(from asset: AVAsset, timeRange: CMTimeRange) async throws -> AudioAnalysisResult {
        // 1. 提取音频样本
        let (samples, sampleRate) = try await extractAudioSamples(from: asset, timeRange: timeRange)

        guard !samples.isEmpty else {
            return AudioAnalysisResult(hitSounds: [])
        }

        // 2. 三阶段检测
        let peaks = detectHitSounds(samples: samples, sampleRate: sampleRate, timeOffset: timeRange.start.seconds)

        return AudioAnalysisResult(hitSounds: peaks)
    }

    /// 并行分析（对于短音频，直接调用普通分析）
    func analyzeAudioParallel(from asset: AVAsset, timeRange: CMTimeRange) async throws -> AudioAnalysisResult {
        // 对于长音频，分段并行处理
        let duration = timeRange.duration.seconds
        if duration > 60 {
            return try await analyzeAudioInChunks(from: asset, timeRange: timeRange, chunkDuration: 30.0)
        }
        return try await analyzeAudio(from: asset, timeRange: timeRange)
    }

    /// 更新配置
    func updateConfig(_ newConfig: AudioAnalysisConfiguration) async {
        self.config = Config.from(newConfig)
    }

    /// 启用诊断模式
    func enableDiagnosticMode(videoInfo: VideoDiagnosticInfo) async {
        diagnosticCollector = SimpleDiagnosticCollector(videoInfo: videoInfo, config: config)
    }

    /// 禁用诊断模式
    func disableDiagnosticMode() async {
        diagnosticCollector = nil
    }

    /// 获取诊断数据
    func getDiagnosticData() async -> AudioDiagnosticData? {
        return diagnosticCollector?.generateDiagnosticData()
    }

    // MARK: - Core Detection Algorithm

    /// 两阶段击球声检测（简化版）
    /// Stage 1: EPD 能量峰值检测
    /// Stage 2: 置信度评分与过滤
    private func detectHitSounds(samples: [Float], sampleRate: Double, timeOffset: Double) -> [AudioPeak] {
        let windowSize = Int(sampleRate * config.windowMs / 1000.0)
        let hopSize = windowSize / 4  // 75% overlap

        guard samples.count > windowSize * 2 else {
            return []
        }

        // Stage 1: EPD 能量峰值检测
        let candidates = detectEnergyPeaks(
            samples: samples,
            sampleRate: sampleRate,
            windowSize: windowSize,
            hopSize: hopSize,
            timeOffset: timeOffset
        )

        // Stage 2: 置信度评分与过滤（移除频率验证，简化为 3 维特征）
        let finalPeaks = scoreAndFilter(
            candidates: candidates,
            samples: samples,
            sampleRate: sampleRate
        )

        return finalPeaks
    }

    // MARK: - Stage 1: EPD 能量峰值检测

    private func detectEnergyPeaks(
        samples: [Float],
        sampleRate: Double,
        windowSize: Int,
        hopSize: Int,
        timeOffset: Double
    ) -> [PeakCandidate] {
        var candidates: [PeakCandidate] = []
        var previousEnergy: Double = 0
        var energyHistory: [Double] = []

        let numWindows = (samples.count - windowSize) / hopSize

        for i in 0..<numWindows {
            let startIndex = i * hopSize
            let endIndex = min(startIndex + windowSize, samples.count)
            let window = Array(samples[startIndex..<endIndex])

            // 计算短时能量
            var sumSquares: Float = 0
            vDSP_svesq(window, 1, &sumSquares, vDSP_Length(window.count))
            let energy = Double(sumSquares) / Double(window.count)

            // 计算 RMS
            let rms = sqrt(energy)

            // 计算能量比率
            let energyRatio = previousEnergy > 1e-10 ? energy / previousEnergy : 0

            // 检测能量突变
            if energyRatio > config.energyRatio && energy > 0.001 {
                let timestamp = timeOffset + Double(startIndex) / sampleRate

                // 计算峰值幅度
                let peakAmplitude = Double(window.map { abs($0) }.max() ?? 0)

                // 计算峰值尖锐度（局部对比度）
                let localMean = energyHistory.isEmpty ? energy : energyHistory.reduce(0, +) / Double(energyHistory.count)
                let sharpness = localMean > 1e-10 ? energy / localMean : 1.0

                let candidate = PeakCandidate(
                    timestamp: timestamp,
                    sampleIndex: startIndex,
                    energy: energy,
                    energyRatio: energyRatio,
                    rms: rms,
                    peakAmplitude: peakAmplitude,
                    sharpness: sharpness,
                    dominantFrequency: nil,
                    frequencyValid: true,
                    confidence: 0
                )
                candidates.append(candidate)

                // 记录诊断数据
                diagnosticCollector?.recordCandidate(candidate, stage: "EPD")
            }

            // 更新历史
            energyHistory.append(energy)
            if energyHistory.count > 10 {
                energyHistory.removeFirst()
            }
            previousEnergy = energy
        }

        print("🎯 [SimpleHitDetector] Stage 1 EPD: 检测到 \(candidates.count) 个能量峰值")
        return candidates
    }

    // MARK: - Stage 2: 频率范围验证

    private func validateFrequencyRange(
        candidates: [PeakCandidate],
        samples: [Float],
        sampleRate: Double
    ) -> [PeakCandidate] {
        var validatedCandidates: [PeakCandidate] = []

        for var candidate in candidates {
            // 提取峰值附近的样本进行 FFT
            let windowSize = config.fftSize
            let startIndex = max(0, candidate.sampleIndex - windowSize / 2)
            let endIndex = min(samples.count, startIndex + windowSize)

            guard endIndex - startIndex >= windowSize else {
                // 样本不足，跳过频率验证
                validatedCandidates.append(candidate)
                continue
            }

            let window = Array(samples[startIndex..<startIndex + windowSize])

            // 计算主频率
            let dominantFreq = calculateDominantFrequency(samples: window, sampleRate: sampleRate)
            candidate.dominantFrequency = dominantFreq

            // 验证频率范围
            let isValid = dominantFreq >= config.minFrequency && dominantFreq <= config.maxFrequency
            candidate.frequencyValid = isValid

            if isValid {
                validatedCandidates.append(candidate)
                diagnosticCollector?.recordCandidate(candidate, stage: "FreqValidation")
            } else {
                diagnosticCollector?.recordRejection(candidate, reason: "频率不在有效范围 (\(Int(dominantFreq)) Hz)")
            }
        }

        print("🎯 [SimpleHitDetector] Stage 2 频率验证: \(validatedCandidates.count)/\(candidates.count) 通过")
        return validatedCandidates
    }

    // MARK: - Stage 2: 置信度评分与过滤

    private func scoreAndFilter(
        candidates: [PeakCandidate],
        samples: [Float],
        sampleRate: Double
    ) -> [AudioPeak] {
        var scoredCandidates: [PeakCandidate] = []

        // 计算全局统计量用于归一化
        let rmsValues = candidates.map { $0.rms }
        let maxRMS = rmsValues.max() ?? 1.0

        for var candidate in candidates {
            // 3 维特征评分（移除频率验证）
            let energyScore = min(candidate.energyRatio / 5.0, 1.0) * 0.45       // 能量突变比 (45%)
            let rmsScore = min(candidate.rms / maxRMS, 1.0) * 0.30               // RMS 强度 (30%)
            let sharpnessScore = min(candidate.sharpness / 3.0, 1.0) * 0.25      // 峰值尖锐度 (25%)

            let confidence = energyScore + rmsScore + sharpnessScore
            candidate.confidence = confidence

            if confidence >= config.confidenceThreshold {
                scoredCandidates.append(candidate)
                diagnosticCollector?.recordCandidate(candidate, stage: "Scoring")
            } else {
                diagnosticCollector?.recordRejection(candidate, reason: "置信度过低 (\(String(format: "%.2f", confidence)))")
            }
        }

        // 合并过近的峰值
        let mergedCandidates = mergePeaks(scoredCandidates)

        print("🎯 [SimpleHitDetector] Stage 2 置信度过滤: \(mergedCandidates.count)/\(candidates.count) 通过")

        // 转换为 AudioPeak
        return mergedCandidates.map { candidate in
            AudioPeak(
                time: candidate.timestamp,
                amplitude: candidate.peakAmplitude,
                confidence: candidate.confidence
            )
        }
    }

    // MARK: - Helper Methods

    /// 计算主频率（简化 FFT）
    private func calculateDominantFrequency(samples: [Float], sampleRate: Double) -> Double {
        let n = samples.count
        guard n > 0 && (n & (n - 1)) == 0 else {
            // 非 2 的幂，返回默认值
            return 1000.0
        }

        // 使用 Accelerate 进行 FFT
        let log2n = vDSP_Length(log2(Double(n)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return 1000.0
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = samples
        var imagPart = [Float](repeating: 0, count: n)
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

        // 执行 FFT
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // 计算幅度谱
        var magnitudes = [Float](repeating: 0, count: n / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))

        // 找到最大幅度的频率 bin（跳过 DC 分量）
        var maxMag: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes[1], 1, &maxMag, &maxIndex, vDSP_Length(magnitudes.count - 1))

        // 转换为频率
        let frequencyResolution = sampleRate / Double(n)
        let dominantFrequency = Double(maxIndex + 1) * frequencyResolution

        return dominantFrequency
    }

    /// 合并过近的峰值
    private func mergePeaks(_ candidates: [PeakCandidate]) -> [PeakCandidate] {
        guard !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { $0.timestamp < $1.timestamp }
        var merged: [PeakCandidate] = []

        for candidate in sorted {
            if let last = merged.last {
                if candidate.timestamp - last.timestamp < config.minPeakInterval {
                    // 保留置信度更高的
                    if candidate.confidence > last.confidence {
                        merged.removeLast()
                        merged.append(candidate)
                    }
                    // 否则跳过当前候选
                } else {
                    merged.append(candidate)
                }
            } else {
                merged.append(candidate)
            }
        }

        return merged
    }

    /// 提取音频样本
    private func extractAudioSamples(from asset: AVAsset, timeRange: CMTimeRange) async throws -> ([Float], Double) {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw AudioAnalyzerError.noAudioTrack
        }

        let assetReader = try AVAssetReader(asset: asset)
        assetReader.timeRange = timeRange

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        assetReader.add(trackOutput)

        guard assetReader.startReading() else {
            throw AudioAnalyzerError.readFailed
        }

        var samples: [Float] = []
        let sampleRate: Double = 44100.0

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let dataPointer = dataPointer {
                let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
                let floatCount = length / MemoryLayout<Float>.size
                samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))
            }
        }

        return (samples, sampleRate)
    }

    /// 分块并行分析
    private func analyzeAudioInChunks(from asset: AVAsset, timeRange: CMTimeRange, chunkDuration: Double) async throws -> AudioAnalysisResult {
        let totalDuration = timeRange.duration.seconds
        let startTime = timeRange.start.seconds
        var allPeaks: [AudioPeak] = []

        var currentTime = startTime
        while currentTime < startTime + totalDuration {
            let chunkEnd = min(currentTime + chunkDuration, startTime + totalDuration)
            let chunkRange = CMTimeRange(
                start: CMTime(seconds: currentTime, preferredTimescale: 600),
                end: CMTime(seconds: chunkEnd, preferredTimescale: 600)
            )

            let result = try await analyzeAudio(from: asset, timeRange: chunkRange)
            allPeaks.append(contentsOf: result.hitSounds)

            currentTime = chunkEnd
        }

        // 合并跨块边界的峰值
        let mergedPeaks = mergeFinalPeaks(allPeaks)
        return AudioAnalysisResult(hitSounds: mergedPeaks)
    }

    /// 合并最终峰值列表
    private func mergeFinalPeaks(_ peaks: [AudioPeak]) -> [AudioPeak] {
        guard !peaks.isEmpty else { return [] }

        let sorted = peaks.sorted { $0.time < $1.time }
        var merged: [AudioPeak] = []

        for peak in sorted {
            if let last = merged.last {
                if peak.time - last.time < config.minPeakInterval {
                    if peak.confidence > last.confidence {
                        merged.removeLast()
                        merged.append(peak)
                    }
                } else {
                    merged.append(peak)
                }
            } else {
                merged.append(peak)
            }
        }

        return merged
    }
}

// MARK: - Peak Candidate

/// 峰值候选数据
private struct PeakCandidate {
    let timestamp: Double
    let sampleIndex: Int
    let energy: Double
    let energyRatio: Double
    let rms: Double
    let peakAmplitude: Double
    let sharpness: Double
    var dominantFrequency: Double?
    var frequencyValid: Bool
    var confidence: Double
}

// MARK: - Simple Diagnostic Collector

/// 简化的诊断数据收集器
private class SimpleDiagnosticCollector {
    let videoInfo: VideoDiagnosticInfo
    let config: SimpleHitDetector.Config

    var allCandidates: [CandidatePeakData] = []
    var finalPeaks: [CandidatePeakData] = []
    var rejectionReasons: [String: Int] = [:]

    // 统计计数器
    var epdCount = 0
    var freqValidatedCount = 0
    var scoredCount = 0

    init(videoInfo: VideoDiagnosticInfo, config: SimpleHitDetector.Config) {
        self.videoInfo = videoInfo
        self.config = config
    }

    func recordCandidate(_ candidate: PeakCandidate, stage: String) {
        switch stage {
        case "EPD":
            epdCount += 1
        case "FreqValidation":
            freqValidatedCount += 1
        case "Scoring":
            scoredCount += 1
            // 记录最终通过的候选
            let peakData = createPeakData(from: candidate, passed: true, reason: nil, stage: stage)
            finalPeaks.append(peakData)
        default:
            break
        }

        let peakData = createPeakData(from: candidate, passed: stage == "Scoring", reason: nil, stage: stage)
        allCandidates.append(peakData)
    }

    func recordRejection(_ candidate: PeakCandidate, reason: String) {
        rejectionReasons[reason, default: 0] += 1
        let peakData = createPeakData(from: candidate, passed: false, reason: reason, stage: "Rejected")
        allCandidates.append(peakData)
    }

    private func createPeakData(from candidate: PeakCandidate, passed: Bool, reason: String?, stage: String) -> CandidatePeakData {
        return CandidatePeakData(
            time: candidate.timestamp,
            amplitude: candidate.peakAmplitude,
            rms: candidate.rms,
            duration: 0.015,  // 15ms 窗口
            confidence: candidate.confidence,
            confidenceBreakdown: ConfidenceBreakdown(
                amplitudeScore: min(candidate.energyRatio / 5.0, 1.0) * 0.35,
                crestFactorScore: 0,
                energyConcentrationScore: 0,
                frequencyRangeScore: candidate.frequencyValid ? 0.25 : 0,
                highFreqEnergyScore: 0,
                otherFeaturesScore: min(candidate.sharpness / 3.0, 1.0) * 0.15
            ),
            spectralFeatures: SpectralFeatures(
                dominantFrequency: candidate.dominantFrequency ?? 0,
                spectralCentroid: 0,
                spectralRolloff: 0,
                lowFreqEnergy: 0,
                primaryHitRangeEnergy: 0,
                highFreqEnergy: 0,
                mfccMean: nil
            ),
            passedFiltering: passed,
            rejectionReason: reason,
            rejectionStage: passed ? nil : stage
        )
    }

    func generateDiagnosticData() -> AudioDiagnosticData {
        let audioFeatures = AudioGlobalFeatures(
            overallRMSMean: 0,
            overallRMSStdDev: 0,
            overallRMSMax: 0,
            overallRMSMedian: 0,
            overallRMSP90: 0,
            maxPeakAmplitude: allCandidates.map { $0.amplitude }.max() ?? 0,
            medianPeakAmplitude: 0,
            dominantFrequencyRange: "\(Int(config.minFrequency))-\(Int(config.maxFrequency)) Hz",
            estimatedSNR: nil
        )

        let stats = FilteringStatistics(
            totalCandidates: allCandidates.count,
            passedAmplitudeThreshold: epdCount,
            passedDurationCheck: epdCount,
            passedConfidenceThreshold: freqValidatedCount,
            passedAdaptiveFiltering: scoredCount,
            afterPostProcessing: finalPeaks.count,
            finalCount: finalPeaks.count,
            rejectionReasons: rejectionReasons,
            averageConfidence: finalPeaks.isEmpty ? 0 : finalPeaks.map { $0.confidence }.reduce(0, +) / Double(finalPeaks.count),
            medianConfidence: 0
        )

        let configSnapshot = AudioConfigSnapshot(
            peakThreshold: config.energyRatio / 10.0,
            minimumConfidence: config.confidenceThreshold,
            minimumPeakInterval: config.minPeakInterval,
            presetName: config.presetName
        )

        return AudioDiagnosticData(
            videoInfo: videoInfo,
            audioFeatures: audioFeatures,
            allCandidatePeaks: allCandidates,
            finalPeaks: finalPeaks,
            filteringStats: stats,
            rmsTimeSeries: [],
            spectralSamples: nil,
            configuration: configSnapshot,
            timestamp: Date()
        )
    }
}
