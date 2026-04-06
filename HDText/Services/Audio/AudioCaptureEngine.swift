import AVFoundation
import Accelerate

final class AudioCaptureEngine {
    private var audioEngine: AVAudioEngine?
    private var tapInstalled = false
    private(set) var isCapturing = false
    private(set) var currentLevel: Float = 0.0

    private var recordedChunks: [Data] = []
    private let chunksLock = NSLock()

    var onLevelUpdate: ((Float) -> Void)?

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    func startCapture(deviceID: String? = nil) throws {
        guard !isCapturing else { return }

        stopCapture()

        chunksLock.lock()
        recordedChunks.removeAll()
        chunksLock.unlock()

        let engine = AVAudioEngine()

        if let deviceID = deviceID, let device = AudioDeviceManager.device(forUID: deviceID) {
            AudioDeviceManager.setInputDevice(device, on: engine)
        }

        let inputNode = engine.inputNode

        engine.prepare()

        let outFmt = inputNode.outputFormat(forBus: 0)
        let inFmt = inputNode.inputFormat(forBus: 0)
        hdLog("inputNode outputFormat: \(outFmt.sampleRate) Hz, \(outFmt.channelCount) ch")
        hdLog("inputNode inputFormat:  \(inFmt.sampleRate) Hz, \(inFmt.channelCount) ch")

        let hwRate = inFmt.sampleRate > 0 ? inFmt.sampleRate : outFmt.sampleRate
        let hwCh = max(inFmt.channelCount, outFmt.channelCount)
        let hwFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hwRate,
            channels: max(hwCh, 1),
            interleaved: false
        )!
        hdLog("Using tap format: \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch")

        guard hwRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        var tapCallCount = 0
        let tapBlock: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            guard let self = self else { return }
            tapCallCount += 1
            if tapCallCount <= 2 {
                hdLog("Audio tap #\(tapCallCount) — \(buffer.frameLength) frames, \(buffer.format.sampleRate) Hz")
            }
            self.updateLevel(from: buffer)
            if let data = self.convertToInt16PCM(buffer: buffer) {
                self.chunksLock.lock()
                self.recordedChunks.append(data)
                self.chunksLock.unlock()
            }
        }

        do {
            try ObjCExceptionCatcher.`try` {
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat, block: tapBlock)
            }
        } catch {
            hdLog("installTap threw ObjC exception: \(error.localizedDescription)")
            throw AudioCaptureError.tapInstallFailed(error.localizedDescription)
        }
        tapInstalled = true
        hdLog("Tap installed OK")

        try engine.start()
        hdLog("Audio engine started, capturing...")

        self.audioEngine = engine
        self.isCapturing = true
    }

    @discardableResult
    func stopCapture() -> Data {
        if let engine = audioEngine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            audioEngine = nil
        }
        isCapturing = false
        currentLevel = 0

        chunksLock.lock()
        let allChunks = recordedChunks
        recordedChunks.removeAll()
        chunksLock.unlock()

        var combined = Data()
        for chunk in allChunks {
            combined.append(chunk)
        }
        hdLog("Audio stopped — \(combined.count) bytes from \(allChunks.count) chunks")
        return combined
    }

    private func convertToInt16PCM(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let srcRate = buffer.format.sampleRate
        let targetRate = 16000.0

        var monoSamples = [Float](repeating: 0, count: frameLength)
        if channelCount > 1 {
            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        } else {
            memcpy(&monoSamples, channelData[0], frameLength * MemoryLayout<Float>.size)
        }

        let resampledSamples: [Float]
        if abs(srcRate - targetRate) > 1.0 {
            let ratio = targetRate / srcRate
            let outputLength = Int(Double(frameLength) * ratio)
            guard outputLength > 0 else { return nil }

            var output = [Float](repeating: 0, count: outputLength)
            for i in 0..<outputLength {
                let srcIndex = Double(i) / ratio
                let idx = Int(srcIndex)
                let frac = Float(srcIndex - Double(idx))
                if idx + 1 < frameLength {
                    output[i] = monoSamples[idx] * (1 - frac) + monoSamples[idx + 1] * frac
                } else if idx < frameLength {
                    output[i] = monoSamples[idx]
                }
            }
            resampledSamples = output
        } else {
            resampledSamples = monoSamples
        }

        var int16Samples = [Int16](repeating: 0, count: resampledSamples.count)
        for i in 0..<resampledSamples.count {
            let clamped = max(-1.0, min(1.0, resampledSamples[i]))
            int16Samples[i] = Int16(clamped * 32767)
        }

        return Data(bytes: int16Samples, count: int16Samples.count * MemoryLayout<Int16>.size)
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = buffer.frameLength

        var rms: Float = 0
        vDSP_measqv(channelData[0], 1, &rms, vDSP_Length(frames))
        rms = sqrtf(rms)

        let db = 20 * log10f(max(rms, 1e-7))
        let normalized = max(0, min(1, (db + 50) / 50))

        currentLevel = normalized
        onLevelUpdate?(normalized)
    }

    /// Compute RMS energy of raw 16-bit PCM data. Returns 0.0–1.0.
    static func computeRMS(of pcmData: Data) -> Float {
        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        var sumSquared: Double = 0
        pcmData.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let normalized = Double(samples[i]) / 32767.0
                sumSquared += normalized * normalized
            }
        }
        return Float(sqrt(sumSquared / Double(sampleCount)))
    }

    /// Returns true if the audio is effectively silence (RMS below threshold).
    static func isSilence(_ pcmData: Data, threshold: Float = 0.008) -> Bool {
        let rms = computeRMS(of: pcmData)
        hdLog("Audio RMS: \(rms) (threshold: \(threshold))")
        return rms < threshold
    }
}

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case permissionDenied
    case tapInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone input device found"
        case .permissionDenied:
            return "Microphone permission denied. Check System Settings > Privacy > Microphone."
        case .tapInstallFailed(let reason):
            return "Audio tap install failed: \(reason)"
        }
    }
}
