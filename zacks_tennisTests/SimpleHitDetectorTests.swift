import Testing
@testable import Zacks网球视频剪辑

struct SimpleHitDetectorTests {
    @Test("攻击时间估计会保留慢起音瞬态")
    func estimateAttackTimeKeepsSlowAttackEnvelope() {
        let sampleRate = 44_100.0
        let peakValue: Float = 1.0
        let rampSamples = Int(sampleRate * 0.018)
        var window = [Float](repeating: 0, count: 1_024)

        for index in 0..<rampSamples {
            window[index] = peakValue * Float(index) / Float(rampSamples)
        }
        window[rampSamples] = peakValue

        let attackTime = SimpleHitDetectorTestSupport.estimateAttackTime(window: window, sampleRate: sampleRate)

        #expect(attackTime > 0.015)
    }

    @Test("攻击时间估计仍能识别快速击球瞬态")
    func estimateAttackTimeStillDetectsFastAttackEnvelope() {
        let sampleRate = 44_100.0
        let peakValue: Float = 1.0
        let rampSamples = Int(sampleRate * 0.003)
        var window = [Float](repeating: 0, count: 1_024)

        for index in 0..<rampSamples {
            window[index] = peakValue * Float(index) / Float(rampSamples)
        }
        window[rampSamples] = peakValue

        let attackTime = SimpleHitDetectorTestSupport.estimateAttackTime(window: window, sampleRate: sampleRate)

        #expect(attackTime < 0.005)
    }
}
