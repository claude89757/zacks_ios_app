//
//  AudioAnalyzer.swift
//  zacks_tennis
//
//  音频分析器 - 检测网球击球声音
//  使用 AVFoundation 提取音频并分析峰值，识别可能的击球声
//

import Foundation
import AVFoundation
import Accelerate

/// 音频分析器 - 负责检测击球声音
actor AudioAnalyzer: AudioAnalyzing {

    // MARK: - Properties

    /// 音频分析配置（可更新，以支持智能配置选择）
    private var config: AudioAnalysisConfiguration

    // MARK: - Diagnostic Properties

    /// 诊断模式开关
    private var diagnosticMode: Bool = false

    /// 诊断数据收集器
    private var diagnosticCollector: DiagnosticDataCollector?

    // MARK: - Initialization

    init(config: AudioAnalysisConfiguration = .default) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 分析视频音频，检测击球声
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - timeRange: 要分析的时间范围
    /// - Returns: 音频分析结果
    func analyzeAudio(
        from asset: AVAsset,
        timeRange: CMTimeRange
    ) async throws -> AudioAnalysisResult {

        // 1. 获取音频轨道
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            // 没有音频轨道，返回空结果
            return AudioAnalysisResult(hitSounds: [])
        }

        // 2. 配置 AssetReader
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )

        reader.add(trackOutput)
        reader.timeRange = timeRange

        // 3. 开始读取
        guard reader.startReading() else {
            throw AudioAnalyzerError.readFailed
        }

        // 4. 提取音频数据并分析峰值
        var audioPeaks: [AudioPeak] = []
        var audioSamples: [Int16] = []
        var currentTime = CMTimeGetSeconds(timeRange.start)

        let sampleRate = try await audioTrack.load(.naturalTimeScale)
        // 优化：使用更小的窗口（0.05秒）进行更频繁的检测，提高对瞬时击球声的敏感度
        let samplesPerBuffer = Int(sampleRate) / 20 // 每 0.05 秒分析一次（原来0.1秒）

        while reader.status == .reading {
            autoreleasepool {
                guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                    return
                }

                defer {
                    CMSampleBufferInvalidate(sampleBuffer)
                }

                // 提取音频数据
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = Data(count: length)

                    data.withUnsafeMutableBytes { ptr in
                        if let baseAddress = ptr.baseAddress {
                            CMBlockBufferCopyDataBytes(
                                blockBuffer,
                                atOffset: 0,
                                dataLength: length,
                                destination: baseAddress
                            )
                        }
                    }

                    // 转换为 Int16 数组
                    let samples = data.withUnsafeBytes { buffer in
                        Array(buffer.bindMemory(to: Int16.self))
                    }

                    audioSamples.append(contentsOf: samples)

                    // 更新时间戳
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    currentTime = CMTimeGetSeconds(presentationTime)
                }
            }

            // 当累积足够样本时进行分析
            if audioSamples.count >= samplesPerBuffer {
                let peak = analyzeSampleBuffer(
                    samples: audioSamples,
                    timestamp: currentTime,
                    sampleRate: Double(sampleRate)
                )

                if let peak = peak {
                    audioPeaks.append(peak)
                }

                // 清空缓冲区
                audioSamples.removeAll(keepingCapacity: true)
            }
        }

        // 5. 自适应阈值过滤：基于统计量动态调整
        let adaptiveFiltered = adaptiveThresholdFiltering(audioPeaks)

        // 6. 后处理：过滤和合并相近的峰值
        let filteredPeaks = postProcessPeaks(adaptiveFiltered)

        return AudioAnalysisResult(hitSounds: filteredPeaks)
    }

    /// 批量分析多个时间段的音频
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - timeRanges: 时间范围数组
    /// - Returns: 音频分析结果
    func analyzeMultipleRanges(
        from asset: AVAsset,
        timeRanges: [CMTimeRange]
    ) async throws -> AudioAnalysisResult {

        var allPeaks: [AudioPeak] = []

        for timeRange in timeRanges {
            let result = try await analyzeAudio(from: asset, timeRange: timeRange)
            allPeaks.append(contentsOf: result.hitSounds)
        }

        // 按时间排序
        allPeaks.sort { $0.time < $1.time }

        return AudioAnalysisResult(hitSounds: allPeaks)
    }

    // MARK: - Configuration Methods

    /// 更新音频分析配置
    /// - Parameter newConfig: 新的配置
    func updateConfig(_ newConfig: AudioAnalysisConfiguration) async {
        self.config = newConfig
        print("⚙️ [AudioAnalyzer] 配置已更新为: \(newConfig.presetName)")
    }

    // MARK: - Diagnostic Methods

    /// 启用诊断模式
    /// - Parameter videoInfo: 视频基本信息
    func enableDiagnosticMode(videoInfo: VideoDiagnosticInfo) async {
        self.diagnosticMode = true
        self.diagnosticCollector = DiagnosticDataCollector(videoInfo: videoInfo, config: config)
        print("🔍 [AudioAnalyzer] 诊断模式已启用")
    }

    /// 禁用诊断模式
    func disableDiagnosticMode() async {
        self.diagnosticMode = false
        self.diagnosticCollector = nil
        print("🔍 [AudioAnalyzer] 诊断模式已禁用")
    }

    /// 获取诊断数据（仅在诊断模式下）
    /// - Returns: 音频诊断数据，如果未启用诊断模式则返回 nil
    func getDiagnosticData() async -> AudioDiagnosticData? {
        guard let collector = diagnosticCollector else { return nil }
        return collector.generateDiagnosticData()
    }

    // MARK: - Private Methods - Analysis

    /// 分析单个音频样本缓冲区（增强版：结合FFT频谱分析）
    /// - Parameters:
    ///   - samples: 音频样本（Int16）
    ///   - timestamp: 时间戳
    ///   - sampleRate: 采样率
    /// - Returns: 检测到的音频峰值（如果有）
    private func analyzeSampleBuffer(
        samples: [Int16],
        timestamp: Double,
        sampleRate: Double
    ) -> AudioPeak? {

        guard !samples.isEmpty else { return nil }

        // 转换为Float数组用于FFT分析
        let floatSamples = samples.map { Float($0) / Float(Int16.max) }

        // 1. 计算 RMS（均方根）功率
        let rms = calculateRMS(samples: samples)

        // 2. 计算峰值功率（改进：使用滑动窗口检测瞬时峰值）
        let peakAmplitude = calculatePeakAmplitudeImproved(samples: floatSamples)

        // 📊 诊断：记录 RMS 数据点
        if diagnosticMode {
            diagnosticCollector?.recordRMS(time: timestamp, rms: rms, peakAmplitude: peakAmplitude)
        }

        // 3. 判断是否是显著峰值（收紧条件，减少误报）
        // 如果峰值幅度足够高，才认为是显著峰值
        let isPeak = peakAmplitude > config.peakThreshold

        // 收紧条件：只有峰值幅度较高且RMS也较高时，才认为是潜在峰值
        let isPotentialPeak = peakAmplitude > config.peakThreshold * 0.85 && rms > 0.2

        guard isPeak || isPotentialPeak else {
            // 📊 诊断：记录被振幅阈值拒绝的候选峰值
            if diagnosticMode, (peakAmplitude > config.peakThreshold * 0.5 || rms > 0.1) {
                // 仍然进行完整分析以收集诊断数据
                let spectralAnalysis = analyzeSpectrum(samples: floatSamples, sampleRate: sampleRate)
                let attackTime = calculateAttackTime(samples: floatSamples, sampleRate: sampleRate)
                let eventDuration = calculateEventDuration(samples: floatSamples, sampleRate: sampleRate)
                let energyConcentration = calculateEnergyConcentration(samples: samples)
                let confidence = 0.0  // 未通过初步检查

                let breakdown = extractConfidenceBreakdown(
                    peakAmplitude: peakAmplitude,
                    rms: rms,
                    energyConcentration: energyConcentration,
                    spectralAnalysis: spectralAnalysis
                )
                let spectralFeatures = convertSpectralFeatures(spectralAnalysis)

                let reason = !isPeak ? "振幅低于阈值 (\(String(format: "%.3f", peakAmplitude)) < \(config.peakThreshold))" :
                                      "RMS过低 (\(String(format: "%.3f", rms)) < 0.2)"
                recordDiagnosticCandidate(
                    time: timestamp,
                    amplitude: peakAmplitude,
                    rms: rms,
                    duration: eventDuration,
                    confidence: confidence,
                    spectralFeatures: spectralFeatures,
                    confidenceBreakdown: breakdown,
                    passed: false,
                    rejectionReason: reason,
                    rejectionStage: FilteringStage.amplitudeFilter.rawValue
                )
            }
            return nil
        }

        // 更新诊断统计
        if diagnosticMode {
            diagnosticCollector?.passedAmplitudeThreshold += 1
        }

        // 4. FFT频谱分析（检测击球声的典型频率特征）
        let spectralAnalysis = analyzeSpectrum(samples: floatSamples, sampleRate: sampleRate)
        
        // 5. 检测攻击时间（attack time）- 击球声的特征是快速上升
        let attackTime = calculateAttackTime(samples: floatSamples, sampleRate: sampleRate)

        // 5a. 计算事件持续时间 - 击球声通常在 20-100ms 之间
        let eventDuration = calculateEventDuration(samples: floatSamples, sampleRate: sampleRate)

        // 5b. 时长过滤：击球声的典型持续时间
        // 放宽范围：10ms - 150ms（适应削球、轻击等多种技术）
        let isValidDuration = eventDuration >= 0.01 && eventDuration <= 0.15

        // 如果持续时间明显不合理，直接过滤掉
        // 只在置信度很低时才硬过滤（从0.6降至0.45，减少误过滤）
        if !isValidDuration && peakAmplitude < 0.45 {
            // 📊 诊断：记录被持续时间拒绝的候选峰值
            if diagnosticMode {
                let energyConcentration = calculateEnergyConcentration(samples: samples)
                let confidence = calculateHitSoundConfidenceEnhanced(
                    rms: rms,
                    peakAmplitude: peakAmplitude,
                    samples: samples,
                    sampleRate: sampleRate,
                    spectralAnalysis: spectralAnalysis,
                    attackTime: attackTime,
                    eventDuration: eventDuration
                )

                let breakdown = extractConfidenceBreakdown(
                    peakAmplitude: peakAmplitude,
                    rms: rms,
                    energyConcentration: energyConcentration,
                    spectralAnalysis: spectralAnalysis
                )
                let spectralFeatures = convertSpectralFeatures(spectralAnalysis)

                recordDiagnosticCandidate(
                    time: timestamp,
                    amplitude: peakAmplitude,
                    rms: rms,
                    duration: eventDuration,
                    confidence: confidence,
                    spectralFeatures: spectralFeatures,
                    confidenceBreakdown: breakdown,
                    passed: false,
                    rejectionReason: "持续时间不符合范围 (\(String(format: "%.3f", eventDuration))s, 需要 0.01-0.15s) 且振幅过低",
                    rejectionStage: FilteringStage.durationFilter.rawValue
                )
            }
            return nil
        }

        // 更新诊断统计
        if diagnosticMode {
            diagnosticCollector?.passedDurationCheck += 1
        }

        // 6. 计算置信度（基于多个特征，包括频谱）
        let confidence = calculateHitSoundConfidenceEnhanced(
            rms: rms,
            peakAmplitude: peakAmplitude,
            samples: samples,
            sampleRate: sampleRate,
            spectralAnalysis: spectralAnalysis,
            attackTime: attackTime,
            eventDuration: eventDuration
        )

        // 7. 精确定位峰值时间（使用插值）
        let preciseTimestamp = findPrecisePeakTime(samples: floatSamples, baseTimestamp: timestamp, sampleRate: sampleRate)

        // 8. 只返回置信度足够高的峰值
        // 收紧条件：提高置信度阈值，减少误报
        // 对于明显的峰值（幅度很高），可以稍微放宽置信度要求
        let confidenceThreshold = peakAmplitude > 0.5 ? config.minimumConfidence * 0.9 : config.minimumConfidence

        // 📊 诊断：记录候选峰值（通过或拒绝）
        if diagnosticMode {
            let energyConcentration = calculateEnergyConcentration(samples: samples)
            let breakdown = extractConfidenceBreakdown(
                peakAmplitude: peakAmplitude,
                rms: rms,
                energyConcentration: energyConcentration,
                spectralAnalysis: spectralAnalysis
            )
            let spectralFeatures = convertSpectralFeatures(spectralAnalysis)

            let passed = confidence >= confidenceThreshold
            let rejectionReason = passed ? nil : "置信度过低 (\(String(format: "%.3f", confidence)) < \(String(format: "%.3f", confidenceThreshold)))"
            let rejectionStage = passed ? nil : FilteringStage.confidenceFilter.rawValue

            recordDiagnosticCandidate(
                time: preciseTimestamp,
                amplitude: peakAmplitude,
                rms: rms,
                duration: eventDuration,
                confidence: confidence,
                spectralFeatures: spectralFeatures,
                confidenceBreakdown: breakdown,
                passed: passed,
                rejectionReason: rejectionReason,
                rejectionStage: rejectionStage
            )

            if passed {
                diagnosticCollector?.passedConfidenceThreshold += 1
            }
        }

        if confidence >= confidenceThreshold {
            return AudioPeak(
                time: preciseTimestamp,
                amplitude: peakAmplitude,
                confidence: confidence
            )
        }

        return nil
    }

    /// 改进的峰值检测（使用滑动窗口检测瞬时峰值）
    private func calculatePeakAmplitudeImproved(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0.0 }
        
        // 优化：使用更小的窗口检测瞬时峰值（击球声是瞬时的，需要更短的时间窗口）
        let windowSize = min(256, samples.count / 8) // 更短的窗口（原来512，现在256）
        guard windowSize > 0 else { return 0.0 }
        
        var maxPeak: Float = 0.0
        
        // 优化：使用更小的步长，确保不遗漏任何峰值
        let stepSize = max(1, windowSize / 4) // 更小的步长
        
        for i in stride(from: 0, to: samples.count - windowSize, by: stepSize) {
            let window = Array(samples[i..<min(i + windowSize, samples.count)])
            
            // 计算窗口内的峰值
            let windowMax = window.map { abs($0) }.max() ?? 0.0
            
            // 计算窗口内的RMS
            let windowRMS = sqrt(window.map { $0 * $0 }.reduce(0, +) / Float(window.count))
            
            // 优化：更重视峰值（击球声是瞬时的强峰值）
            let combined = windowMax * 0.8 + windowRMS * 0.2
            
            maxPeak = max(maxPeak, combined)
        }
        
        // 如果没有找到峰值，使用全局最大值作为备选
        if maxPeak < 0.1 {
            let globalMax = samples.map { abs($0) }.max() ?? 0.0
            maxPeak = max(maxPeak, Float(globalMax))
        }
        
        return Double(maxPeak)
    }

    /// FFT频谱分析结果（基于网球击球声特征优化）
    struct SpectralAnalysis {
        let dominantFrequency: Double
        let energyInHitRange: Double  // 500-4000Hz范围内的能量
        let energyInPrimaryRange: Double  // 1000-3000Hz范围内的能量（拍线振动特征）
        let energyInLowFreq: Double  // 200-500Hz范围内的能量（球体旋转特征）
        let spectralCentroid: Double  // 频谱重心
        let spectralRolloff: Double   // 频谱滚降点
        let spectralContrast: Double  // 频谱对比度（区分击球声和背景噪声）
        let spectralFlux: Double  // 频谱通量（检测瞬态变化）
        let highFreqEnergyRatio: Double  // 高频能量占比（1000-3000Hz / 总能量）
        let mfccCoefficients: [Double]  // MFCC系数（13维，提高鲁棒性）
        let mfccVariance: Double  // MFCC系数方差（衡量音频复杂度）
    }

    /// 频谱分析（使用FFT检测击球声的典型频率特征）
    private func analyzeSpectrum(samples: [Float], sampleRate: Double) -> SpectralAnalysis {
        // 优化：使用固定大小的FFT窗口，提高效率和准确性
        let targetFFTSize = 2048 // 固定FFT大小，提供更好的频率分辨率
        guard samples.count >= 256 else {
            return SpectralAnalysis(
                dominantFrequency: 0,
                energyInHitRange: 0,
                energyInPrimaryRange: 0,
                energyInLowFreq: 0,
                spectralCentroid: 0,
                spectralRolloff: 0,
                spectralContrast: 0,
                spectralFlux: 0,
                highFreqEnergyRatio: 0,
                mfccCoefficients: [Double](repeating: 0, count: 13),
                mfccVariance: 0
            )
        }
        
        // 如果样本数少于FFT大小，使用实际大小
        let fftSize = min(targetFFTSize, nextPowerOfTwo(samples.count))
        
        // 填充到FFT大小（只取前fftSize个样本，避免填充过多零）
        var paddedSamples: [Float]
        if samples.count >= fftSize {
            paddedSamples = Array(samples.prefix(fftSize))
        } else {
            paddedSamples = samples
            while paddedSamples.count < fftSize {
                paddedSamples.append(0)
            }
        }
        
        // 使用vDSP进行FFT（需要Accelerate框架）
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
            return SpectralAnalysis(
                dominantFrequency: 0,
                energyInHitRange: 0,
                energyInPrimaryRange: 0,
                energyInLowFreq: 0,
                spectralCentroid: 0,
                spectralRolloff: 0,
                spectralContrast: 0,
                spectralFlux: 0,
                highFreqEnergyRatio: 0,
                mfccCoefficients: [Double](repeating: 0, count: 13),
                mfccVariance: 0
            )
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        let halfSize = fftSize / 2
        var realParts = [Float](repeating: 0, count: halfSize)
        var imagParts = [Float](repeating: 0, count: halfSize)
        
        // 应用Hanning窗减少频谱泄漏
        var windowedSamples = [Float](repeating: 0, count: fftSize)
        var hanningWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hanningWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(paddedSamples, 1, hanningWindow, 1, &windowedSamples, 1, vDSP_Length(fftSize))
        
        // 准备复数数据 - 对于实信号FFT，直接复制到realParts
        for i in 0..<halfSize {
            realParts[i] = windowedSamples[i]
            imagParts[i] = 0
        }
        
        var splitComplex = DSPSplitComplex(
            realp: &realParts,
            imagp: &imagParts
        )
        
        // 执行FFT（对于实信号，使用vDSP_fft_zrip）
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // 计算幅度谱
        var magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
        
        // 转换为功率谱（使用幅度本身，不需要开方）
        let powerSpectrum = magnitudes.map { sqrt($0) }
        
        // 定义网球击球声的特征频率范围
        // 1. 低频呼啸声：200-500Hz（球体旋转与空气摩擦）
        let lowFreqMin: Double = 200
        let lowFreqMax: Double = 500
        let lowFreqMinBin = Int(lowFreqMin * Double(fftSize) / sampleRate)
        let lowFreqMaxBin = Int(lowFreqMax * Double(fftSize) / sampleRate)
        let lowFreqRange = max(0, lowFreqMinBin)..<min(halfSize, lowFreqMaxBin)
        
        // 2. 主频率范围：1000-3000Hz（拍线振动，形成尖锐的"砰"声 - 这是最特征性的）
        let primaryFreqMin: Double = 1000
        let primaryFreqMax: Double = 3000
        let primaryMinBin = Int(primaryFreqMin * Double(fftSize) / sampleRate)
        let primaryMaxBin = Int(primaryFreqMax * Double(fftSize) / sampleRate)
        let primaryRange = max(0, primaryMinBin)..<min(halfSize, primaryMaxBin)
        
        // 3. 宽频率范围：300-5000Hz（总击球声范围）
        let hitSoundMinFreq: Double = 300
        let hitSoundMaxFreq: Double = 5000
        let minBin = Int(hitSoundMinFreq * Double(fftSize) / sampleRate)
        let maxBin = Int(hitSoundMaxFreq * Double(fftSize) / sampleRate)
        let validRange = max(0, minBin)..<min(halfSize, maxBin)
        
        // 找到主导频率（优先在1000-3000Hz范围内）
        var dominantFrequency: Double = 0
        var maxMagnitude: Float = 0
        var maxIndex = 0
        
        // 首先在主要频率范围内查找
        if !primaryRange.isEmpty {
            for i in primaryRange {
                if powerSpectrum[i] > maxMagnitude {
                    maxMagnitude = powerSpectrum[i]
                    maxIndex = i
                }
            }
        }
        
        // 如果主频率范围内没找到，在宽频率范围内查找
        if maxMagnitude == 0 && !validRange.isEmpty {
            for i in validRange {
                if powerSpectrum[i] > maxMagnitude {
                    maxMagnitude = powerSpectrum[i]
                    maxIndex = i
                }
            }
        }
        
        dominantFrequency = Double(maxIndex) * sampleRate / Double(fftSize)
        
        // 计算总能量
        var totalEnergy: Double = 0
        var weightedSum: Double = 0
        for i in 0..<halfSize {
            let energy = Double(powerSpectrum[i])
            totalEnergy += energy
            let freq = Double(i) * sampleRate / Double(fftSize)
            weightedSum += freq * energy
        }
        
        // 计算各频率范围内的能量
        let energyInHitRange: Double = validRange.isEmpty ? 0 :
            powerSpectrum[validRange].map { Double($0) }.reduce(0, +) / Double(validRange.count)
        
        let energyInPrimaryRange: Double = primaryRange.isEmpty ? 0 :
            powerSpectrum[primaryRange].map { Double($0) }.reduce(0, +) / Double(primaryRange.count)
        
        let energyInLowFreq: Double = lowFreqRange.isEmpty ? 0 :
            powerSpectrum[lowFreqRange].map { Double($0) }.reduce(0, +) / Double(lowFreqRange.count)
        
        // 计算高频能量占比（1000-3000Hz能量 / 总能量）
        let primaryEnergy = primaryRange.isEmpty ? 0 :
            powerSpectrum[primaryRange].map { Double($0) }.reduce(0, +)
        let highFreqEnergyRatio = totalEnergy > 0 ? primaryEnergy / totalEnergy : 0
        
        // 计算频谱重心（spectral centroid）
        let spectralCentroid = totalEnergy > 0 ? weightedSum / totalEnergy : 0
        
        // 计算频谱滚降点（spectral rolloff）- 85%能量所在频率
        var cumulativeEnergy: Double = 0
        let targetEnergy = totalEnergy * 0.85
        var spectralRolloff: Double = 0
        for i in 0..<halfSize {
            cumulativeEnergy += Double(powerSpectrum[i])
            if cumulativeEnergy >= targetEnergy {
                spectralRolloff = Double(i) * sampleRate / Double(fftSize)
                break
            }
        }
        
        // 计算频谱对比度（spectral contrast）- 区分击球声和背景噪声
        // 对比度 = 高频能量 - 低频能量
        let lowEnergy = lowFreqRange.isEmpty ? 0 :
            powerSpectrum[lowFreqRange].map { Double($0) }.reduce(0, +) / Double(lowFreqRange.count)
        let spectralContrast = max(0, energyInPrimaryRange - lowEnergy)
        
        // 计算频谱通量（spectral flux）- 检测瞬态变化
        // 简单实现：计算相邻频率bin的能量差异
        var spectralFlux: Double = 0
        if halfSize > 1 {
            for i in 1..<halfSize {
                let diff = Double(powerSpectrum[i]) - Double(powerSpectrum[i-1])
                spectralFlux += diff * diff
            }
            spectralFlux = sqrt(spectralFlux) / Double(halfSize)
        }

        // 计算 MFCC 系数（13维）- 提高鲁棒性和噪声抑制能力
        let mfccCoeffs = calculateMFCC(
            powerSpectrum: powerSpectrum,
            sampleRate: sampleRate,
            fftSize: fftSize,
            numCoefficients: 13
        )

        // 计算 MFCC 方差（衡量音频复杂度）
        let mfccMean = mfccCoeffs.reduce(0, +) / Double(mfccCoeffs.count)
        let mfccVariance = mfccCoeffs.map { pow($0 - mfccMean, 2) }.reduce(0, +) / Double(mfccCoeffs.count)

        return SpectralAnalysis(
            dominantFrequency: dominantFrequency,
            energyInHitRange: energyInHitRange,
            energyInPrimaryRange: energyInPrimaryRange,
            energyInLowFreq: energyInLowFreq,
            spectralCentroid: spectralCentroid,
            spectralRolloff: spectralRolloff,
            spectralContrast: spectralContrast,
            spectralFlux: spectralFlux,
            highFreqEnergyRatio: highFreqEnergyRatio,
            mfccCoefficients: mfccCoeffs,
            mfccVariance: mfccVariance
        )
    }

    /// 计算攻击时间（attack time）- 击球声的特征是快速上升
    private func calculateAttackTime(samples: [Float], sampleRate: Double) -> Double {
        guard samples.count > 10 else { return 1.0 }

        // 找到最大值的索引
        guard let maxIndex = samples.enumerated().max(by: { abs($0.element) < abs($1.element) })?.offset else {
            return 1.0
        }

        // 从开始到峰值，计算上升时间
        let peakValue = abs(samples[maxIndex])
        let threshold = peakValue * 0.1 // 10%阈值

        var attackStartIndex = 0
        for i in stride(from: max(0, maxIndex - 100), to: maxIndex, by: 1) {
            if abs(samples[i]) >= threshold {
                attackStartIndex = i
                break
            }
        }

        let attackSamples = maxIndex - attackStartIndex
        let attackTime = Double(attackSamples) / sampleRate

        // 击球声的攻击时间通常在0.001-0.01秒之间
        return attackTime
    }

    /// 计算音频事件持续时间 - 从事件开始到结束的完整时长
    /// - Parameters:
    ///   - samples: 音频样本
    ///   - sampleRate: 采样率
    /// - Returns: 事件持续时间（秒）
    private func calculateEventDuration(samples: [Float], sampleRate: Double) -> Double {
        guard samples.count > 10 else { return 0 }

        // 找到峰值
        guard let maxIndex = samples.enumerated().max(by: { abs($0.element) < abs($1.element) })?.offset else {
            return 0
        }

        let peakValue = abs(samples[maxIndex])
        let startThreshold = peakValue * 0.1  // 10% 阈值作为起始点
        let endThreshold = peakValue * 0.05   // 5% 阈值作为结束点（更宽松）

        // 向前搜索事件起始点
        var startIndex = 0
        for i in stride(from: maxIndex, through: 0, by: -1) {
            if abs(samples[i]) < startThreshold {
                startIndex = i
                break
            }
        }

        // 向后搜索事件结束点
        var endIndex = samples.count - 1
        for i in maxIndex..<samples.count {
            if abs(samples[i]) < endThreshold {
                endIndex = i
                break
            }
        }

        // 计算持续时间
        let durationSamples = endIndex - startIndex
        let duration = Double(durationSamples) / sampleRate

        return duration
    }

    /// 精确定位峰值时间（使用插值）
    private func findPrecisePeakTime(samples: [Float], baseTimestamp: Double, sampleRate: Double) -> Double {
        guard let maxIndex = samples.enumerated().max(by: { abs($0.element) < abs($1.element) })?.offset else {
            return baseTimestamp
        }
        
        // 使用抛物线插值精确定位峰值
        if maxIndex > 0 && maxIndex < samples.count - 1 {
            let y1 = abs(samples[maxIndex - 1])
            let y2 = abs(samples[maxIndex])
            let y3 = abs(samples[maxIndex + 1])
            
            // 抛物线插值公式
            let delta = Double((y1 - y3) / (2.0 * (y1 - 2.0 * y2 + y3) + 0.0001))
            let preciseOffset = Double(maxIndex) + delta
            return baseTimestamp + preciseOffset / sampleRate
        }
        
        return baseTimestamp + Double(maxIndex) / sampleRate
    }

    /// 计算下一个2的幂次方（用于FFT）
    private func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }

    // MARK: - MFCC Calculation

    /// 将赫兹转换为梅尔刻度
    private func hertzToMel(_ hz: Double) -> Double {
        return 2595.0 * log10(1.0 + hz / 700.0)
    }

    /// 将梅尔刻度转换为赫兹
    private func melToHertz(_ mel: Double) -> Double {
        return 700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    /// 创建梅尔滤波器组
    /// - Parameters:
    ///   - numFilters: 滤波器数量（通常为26）
    ///   - fftSize: FFT大小
    ///   - sampleRate: 采样率
    ///   - lowFreq: 最低频率（Hz）
    ///   - highFreq: 最高频率（Hz）
    /// - Returns: 滤波器组矩阵 [numFilters][fftSize/2]
    private func createMelFilterbank(
        numFilters: Int = 26,
        fftSize: Int,
        sampleRate: Double,
        lowFreq: Double = 0,
        highFreq: Double? = nil
    ) -> [[Double]] {
        let highFreqValue = highFreq ?? sampleRate / 2.0
        let numBins = fftSize / 2

        // 转换到梅尔刻度
        let lowMel = hertzToMel(lowFreq)
        let highMel = hertzToMel(highFreqValue)

        // 在梅尔刻度上均匀分布滤波器中心点
        var melPoints = [Double](repeating: 0, count: numFilters + 2)
        for i in 0..<(numFilters + 2) {
            melPoints[i] = lowMel + Double(i) * (highMel - lowMel) / Double(numFilters + 1)
        }

        // 转换回赫兹
        let hzPoints = melPoints.map { melToHertz($0) }

        // 转换为FFT频率bin索引
        let binPoints = hzPoints.map { Int(floor(Double(fftSize + 1) * $0 / sampleRate)) }

        // 创建滤波器组
        var filterbank = [[Double]](repeating: [Double](repeating: 0, count: numBins), count: numFilters)

        for i in 0..<numFilters {
            let leftBin = binPoints[i]
            let centerBin = binPoints[i + 1]
            let rightBin = binPoints[i + 2]

            // 上升斜坡
            for j in leftBin..<centerBin {
                if j < numBins && centerBin > leftBin {
                    filterbank[i][j] = Double(j - leftBin) / Double(centerBin - leftBin)
                }
            }

            // 下降斜坡
            for j in centerBin..<rightBin {
                if j < numBins && rightBin > centerBin {
                    filterbank[i][j] = Double(rightBin - j) / Double(rightBin - centerBin)
                }
            }
        }

        return filterbank
    }

    /// 计算MFCC系数
    /// - Parameters:
    ///   - powerSpectrum: 功率谱
    ///   - sampleRate: 采样率
    ///   - fftSize: FFT大小
    ///   - numCoefficients: 返回的MFCC系数数量（通常为13）
    /// - Returns: MFCC系数数组
    private func calculateMFCC(
        powerSpectrum: [Float],
        sampleRate: Double,
        fftSize: Int,
        numCoefficients: Int = 13
    ) -> [Double] {
        let numFilters = 26
        let halfSize = fftSize / 2

        // 创建梅尔滤波器组
        let filterbank = createMelFilterbank(
            numFilters: numFilters,
            fftSize: fftSize,
            sampleRate: sampleRate,
            lowFreq: 0,
            highFreq: sampleRate / 2.0
        )

        // 应用滤波器组并计算对数能量
        var filterEnergies = [Double](repeating: 0, count: numFilters)
        for i in 0..<numFilters {
            var energy: Double = 0
            for j in 0..<min(halfSize, filterbank[i].count) {
                energy += Double(powerSpectrum[j]) * filterbank[i][j]
            }
            // 取对数（添加小常数避免log(0)）
            filterEnergies[i] = log(max(energy, 1e-10))
        }

        // 应用DCT（离散余弦变换）得到MFCC系数
        var mfccCoeffs = [Double](repeating: 0, count: numCoefficients)
        for i in 0..<numCoefficients {
            var sum: Double = 0
            for j in 0..<numFilters {
                sum += filterEnergies[j] * cos(Double(i) * (Double(j) + 0.5) * Double.pi / Double(numFilters))
            }
            mfccCoeffs[i] = sum
        }

        return mfccCoeffs
    }

    /// 计算 RMS（均方根）功率
    private func calculateRMS(samples: [Int16]) -> Double {
        var sum: Double = 0.0

        for sample in samples {
            let normalized = Double(sample) / Double(Int16.max)
            sum += normalized * normalized
        }

        return sqrt(sum / Double(samples.count))
    }

    /// 计算峰值幅度
    private func calculatePeakAmplitude(samples: [Int16]) -> Double {
        guard let maxSample = samples.map({ abs($0) }).max() else {
            return 0.0
        }

        return Double(maxSample) / Double(Int16.max)
    }

    /// 增强的置信度计算（结合频谱特征，优化权重）
    private func calculateHitSoundConfidenceEnhanced(
        rms: Double,
        peakAmplitude: Double,
        samples: [Int16],
        sampleRate: Double,
        spectralAnalysis: SpectralAnalysis,
        attackTime: Double,
        eventDuration: Double
    ) -> Double {

        var confidence: Double = 0.0

        // 优化权重分配：如果击球声很明显，应该更信任峰值幅度

        // 特征1：峰值幅度（最重要，因为击球声很明显）- 提高权重
        let amplitudeScore = min(peakAmplitude / 0.6, 1.0) // 降低分母，提高敏感度
        confidence += amplitudeScore * 0.33 // 33% 权重（从35%调整）

        // 特征2：峰值与 RMS 的比值（击球声是短促的高峰值）
        let crestFactor = peakAmplitude / (rms + 0.001)
        let crestScore = min(crestFactor / 4.0, 1.0) // 降低阈值，提高敏感度
        confidence += crestScore * 0.23 // 23% 权重（从25%调整）

        // 特征3：信号能量集中度
        let energyConcentration = calculateEnergyConcentration(samples: samples)
        confidence += energyConcentration * 0.14 // 14% 权重（从15%调整）

        // 特征4：主频率范围检测（1000-3000Hz，拍线振动特征）- 最重要的频谱特征
        let frequencyInPrimaryRange = spectralAnalysis.dominantFrequency >= 1000 &&
                                     spectralAnalysis.dominantFrequency <= 3000
        let frequencyScore = frequencyInPrimaryRange ? 1.0 :
                           (spectralAnalysis.dominantFrequency >= 300 &&
                            spectralAnalysis.dominantFrequency <= 5000 ? 0.6 : 0.3)
        confidence += frequencyScore * 0.14 // 14% 权重（从15%调整）

        // 特征5：高频能量占比（1000-3000Hz能量占比）- 网球击球声的核心特征
        // 网球击球声的高频能量占比应该较高（>0.15）
        let highFreqRatioScore = min(spectralAnalysis.highFreqEnergyRatio / 0.15, 1.0)
        confidence += highFreqRatioScore * 0.14 // 14% 权重（从15%调整）

        // 特征6：主频率范围内的能量（1000-3000Hz）- 拍线振动能量
        let primaryRangeEnergyScore = min(spectralAnalysis.energyInPrimaryRange * 3.0, 1.0)
        confidence += primaryRangeEnergyScore * 0.09 // 9% 权重（从10%调整）

        // 特征7：频谱对比度（区分击球声和背景噪声）
        let contrastScore = min(spectralAnalysis.spectralContrast * 2.0, 1.0)
        confidence += contrastScore * 0.09 // 9% 权重（从10%调整）

        // 特征8：频谱通量（检测瞬态变化）- 击球声是瞬态的
        let fluxScore = min(spectralAnalysis.spectralFlux * 5.0, 1.0)
        confidence += fluxScore * 0.05 // 5% 权重

        // 特征9：攻击时间（放宽范围）
        let attackTimeScore = (attackTime > 0.0003 && attackTime < 0.03) ? 1.0 : 0.7
        confidence += attackTimeScore * 0.05 // 5% 权重

        // 特征10：MFCC方差（音频复杂度）- 击球声具有特定的频谱特征，方差较大
        // MFCC方差范围通常在 0-500 之间，击球声通常 > 20
        let mfccVarianceScore = min(spectralAnalysis.mfccVariance / 50.0, 1.0)
        confidence += mfccVarianceScore * 0.07 // 7% 权重（从8%调整）

        // 特征11：事件持续时间（20-100ms 是击球声的典型范围）
        // 持续时间在最优范围内得满分，偏离则降低评分
        let optimalDurationMin: Double = 0.020  // 20ms
        let optimalDurationMax: Double = 0.100  // 100ms
        var durationScore: Double = 0.0

        if eventDuration >= optimalDurationMin && eventDuration <= optimalDurationMax {
            // 在最优范围内，得满分
            durationScore = 1.0
        } else if eventDuration < optimalDurationMin {
            // 太短，线性降低评分（15ms以下归零）
            durationScore = max(0, (eventDuration - 0.015) / (optimalDurationMin - 0.015))
        } else {
            // 太长，线性降低评分（120ms以上归零）
            durationScore = max(0, (0.120 - eventDuration) / (0.120 - optimalDurationMax))
        }
        confidence += durationScore * 0.07 // 7% 权重（新增）

        // 权重总和：100%
        return min(confidence, 1.0)
    }

    /// 计算信号能量集中度
    /// 能量越集中在少数几个样本点，越可能是击球声
    private func calculateEnergyConcentration(samples: [Int16]) -> Double {
        let sortedSamples = samples.map { abs($0) }.sorted(by: >)

        // 计算前 10% 样本的能量占比
        let top10Count = max(1, samples.count / 10)
        let top10Energy = sortedSamples.prefix(top10Count).map { Double($0) * Double($0) }.reduce(0, +)
        let totalEnergy = samples.map { Double($0) * Double($0) }.reduce(0, +)

        return totalEnergy > 0 ? top10Energy / totalEnergy : 0.0
    }

    /// 计算零交叉率（信号频率特征）
    private func calculateZeroCrossingRate(samples: [Int16]) -> Double {
        var crossings = 0

        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i-1] < 0) || (samples[i] < 0 && samples[i-1] >= 0) {
                crossings += 1
            }
        }

        return Double(crossings) / Double(samples.count)
    }

    // MARK: - Private Methods - Post Processing

    /// 自适应阈值过滤：基于局部统计动态调整置信度阈值
    /// - Parameter peaks: 原始峰值数组
    /// - Returns: 经过自适应过滤的峰值数组
    private func adaptiveThresholdFiltering(_ peaks: [AudioPeak]) -> [AudioPeak] {
        guard peaks.count >= 3 else { return peaks }

        // 计算全局统计量
        let confidences = peaks.map { $0.confidence }
        let meanConfidence = confidences.reduce(0, +) / Double(confidences.count)

        // ⚡️ 快速通道：如果整体音频质量很好（高置信度），跳过自适应过滤
        // 这可以避免误过滤真实击球，减少累积损失
        if meanConfidence > 0.7 {
            // 更新诊断统计计数器
            if diagnosticMode {
                diagnosticCollector?.passedAdaptiveFiltering = peaks.count
            }
            return peaks
        }

        let variance = confidences.map { pow($0 - meanConfidence, 2) }.reduce(0, +) / Double(confidences.count)
        let stdDev = sqrt(variance)

        // 自适应阈值 = 均值 + 调整系数 × 标准差
        // 降低调整系数：从1.0改为0.8（减少过度过滤）
        let adaptiveThreshold = max(
            config.minimumConfidence * 0.8,  // 最低不低于配置阈值的 80%
            min(
                meanConfidence + 0.8 * stdDev,  // 统计阈值（降低系数）
                config.minimumConfidence * 1.2   // 最高不超过配置阈值的 120%
            )
        )

        // 使用滑动窗口进行局部自适应过滤
        var filtered: [AudioPeak] = []
        let windowDuration: Double = 5.0  // 5秒滑动窗口

        for (index, peak) in peaks.enumerated() {
            // 获取窗口内的峰值（前后各 2.5 秒）
            let windowStart = peak.time - windowDuration / 2.0
            let windowEnd = peak.time + windowDuration / 2.0

            let windowPeaks = peaks.filter { $0.time >= windowStart && $0.time <= windowEnd }

            if windowPeaks.count >= 2 {
                // 计算窗口内的局部统计量
                let localConfidences = windowPeaks.map { $0.confidence }
                let localMean = localConfidences.reduce(0, +) / Double(localConfidences.count)
                let localVariance = localConfidences.map { pow($0 - localMean, 2) }.reduce(0, +) / Double(localConfidences.count)
                let localStdDev = sqrt(localVariance)

                // 局部自适应阈值（降低系数：从1.5改为1.2）
                let localThreshold = max(
                    adaptiveThreshold * 0.9,
                    localMean + 1.2 * localStdDev  // 使用 1.2 倍标准差（减少过度过滤）
                )

                // 如果峰值置信度高于局部阈值，保留
                if peak.confidence >= localThreshold {
                    filtered.append(peak)
                }
            } else {
                // 窗口内峰值太少，使用全局阈值
                if peak.confidence >= adaptiveThreshold {
                    filtered.append(peak)
                }
            }
        }

        // 更新诊断统计计数器
        if diagnosticMode {
            diagnosticCollector?.passedAdaptiveFiltering = filtered.count
        }

        return filtered
    }

    /// 后处理峰值：过滤和合并（优化：减少误合并）
    private func postProcessPeaks(_ peaks: [AudioPeak]) -> [AudioPeak] {
        guard !peaks.isEmpty else { return [] }

        var filtered: [AudioPeak] = []
        var currentPeak: AudioPeak? = nil

        for peak in peaks {
            if let current = currentPeak {
                // 优化：如果两个峰值时间非常接近（< 0.15 秒），保留置信度更高的
                // 但如果两个峰值都很高（都是明显的击球声），都保留
                let timeDiff = abs(peak.time - current.time)
                
                if timeDiff < config.minimumPeakInterval {
                    // 如果两个峰值都很高（都是明显的击球声），且间隔合理，都保留
                    // 统一阈值为0.55（从0.65降低，减少误合并）
                    if peak.confidence > 0.55 && current.confidence > 0.55 && timeDiff > 0.10 {
                        // 连续击球，都保留
                        filtered.append(current)
                        currentPeak = peak
                    } else {
                        // 保留置信度更高的
                        if peak.confidence > current.confidence {
                            currentPeak = peak
                        }
                    }
                } else {
                    // 保存当前峰值，开始新峰值
                    filtered.append(current)
                    currentPeak = peak
                }
            } else {
                currentPeak = peak
            }
        }

        // 添加最后一个峰值
        if let lastPeak = currentPeak {
            filtered.append(lastPeak)
        }

        // 更新诊断统计计数器
        if diagnosticMode {
            diagnosticCollector?.afterPostProcessing = filtered.count
        }

        return filtered
    }

    // MARK: - Diagnostic Helper Methods

    /// 记录诊断候选峰值（仅在诊断模式下）
    private func recordDiagnosticCandidate(
        time: Double,
        amplitude: Double,
        rms: Double,
        duration: Double,
        confidence: Double,
        spectralFeatures: SpectralFeatures,
        confidenceBreakdown: ConfidenceBreakdown,
        passed: Bool,
        rejectionReason: String?,
        rejectionStage: String?
    ) {
        guard diagnosticMode, let collector = diagnosticCollector else { return }

        let candidate = CandidatePeakData(
            time: time,
            amplitude: amplitude,
            rms: rms,
            duration: duration,
            confidence: confidence,
            confidenceBreakdown: confidenceBreakdown,
            spectralFeatures: spectralFeatures,
            passedFiltering: passed,
            rejectionReason: rejectionReason,
            rejectionStage: rejectionStage
        )

        collector.recordCandidate(candidate)
    }

    /// 提取置信度分解信息
    private func extractConfidenceBreakdown(
        peakAmplitude: Double,
        rms: Double,
        energyConcentration: Double,
        spectralAnalysis: SpectralAnalysis
    ) -> ConfidenceBreakdown {
        // 复制 calculateHitSoundConfidenceEnhanced 的逻辑
        let amplitudeScore = min(peakAmplitude / 0.6, 1.0) * 0.33
        let crestFactor = peakAmplitude / (rms + 0.001)
        let crestScore = min(crestFactor / 4.0, 1.0) * 0.23
        let energyScore = energyConcentration * 0.14

        let frequencyInPrimaryRange = spectralAnalysis.dominantFrequency >= 1000 &&
                                     spectralAnalysis.dominantFrequency <= 3000
        let frequencyScore = (frequencyInPrimaryRange ? 1.0 :
                           (spectralAnalysis.dominantFrequency >= 300 &&
                            spectralAnalysis.dominantFrequency <= 5000 ? 0.6 : 0.3)) * 0.14

        let highFreqScore = min(spectralAnalysis.highFreqEnergyRatio / 0.15, 1.0) * 0.14

        // 其他特征总和 (剩余 2%)
        let otherScore = 0.02

        return ConfidenceBreakdown(
            amplitudeScore: amplitudeScore,
            crestFactorScore: crestScore,
            energyConcentrationScore: energyScore,
            frequencyRangeScore: frequencyScore,
            highFreqEnergyScore: highFreqScore,
            otherFeaturesScore: otherScore
        )
    }

    /// 从 SpectralAnalysis 转换为 SpectralFeatures
    private func convertSpectralFeatures(_ analysis: SpectralAnalysis) -> SpectralFeatures {
        return SpectralFeatures(
            dominantFrequency: analysis.dominantFrequency,
            spectralCentroid: analysis.spectralCentroid,
            spectralRolloff: analysis.spectralRolloff,
            lowFreqEnergy: analysis.energyInLowFreq,
            primaryHitRangeEnergy: analysis.energyInPrimaryRange,
            highFreqEnergy: analysis.highFreqEnergyRatio,
            mfccMean: analysis.mfccCoefficients.isEmpty ? nil : Array(analysis.mfccCoefficients.prefix(5))
        )
    }
}

