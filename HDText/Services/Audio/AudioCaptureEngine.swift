import AVFoundation

/// Records 16 kHz mono Int16 PCM from one microphone.
///
/// Uses AVCaptureSession bound to the chosen device. AVAudioEngine's input node follows the
/// system default input: selecting another mic made it open the default device too (e.g. Bluetooth
/// headphones), whose profile switch fired a configuration change that stopped the engine ~1 s in.
///
/// Session setup, start and stop run on `sessionQueue`, never the caller's thread: they take ~0.3 s,
/// and the main thread also services the global hotkey event tap, so blocking it stalls every keystroke.
final class AudioCaptureEngine: NSObject {
    private var session: AVCaptureSession?  // sessionQueue only
    private let sessionQueue = DispatchQueue(label: "com.hdtext.audio-session")
    private let sampleQueue = DispatchQueue(label: "com.hdtext.audio-capture")
    private(set) var isCapturing = false
    private(set) var currentLevel: Float = 0.0

    private var recordedChunks: [Data] = []
    private let chunksLock = NSLock()
    private var bufferCount = 0
    private var accepting = false  // chunksLock; false drops buffers that arrive after stop
    private var startedAt: Date?

    var onLevelUpdate: ((Float) -> Void)?
    /// Called on the main queue if the microphone could not be started.
    var onCaptureError: ((Error) -> Void)?

    private static let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

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

    /// Returns immediately; the session starts on a background queue (errors go to `onCaptureError`).
    func startCapture(deviceID: String? = nil) throws {
        guard !isCapturing else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: throw AudioCaptureError.permissionDenied
        default: break
        }

        chunksLock.lock()
        recordedChunks.removeAll()
        bufferCount = 0
        accepting = true
        chunksLock.unlock()

        startedAt = Date()
        isCapturing = true
        sessionQueue.async { [weak self] in
            self?.startSession(deviceID: deviceID)
        }
    }

    @discardableResult
    func stopCapture() -> Data {
        chunksLock.lock()
        accepting = false
        let allChunks = recordedChunks
        let buffers = bufferCount
        recordedChunks.removeAll()
        bufferCount = 0
        chunksLock.unlock()

        if isCapturing {
            sessionQueue.async { [weak self] in self?.stopSession() }
        }
        isCapturing = false
        currentLevel = 0

        var combined = Data()
        for chunk in allChunks {
            combined.append(chunk)
        }
        let seconds = Double(combined.count) / 32000
        hdLog("Audio stopped — \(combined.count) bytes (\(String(format: "%.2f", seconds)) s) from \(buffers) buffers")
        if let startedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed > 1.5, seconds < elapsed * 0.6 {
                hdLogWarning(String(format: "Microphone delivered only %.2f s of audio in %.2f s of recording", seconds, elapsed))
            }
        }
        startedAt = nil
        return combined
    }

    private func startSession(deviceID: String?) {
        stopSession()
        do {
            guard let device = Self.captureDevice(forUID: deviceID) else {
                throw AudioCaptureError.noInputDevice
            }
            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: device)
            } catch {
                if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                    throw AudioCaptureError.permissionDenied
                }
                throw AudioCaptureError.captureFailed(error.localizedDescription)
            }

            let output = AVCaptureAudioDataOutput()
            output.audioSettings = Self.outputSettings
            output.setSampleBufferDelegate(self, queue: sampleQueue)

            let session = AVCaptureSession()
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                throw AudioCaptureError.captureFailed("Could not attach \(device.localizedName)")
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()

            NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                                                   name: AVCaptureSession.runtimeErrorNotification, object: session)
            session.startRunning()
            self.session = session
            hdLog("Capture started — \(device.localizedName)")
        } catch {
            hdLogWarning("Microphone failed to start: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in self?.onCaptureError?(error) }
        }
    }

    private func stopSession() {
        guard let session else { return }
        session.stopRunning()
        NotificationCenter.default.removeObserver(self, name: AVCaptureSession.runtimeErrorNotification, object: session)
        self.session = nil
    }

    /// The device with this CoreAudio UID (AVCaptureDevice.uniqueID matches it on macOS), else the system default.
    private static func captureDevice(forUID uid: String?) -> AVCaptureDevice? {
        if let uid, !uid.isEmpty {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
            ).devices
            if let match = devices.first(where: { $0.uniqueID == uid }) {
                return match
            }
            hdLog("Selected microphone \(uid) not found — using system default")
        }
        return AVCaptureDevice.default(for: .audio)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        hdLog("Capture session runtime error: \(error?.localizedDescription ?? "unknown")")
    }

    private func updateLevel(from chunk: Data) {
        let rms = Self.computeRMS(of: chunk)
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

extension AudioCaptureEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return }

        var chunk = Data(count: length)
        let status = chunk.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { return }

        chunksLock.lock()
        let keep = accepting
        if keep {
            recordedChunks.append(chunk)
            bufferCount += 1
        }
        chunksLock.unlock()

        if keep { updateLevel(from: chunk) }
    }
}

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case permissionDenied
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone input device found"
        case .permissionDenied:
            return "Microphone permission denied. Check System Settings > Privacy > Microphone."
        case .captureFailed(let reason):
            return "Microphone capture failed: \(reason)"
        }
    }
}
