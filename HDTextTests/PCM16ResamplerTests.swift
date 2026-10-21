import XCTest
import AVFoundation
@testable import HDText

final class PCM16ResamplerTests: XCTestCase {
    func testStereo48kBecomesMono16kWithSignal() throws {
        let input = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false))
        let resampler = try XCTUnwrap(PCM16Resampler(inputFormat: input))

        var total = Data()
        var phase = 0.0
        for _ in 0..<10 {   // 10 × 4800 frames = 1 s of 440 Hz tone
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
            buffer.frameLength = 4800
            for i in 0..<4800 {
                let v = Float(sin(phase) * 0.5)
                buffer.floatChannelData![0][i] = v
                buffer.floatChannelData![1][i] = v
                phase += 2 * .pi * 440 / 48000
            }
            if let chunk = resampler.convert(buffer) { total.append(chunk) }   // converter may buffer the first chunk
        }

        let samples = total.count / 2
        XCTAssertEqual(Double(samples), 16000, accuracy: 400)
        XCTAssertGreaterThan(AudioCaptureEngine.computeRMS(of: total), 0.2)
    }
}