// MARK: - Supporting Types

/// 音频分析配置
struct AudioAnalysisConfiguration {
    /// 峰值阈值（归一化后的幅度）
    let peakThreshold: Double

    /// 最小置信度（低于此值的峰值会被过滤）
    let minimumConfidence: Double

    /// 最小峰值间隔（秒）- 太近的峰值会被合并
    let minimumPeakInterval: Double

    /// 配置预设名称
    var presetName: String {
        switch (peakThreshold, minimumConfidence) {
        case (0.25, 0.50): return "default"
        case (0.4, 0.6): return "strict"
        case (0.1, 0.25): return "lenient"
        case (0.18, 0.45): return "mobile_recording"
        default: return "custom"
        }
    }

    /// 默认配置（平衡准确率和召回率）
    static let `default` = AudioAnalysisConfiguration(
        peakThreshold: 0.25,  // 提高阈值，减少误报（原来0.15）
        minimumConfidence: 0.50,  // P1修复：降至0.50，减少AudioAnalyzer过度过滤（原0.55）
        minimumPeakInterval: 0.18  // 增加最小间隔，避免过于密集的误识别（原来0.12）
    )

    /// 严格配置（减少误报）
    static let strict = AudioAnalysisConfiguration(
        peakThreshold: 0.4,
        minimumConfidence: 0.6,
        minimumPeakInterval: 0.2
    )

