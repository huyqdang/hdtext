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

        guard let resampler = PCM16Resampler(inputFormat: hwFormat) else {
            throw AudioCaptureError.tapInstallFailed("Could not create 16 kHz converter")
        }

        var tapCallCount = 0
        let tapBlock: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            guard let self = self else { return }
            tapCallCount += 1
            if tapCallCount <= 2 {
                hdLog("Audio tap #\(tapCallCount) — \(buffer.frameLength) frames, \(buffer.format.sampleRate) Hz")
            }
            self.updateLevel(from: buffer)
            if let data = resampler.convert(buffer) {
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

/// Streams capture buffers into 16 kHz mono Int16 PCM with proper anti-aliased resampling.
final class PCM16Resampler {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat, targetSampleRate: Double = 16000) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate,
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: output) else { return nil }
        converter.downmix = true
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0 else { return nil }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            hdLog("Resampler error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        guard out.frameLength > 0, let channel = out.int16ChannelData else { return nil }
        return Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
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
