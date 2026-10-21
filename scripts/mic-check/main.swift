import AVFoundation

// Records a few seconds from each microphone through the app's AudioCaptureEngine and reports how
// much audio arrived. Healthy: audio seconds ≈ recording seconds for every device, including
// non-default ones (the 2026-10 bug delivered ~1 s then stopped when a Bluetooth headset was default).
let seconds = 4.0
var targets: [(name: String, uid: String?)] = CommandLine.arguments.dropFirst().map { ($0, $0) }
if targets.isEmpty {
    targets = [("system default", nil)] + AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
    ).devices.map { ($0.localizedName, $0.uniqueID) }
}

var failures = 0
for target in targets {
    let engine = AudioCaptureEngine()
    do {
        try engine.startCapture(deviceID: target.uid)
    } catch {
        print("FAIL  \(target.name): \(error.localizedDescription)")
        failures += 1
        continue
    }
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    let data = engine.stopCapture()
    let audio = Double(data.count) / 32000
    let ok = audio >= seconds * 0.9
    if !ok { failures += 1 }
    print(String(format: "%@  %@: recorded %.1f s → %.2f s of audio, RMS %.4f",
                 ok ? "OK  " : "FAIL", target.name, seconds, audio, AudioCaptureEngine.computeRMS(of: data)))
}
exit(failures == 0 ? 0 : 2)