    /// 宽松配置（提高召回率）
    static let lenient = AudioAnalysisConfiguration(
        peakThreshold: 0.1,  // 非常低的阈值
        minimumConfidence: 0.25,  // 非常低的置信度
        minimumPeakInterval: 0.08  // 允许非常密集的峰值
    )

    /// 手机录制配置（针对移动设备录制的视频优化）
    /// 适用于：整体音量偏低、峰值振幅较小的手机现场录制视频
    static let mobileRecording = AudioAnalysisConfiguration(
        peakThreshold: 0.18,  // 降低阈值以适应手机录制的较低音量
        minimumConfidence: 0.45,  // 适度降低置信度要求
        minimumPeakInterval: 0.18  // 保持与 default 相同的间隔
    )
}

// MARK: - Diagnostic Data Collector

/// 诊断数据收集器 - 收集音频分析过程中的所有中间数据
private class DiagnosticDataCollector {
    let videoInfo: VideoDiagnosticInfo
    let config: AudioAnalysisConfiguration

    var allCandidates: [CandidatePeakData] = []
    var finalPeaks: [CandidatePeakData] = []
    var rmsTimeSeries: [RMSDataPoint] = []
    var spectralSamples: [SpectralDataPoint] = []

    // 统计计数器
    var passedAmplitudeThreshold = 0
    var passedDurationCheck = 0
    var passedConfidenceThreshold = 0
    var passedAdaptiveFiltering = 0
    var afterPostProcessing = 0

