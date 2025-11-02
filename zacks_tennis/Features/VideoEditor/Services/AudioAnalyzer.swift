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

    /// 音频分析配置
    private let config: AudioAnalysisConfiguration

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
        let samplesPerBuffer = Int(sampleRate) / 10 // 每 0.1 秒分析一次

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

        // 5. 后处理：过滤和合并相近的峰值
        let filteredPeaks = postProcessPeaks(audioPeaks)

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

    // MARK: - Private Methods - Analysis

    /// 分析单个音频样本缓冲区
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

        // 1. 计算 RMS（均方根）功率
        let rms = calculateRMS(samples: samples)

        // 2. 计算峰值功率
        let peakAmplitude = calculatePeakAmplitude(samples: samples)

        // 3. 判断是否是显著峰值
        let isPeak = peakAmplitude > config.peakThreshold

        guard isPeak else { return nil }

        // 4. 计算置信度（基于多个特征）
        let confidence = calculateHitSoundConfidence(
            rms: rms,
            peakAmplitude: peakAmplitude,
            samples: samples,
            sampleRate: sampleRate
        )

        // 5. 只返回置信度足够高的峰值
        if confidence >= config.minimumConfidence {
            return AudioPeak(
                time: timestamp,
                amplitude: peakAmplitude,
                confidence: confidence
            )
        }

        return nil
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

    /// 计算是击球声的置信度
    /// - Parameters:
    ///   - rms: RMS 功率
    ///   - peakAmplitude: 峰值幅度
    ///   - samples: 音频样本
    ///   - sampleRate: 采样率
    /// - Returns: 置信度 (0-1)
    private func calculateHitSoundConfidence(
        rms: Double,
        peakAmplitude: Double,
        samples: [Int16],
        sampleRate: Double
    ) -> Double {

        var confidence: Double = 0.0

        // 特征1：峰值与 RMS 的比值（击球声是短促的高峰值）
        // 峰值比 RMS 高很多说明是瞬时的强声音
        let crestFactor = peakAmplitude / (rms + 0.001) // 避免除零
        let crestScore = min(crestFactor / 5.0, 1.0) // 归一化到 0-1
        confidence += crestScore * 0.4 // 40% 权重

        // 特征2：峰值幅度（越高越可能是击球声）
        let amplitudeScore = min(peakAmplitude / 0.8, 1.0) // 0.8 以上认为是强峰值
        confidence += amplitudeScore * 0.3 // 30% 权重

        // 特征3：信号能量集中度（击球声能量集中）
        let energyConcentration = calculateEnergyConcentration(samples: samples)
        confidence += energyConcentration * 0.2 // 20% 权重

        // 特征4：零交叉率（击球声的频率特征）
        let zeroCrossingRate = calculateZeroCrossingRate(samples: samples)
        let zcrScore = zeroCrossingRate > 0.1 && zeroCrossingRate < 0.5 ? 1.0 : 0.5
        confidence += zcrScore * 0.1 // 10% 权重

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

    /// 后处理峰值：过滤和合并
    private func postProcessPeaks(_ peaks: [AudioPeak]) -> [AudioPeak] {
        guard !peaks.isEmpty else { return [] }

        var filtered: [AudioPeak] = []
        var currentPeak: AudioPeak? = nil

        for peak in peaks {
            if let current = currentPeak {
                // 如果两个峰值时间非常接近（< 0.2 秒），保留置信度更高的
                if abs(peak.time - current.time) < config.minimumPeakInterval {
                    if peak.confidence > current.confidence {
                        currentPeak = peak
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

        return filtered
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

    /// 默认配置
    static let `default` = AudioAnalysisConfiguration(
        peakThreshold: 0.4,
        minimumConfidence: 0.5,
        minimumPeakInterval: 0.2
    )

    /// 严格配置（减少误报）
    static let strict = AudioAnalysisConfiguration(
        peakThreshold: 0.6,
        minimumConfidence: 0.7,
        minimumPeakInterval: 0.3
    )

    /// 宽松配置（提高召回率）
    static let lenient = AudioAnalysisConfiguration(
        peakThreshold: 0.3,
        minimumConfidence: 0.4,
        minimumPeakInterval: 0.15
    )
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
