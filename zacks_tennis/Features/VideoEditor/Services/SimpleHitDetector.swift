//
//  SimpleHitDetector.swift
//  zacks_tennis
//
//  优化版网球击球声检测器
//  三阶段检测：EPD 能量峰值 → 频谱分析 → 8 维置信度评分
//  特征：energyRatio, rms, sharpness, frequencyMatch, highFreqEnergyRatio,
//        spectralCentroid, spectralFlux, crestFactor + 攻击时间 + 自适应噪声底
//

import Foundation
import AVFoundation
import Accelerate

// MARK: - SimpleHitDetector

/// 优化版网球击球声检测器
/// 使用 EPD (Energy Peak Detection) + 频谱分析 + 8 维置信度评分
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
            energyRatio: 2.0,
            confidenceThreshold: 0.35,
            minPeakInterval: 0.12,
            minFrequency: 500,
            maxFrequency: 4000,
            windowMs: 15.0,
            fftSize: 1024              // 从 256 升级到 1024，频率分辨率 ~43Hz
        )

        /// 高召回率配置（更敏感）
        static let sensitive = Config(
            energyRatio: 1.8,
            confidenceThreshold: 0.30,
            minPeakInterval: 0.08,
            minFrequency: 400,
            maxFrequency: 5000,
            windowMs: 15.0,
            fftSize: 1024
        )

        /// 手机录制配置
        static let mobile = Config(
            energyRatio: 1.9,
            confidenceThreshold: 0.32,
            minPeakInterval: 0.10,
            minFrequency: 500,
            maxFrequency: 4500,
            windowMs: 15.0,
            fftSize: 1024
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
                fftSize: audioConfig.fineFFTSize  // 使用 fineFFTSize (1024) 而非 fastFFTSize (256)
            )
        }
    }

    // MARK: - Spectral Features (Internal)

    /// 频谱分析结果
    private struct DetectedSpectralFeatures {
        let dominantFrequency: Double
        let lowBandEnergy: Double       // 200-500Hz：球体共振
        let midBandEnergy: Double       // 500-2000Hz：弦-球交互
        let highBandEnergy: Double      // 2000-5000Hz：撞击瞬态
        let highFreqEnergyRatio: Double // (mid+high) / total
        let spectralCentroid: Double    // 能量加权平均频率
        let spectralFlux: Double        // 相邻频率 bin 差异
    }

    // MARK: - Properties

    private var config: Config
    private var diagnosticCollector: SimpleDiagnosticCollector?

    // FFT 缓存（避免重复创建/销毁）
    private var cachedFFTSetup: (setup: FFTSetup, log2n: vDSP_Length)?
    private var cachedHannWindow: [Float]?
    private var cachedHannWindowSize: Int = 0

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Cleanup

    /// 清理 FFT 资源
    private func cleanupFFT() {
        if let cached = cachedFFTSetup {
            vDSP_destroy_fftsetup(cached.setup)
            cachedFFTSetup = nil
        }
    }

    // MARK: - AudioAnalyzing Protocol

    /// 分析音频轨道
    func analyzeAudio(from asset: AVAsset, timeRange: CMTimeRange) async throws -> AudioAnalysisResult {
        let (samples, sampleRate) = try await extractAudioSamples(from: asset, timeRange: timeRange)

        guard !samples.isEmpty else {
            return AudioAnalysisResult(hitSounds: [])
        }

        let peaks = detectHitSounds(samples: samples, sampleRate: sampleRate, timeOffset: timeRange.start.seconds)

        return AudioAnalysisResult(hitSounds: peaks)
    }

    /// 并行分析（对于短音频，直接调用普通分析）
    func analyzeAudioParallel(from asset: AVAsset, timeRange: CMTimeRange) async throws -> AudioAnalysisResult {
        let duration = timeRange.duration.seconds
        if duration > 60 {
            return try await analyzeAudioInChunks(from: asset, timeRange: timeRange, chunkDuration: 30.0)
        }
        return try await analyzeAudio(from: asset, timeRange: timeRange)
    }

    /// 更新配置
    func updateConfig(_ newConfig: AudioAnalysisConfiguration) async {
        self.config = Config.from(newConfig)
        // FFT 大小可能变化，清理缓存
        cleanupFFT()
        cachedHannWindow = nil
        cachedHannWindowSize = 0
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

    /// 三阶段击球声检测
    /// Stage 1: EPD 能量峰值检测（含自适应噪声底）
    /// Stage 2: 频谱分析 + 攻击时间计算
    /// Stage 3: 8 维置信度评分与过滤
    private func detectHitSounds(samples: [Float], sampleRate: Double, timeOffset: Double) -> [AudioPeak] {
        let windowSize = Int(sampleRate * config.windowMs / 1000.0)
        let hopSize = windowSize / 4  // 75% overlap

        guard samples.count > windowSize * 2 else {
            return []
        }

        // Stage 1: EPD 能量峰值检测（含自适应噪声底）
        let candidates = detectEnergyPeaks(
            samples: samples,
            sampleRate: sampleRate,
            windowSize: windowSize,
            hopSize: hopSize,
            timeOffset: timeOffset
        )

        // Stage 2 + 3: 频谱分析 + 8 维置信度评分与过滤
        let finalPeaks = analyzeAndScore(
            candidates: candidates,
            samples: samples,
            sampleRate: sampleRate
        )

        return finalPeaks
    }

    // MARK: - Stage 1: EPD 能量峰值检测（含自适应噪声底）

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

            // 自适应噪声底估计（Phase 4）
            let noiseFloor = estimateNoiseFloor(energyHistory: energyHistory)
            let adaptiveMinEnergy = max(0.001, noiseFloor * 3.0)

            // 检测能量突变（使用自适应阈值）
            if energyRatio > config.energyRatio && energy > adaptiveMinEnergy {
                let timestamp = timeOffset + Double(startIndex) / sampleRate

                // 计算峰值幅度
                var maxVal: Float = 0
                vDSP_maxmgv(window, 1, &maxVal, vDSP_Length(window.count))
                let peakAmplitude = Double(maxVal)

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
                    noiseFloor: noiseFloor,
                    spectralFeatures: nil,
                    attackTime: nil,
                    dominantFrequency: nil,
                    frequencyValid: true,
                    confidence: 0
                )
                candidates.append(candidate)

                diagnosticCollector?.recordCandidate(candidate, stage: "EPD")
            }

            // 更新历史（扩展到 50 个条目用于噪声底估计）
            energyHistory.append(energy)
            if energyHistory.count > 50 {
                energyHistory.removeFirst()
            }
            previousEnergy = energy
        }

        print("🎯 [SimpleHitDetector] Stage 1 EPD: 检测到 \(candidates.count) 个能量峰值")
        return candidates
    }

    // MARK: - Phase 4: 自适应噪声底估计

    /// 基于百分位的噪声底估计
    private func estimateNoiseFloor(energyHistory: [Double]) -> Double {
        guard energyHistory.count >= 10 else { return 0.001 }
        let sorted = energyHistory.sorted()
        let p10Index = max(0, Int(Double(sorted.count) * 0.10))
        return max(sorted[p10Index], 1e-10)
    }

    // MARK: - Stage 2 + 3: 频谱分析与 8 维置信度评分

    private func analyzeAndScore(
        candidates: [PeakCandidate],
        samples: [Float],
        sampleRate: Double
    ) -> [AudioPeak] {
        var scoredCandidates: [PeakCandidate] = []

        // 计算全局统计量用于归一化
        let rmsValues = candidates.map { $0.rms }
        let maxRMS = rmsValues.max() ?? 1.0

        for var candidate in candidates {
            // Stage 2a: 频谱分析
            let fftSize = config.fftSize
            let startIndex = max(0, candidate.sampleIndex - fftSize / 2)
            let availableEnd = min(samples.count, startIndex + fftSize)

            if availableEnd - startIndex >= fftSize {
                let fftWindow = Array(samples[startIndex..<startIndex + fftSize])
                let spectral = analyzeSpectralFeatures(samples: fftWindow, sampleRate: sampleRate)
                candidate.spectralFeatures = spectral
                candidate.dominantFrequency = spectral.dominantFrequency
            }

            // Stage 2b: 攻击时间计算（Phase 5）
            let attackWindowSize = min(1024, Int(sampleRate * 0.025))  // ~25ms 窗口
            let attackStart = max(0, candidate.sampleIndex - attackWindowSize / 4)
            let attackEnd = min(samples.count, attackStart + attackWindowSize)
            if attackEnd - attackStart > 10 {
                let attackWindow = Array(samples[attackStart..<attackEnd])
                candidate.attackTime = calculateAttackTime(window: attackWindow, sampleRate: sampleRate)
            }

            // Stage 3: 8 维置信度评分
            let confidence = calculate8DConfidence(
                candidate: candidate,
                maxRMS: maxRMS
            )
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

        print("🎯 [SimpleHitDetector] Stage 2+3 频谱分析+置信度过滤: \(mergedCandidates.count)/\(candidates.count) 通过")

        return mergedCandidates.map { candidate in
            AudioPeak(
                time: candidate.timestamp,
                amplitude: candidate.peakAmplitude,
                confidence: candidate.confidence
            )
        }
    }

    // MARK: - Phase 2: 频谱分析（1024 点 FFT + Hann 窗口 + vDSP_fft_zrip）

    /// 使用改进的 FFT 进行频谱特征提取
    private func analyzeSpectralFeatures(samples: [Float], sampleRate: Double) -> DetectedSpectralFeatures {
        let n = samples.count
        guard n > 0 && (n & (n - 1)) == 0 else {
            return DetectedSpectralFeatures(
                dominantFrequency: 0, lowBandEnergy: 0, midBandEnergy: 0,
                highBandEnergy: 0, highFreqEnergyRatio: 0, spectralCentroid: 0, spectralFlux: 0
            )
        }

        let log2n = vDSP_Length(log2(Double(n)))
        let halfSize = n / 2

        // 获取或创建 FFT Setup（缓存）
        let fftSetup: FFTSetup
        if let cached = cachedFFTSetup, cached.log2n == log2n {
            fftSetup = cached.setup
        } else {
            guard let newSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
                return DetectedSpectralFeatures(
                    dominantFrequency: 0, lowBandEnergy: 0, midBandEnergy: 0,
                    highBandEnergy: 0, highFreqEnergyRatio: 0, spectralCentroid: 0, spectralFlux: 0
                )
            }
            if let old = cachedFFTSetup {
                vDSP_destroy_fftsetup(old.setup)
            }
            cachedFFTSetup = (newSetup, log2n)
            fftSetup = newSetup
        }

        // 获取或创建 Hann 窗口（缓存）
        if cachedHannWindow == nil || cachedHannWindowSize != n {
            var window = [Float](repeating: 0, count: n)
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
            cachedHannWindow = window
            cachedHannWindowSize = n
        }

        // 应用 Hann 窗口
        var windowedSamples = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, cachedHannWindow!, 1, &windowedSamples, 1, vDSP_Length(n))

        // 准备分裂复数格式用于 vDSP_fft_zrip
        var realParts = [Float](repeating: 0, count: halfSize)
        var imagParts = [Float](repeating: 0, count: halfSize)

        // 将实信号打包为分裂复数格式
        for i in 0..<halfSize {
            realParts[i] = windowedSamples[2 * i]
            imagParts[i] = windowedSamples[2 * i + 1]
        }

        var splitComplex = DSPSplitComplex(realp: &realParts, imagp: &imagParts)

        // 执行实信号 FFT（vDSP_fft_zrip 比 vDSP_fft_zip 快约 2x）
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // 计算幅度谱（功率谱）
        var magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

        // 转换为幅度（开方）
        var powerSpectrum = [Float](repeating: 0, count: halfSize)
        var count = Int32(halfSize)
        vvsqrtf(&powerSpectrum, magnitudes, &count)

        // 频率分辨率
        let freqResolution = sampleRate / Double(n)

        // 多频带能量分析
        // 低频：200-500Hz（球体共振）
        let lowMinBin = max(1, Int(200.0 / freqResolution))
        let lowMaxBin = min(halfSize, Int(500.0 / freqResolution))
        // 中频：500-2000Hz（弦-球交互）
        let midMinBin = max(1, Int(500.0 / freqResolution))
        let midMaxBin = min(halfSize, Int(2000.0 / freqResolution))
        // 高频：2000-5000Hz（撞击瞬态）
        let highMinBin = max(1, Int(2000.0 / freqResolution))
        let highMaxBin = min(halfSize, Int(5000.0 / freqResolution))

        var lowBandEnergy: Double = 0
        var midBandEnergy: Double = 0
        var highBandEnergy: Double = 0
        var totalEnergy: Double = 0
        var weightedSum: Double = 0

        // 主导频率搜索（在 300-5000Hz 范围内）
        let searchMinBin = max(1, Int(300.0 / freqResolution))
        let searchMaxBin = min(halfSize, Int(5000.0 / freqResolution))
        var maxMag: Float = 0
        var maxIndex = 0

        for i in 1..<halfSize {
            let mag = Double(powerSpectrum[i])
            let freq = Double(i) * freqResolution
            totalEnergy += mag
            weightedSum += freq * mag

            if i >= lowMinBin && i < lowMaxBin { lowBandEnergy += mag }
            if i >= midMinBin && i < midMaxBin { midBandEnergy += mag }
            if i >= highMinBin && i < highMaxBin { highBandEnergy += mag }

            if i >= searchMinBin && i < searchMaxBin && powerSpectrum[i] > maxMag {
                maxMag = powerSpectrum[i]
                maxIndex = i
            }
        }

        let dominantFrequency = Double(maxIndex) * freqResolution
        let highFreqEnergyRatio = totalEnergy > 0 ? (midBandEnergy + highBandEnergy) / totalEnergy : 0
        let spectralCentroid = totalEnergy > 0 ? weightedSum / totalEnergy : 0

        // 频谱通量（相邻 bin 差异平方和的归一化平方根）
        var spectralFlux: Double = 0
        if halfSize > 1 {
            for i in 1..<halfSize {
                let diff = Double(powerSpectrum[i]) - Double(powerSpectrum[i - 1])
                spectralFlux += diff * diff
            }
            spectralFlux = sqrt(spectralFlux) / Double(halfSize)
        }

        return DetectedSpectralFeatures(
            dominantFrequency: dominantFrequency,
            lowBandEnergy: lowBandEnergy,
            midBandEnergy: midBandEnergy,
            highBandEnergy: highBandEnergy,
            highFreqEnergyRatio: highFreqEnergyRatio,
            spectralCentroid: spectralCentroid,
            spectralFlux: spectralFlux
        )
    }

    // MARK: - Phase 5: 攻击时间检测

    /// 计算攻击时间（从 10% 阈值到峰值的时间）
    private func calculateAttackTime(window: [Float], sampleRate: Double) -> Double {
        guard window.count > 10 else { return 1.0 }

        // 找到峰值样本
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxmgvi(window, 1, &maxVal, &maxIdx, vDSP_Length(window.count))

        let peakIdx = Int(maxIdx)
        let threshold = maxVal * 0.1  // 10% 阈值

        // 从峰值向后搜索 10% 阈值交叉点（限制搜索范围 ~2ms）
        let searchLimit = max(0, peakIdx - min(100, peakIdx))
        var attackStart = searchLimit
        for i in stride(from: peakIdx, through: searchLimit, by: -1) {
            if abs(window[i]) < threshold {
                attackStart = i
                break
            }
        }

        return Double(peakIdx - attackStart) / sampleRate
    }

    // MARK: - Phase 3: 8 维置信度评分

    /// 8 维特征置信度计算 + SNR 感知 + 攻击时间调制
    private func calculate8DConfidence(
        candidate: PeakCandidate,
        maxRMS: Double
    ) -> Double {
        let spectral = candidate.spectralFeatures

        // 特征 1: 能量突变比 (20%)
        let energyScore = min(candidate.energyRatio / 5.0, 1.0) * 0.20

        // 特征 2: RMS 强度 (12%)
        let rmsScore = min(candidate.rms / maxRMS, 1.0) * 0.12

        // 特征 3: 峰值尖锐度 (8%)
        let sharpnessScore = min(candidate.sharpness / 3.0, 1.0) * 0.08

        // 特征 4: 频率匹配 (15%)
        let freqMatchScore: Double
        if let freq = spectral?.dominantFrequency, freq > 0 {
            if freq >= 500 && freq <= 4000 {
                freqMatchScore = 1.0
            } else if freq >= 300 && freq <= 5000 {
                freqMatchScore = 0.6
            } else {
                freqMatchScore = 0.2
            }
        } else {
            freqMatchScore = 0.5  // 无频谱数据时中性评分
        }
        let frequencyScore = freqMatchScore * 0.15

        // 特征 5: 高频能量占比 (15%)
        let highFreqRatio = spectral?.highFreqEnergyRatio ?? 0
        let highFreqScore = min(highFreqRatio / 0.15, 1.0) * 0.15

        // 特征 6: 频谱质心 (10%)
        let centroidMatchScore: Double
        if let centroid = spectral?.spectralCentroid, centroid > 0 {
            if centroid >= 1500 && centroid <= 3500 {
                centroidMatchScore = 1.0
            } else if centroid >= 800 && centroid <= 5000 {
                centroidMatchScore = 0.6
            } else {
                centroidMatchScore = 0.2
            }
        } else {
            centroidMatchScore = 0.5
        }
        let centroidScore = centroidMatchScore * 0.10

        // 特征 7: 频谱通量 (10%)
        let flux = spectral?.spectralFlux ?? 0
        let fluxScore = min(flux * 5.0, 1.0) * 0.10

        // 特征 8: 峰度因子 (10%)
        let crestFactor = candidate.rms > 1e-10 ? candidate.peakAmplitude / candidate.rms : 0
        let crestScore = min(crestFactor / 4.0, 1.0) * 0.10

        var confidence = energyScore + rmsScore + sharpnessScore + frequencyScore
                       + highFreqScore + centroidScore + fluxScore + crestScore

        // SNR 感知调制（Phase 4）
        if candidate.noiseFloor > 1e-10 {
            let snr = 10.0 * log10(candidate.energy / candidate.noiseFloor)
            if snr < 6 {
                confidence *= 0.7
            } else if snr < 12 {
                confidence *= 0.9
            } else if snr > 20 {
                confidence = min(confidence * 1.05, 1.0)
            }
        }

        // 攻击时间调制（Phase 5）
        if let attackTime = candidate.attackTime {
            if attackTime < 0.005 {
                confidence = min(confidence * 1.1, 1.0)   // 快速攻击，网球击球特征
            } else if attackTime > 0.015 {
                confidence *= 0.8                          // 慢攻击，可能是人声或环境噪声
            }
        }

        return confidence
    }

    // MARK: - Helper Methods

    /// 合并过近的峰值
    private func mergePeaks(_ candidates: [PeakCandidate]) -> [PeakCandidate] {
        guard !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { $0.timestamp < $1.timestamp }
        var merged: [PeakCandidate] = []

        for candidate in sorted {
            if let last = merged.last {
                if candidate.timestamp - last.timestamp < config.minPeakInterval {
                    if candidate.confidence > last.confidence {
                        merged.removeLast()
                        merged.append(candidate)
                    }
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
    let noiseFloor: Double
    var spectralFeatures: SimpleHitDetector.DetectedSpectralFeatures?
    var attackTime: Double?
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
        let spectral = candidate.spectralFeatures

        // 计算各项得分用于诊断
        let energyScore = min(candidate.energyRatio / 5.0, 1.0) * 0.20
        let crestFactor = candidate.rms > 1e-10 ? candidate.peakAmplitude / candidate.rms : 0
        let crestFactorScore = min(crestFactor / 4.0, 1.0) * 0.10
        let highFreqEnergyScore = min((spectral?.highFreqEnergyRatio ?? 0) / 0.15, 1.0) * 0.15

        let freqMatchScore: Double
        if let freq = spectral?.dominantFrequency, freq > 0 {
            freqMatchScore = (freq >= 500 && freq <= 4000) ? 1.0 : ((freq >= 300 && freq <= 5000) ? 0.6 : 0.2)
        } else {
            freqMatchScore = 0.5
        }
        let frequencyScore = freqMatchScore * 0.15

        // sharpness + spectralFlux + centroid 合计为 otherFeaturesScore
        let sharpnessScore = min(candidate.sharpness / 3.0, 1.0) * 0.08
        let fluxScore = min((spectral?.spectralFlux ?? 0) * 5.0, 1.0) * 0.10
        let centroidMatchScore: Double
        if let centroid = spectral?.spectralCentroid, centroid > 0 {
            centroidMatchScore = (centroid >= 1500 && centroid <= 3500) ? 1.0 : ((centroid >= 800 && centroid <= 5000) ? 0.6 : 0.2)
        } else {
            centroidMatchScore = 0.5
        }
        let centroidScore = centroidMatchScore * 0.10

        return CandidatePeakData(
            time: candidate.timestamp,
            amplitude: candidate.peakAmplitude,
            rms: candidate.rms,
            duration: 0.015,
            confidence: candidate.confidence,
            confidenceBreakdown: ConfidenceBreakdown(
                amplitudeScore: energyScore,
                crestFactorScore: crestFactorScore,
                energyConcentrationScore: min(candidate.rms / 1.0, 1.0) * 0.12,  // RMS 归一化
                frequencyRangeScore: frequencyScore,
                highFreqEnergyScore: highFreqEnergyScore,
                otherFeaturesScore: sharpnessScore + fluxScore + centroidScore
            ),
            spectralFeatures: SpectralFeatures(
                dominantFrequency: spectral?.dominantFrequency ?? 0,
                spectralCentroid: spectral?.spectralCentroid ?? 0,
                spectralRolloff: 0,
                lowFreqEnergy: spectral?.lowBandEnergy ?? 0,
                primaryHitRangeEnergy: spectral?.midBandEnergy ?? 0,
                highFreqEnergy: spectral?.highBandEnergy ?? 0,
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