    var rejectionReasons: [String: Int] = [:]

    // 全局音频特征
    var allRMSValues: [Double] = []
    var allPeakAmplitudes: [Double] = []

    init(videoInfo: VideoDiagnosticInfo, config: AudioAnalysisConfiguration) {
        self.videoInfo = videoInfo
        self.config = config
    }

    /// 记录候选峰值
    func recordCandidate(_ candidate: CandidatePeakData) {
        allCandidates.append(candidate)

        // 更新统计
        if candidate.passedFiltering {
            finalPeaks.append(candidate)
        }

        if let reason = candidate.rejectionReason {
            rejectionReasons[reason, default: 0] += 1
        }

        // 收集幅度数据
        allPeakAmplitudes.append(candidate.amplitude)
    }

    /// 记录 RMS 数据点
    func recordRMS(time: Double, rms: Double, peakAmplitude: Double?) {
        allRMSValues.append(rms)
        rmsTimeSeries.append(RMSDataPoint(time: time, rms: rms, peakAmplitude: peakAmplitude))
    }

    /// 记录频谱数据
    func recordSpectralData(time: Double, frequencyBins: [Double], magnitudes: [Double]) {
        spectralSamples.append(SpectralDataPoint(
            time: time,
            frequencyBins: frequencyBins,
            magnitudes: magnitudes
        ))
    }

    /// 生成完整的诊断数据
    func generateDiagnosticData() -> AudioDiagnosticData {
        // 计算全局音频特征
        let audioFeatures = calculateGlobalFeatures()

        // 计算过滤统计
        let stats = FilteringStatistics(
            totalCandidates: allCandidates.count,
            passedAmplitudeThreshold: passedAmplitudeThreshold,
            passedDurationCheck: passedDurationCheck,
            passedConfidenceThreshold: passedConfidenceThreshold,
            passedAdaptiveFiltering: passedAdaptiveFiltering,
            afterPostProcessing: afterPostProcessing,
            finalCount: finalPeaks.count,
            rejectionReasons: rejectionReasons,
            averageConfidence: finalPeaks.isEmpty ? 0 : finalPeaks.map { $0.confidence }.reduce(0, +) / Double(finalPeaks.count),
            medianConfidence: calculateMedian(finalPeaks.map { $0.confidence })
        )

        // 配置快照
        let configSnapshot = AudioConfigSnapshot(
            peakThreshold: config.peakThreshold,
            minimumConfidence: config.minimumConfidence,
            minimumPeakInterval: config.minimumPeakInterval,
            presetName: config.presetName
        )

        return AudioDiagnosticData(
            videoInfo: videoInfo,
            audioFeatures: audioFeatures,
            allCandidatePeaks: allCandidates,
            finalPeaks: finalPeaks,
            filteringStats: stats,
            rmsTimeSeries: rmsTimeSeries,
            spectralSamples: spectralSamples.isEmpty ? nil : spectralSamples,
            configuration: configSnapshot,
            timestamp: Date()
        )
    }

    private func calculateGlobalFeatures() -> AudioGlobalFeatures {
        let rmsValues = allRMSValues
        let peakAmps = allPeakAmplitudes

        return AudioGlobalFeatures(
            overallRMSMean: rmsValues.isEmpty ? 0 : rmsValues.reduce(0, +) / Double(rmsValues.count),
            overallRMSStdDev: calculateStdDev(rmsValues),
            overallRMSMax: rmsValues.max() ?? 0,
            overallRMSMedian: calculateMedian(rmsValues),
            overallRMSP90: calculatePercentile(rmsValues, percentile: 90),
            maxPeakAmplitude: peakAmps.max() ?? 0,
            medianPeakAmplitude: calculateMedian(peakAmps),
            dominantFrequencyRange: "未分析",  // TODO: 实际计算
            estimatedSNR: nil  // TODO: 实际计算
        )
    }

    private func calculateMedian(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid-1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

    private func calculateStdDev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    private func calculatePercentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * percentile / 100.0)
        return sorted[min(index, sorted.count - 1)]
    }
}

/// 音频分析错误
enum AudioAnalyzerError: LocalizedError {
    case noAudioTrack
    case readFailed
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "视频中没有音频轨道"
        case .readFailed:
            return "音频读取失败"
        case .invalidAudioFormat:
            return "不支持的音频格式"
        }
    }
}
