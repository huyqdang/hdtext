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
    let called = Date()
    do {
        try engine.startCapture(deviceID: target.uid)
        let blockedMs = Date().timeIntervalSince(called) * 1000
        if blockedMs > 20 { print(String(format: "SLOW  %@: startCapture blocked the caller %.0f ms", target.name, blockedMs)); failures += 1 }
    } catch {
        print("FAIL  \(target.name): \(error.localizedDescription)")
        failures += 1
        continue
    }
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    let stopCalled = Date()
    let data = engine.stopCapture()
    let stopMs = Date().timeIntervalSince(stopCalled) * 1000
    if stopMs > 20 { print(String(format: "SLOW  %@: stopCapture blocked the caller %.0f ms", target.name, stopMs)); failures += 1 }
    let audio = Double(data.count) / 32000
    let ok = audio >= seconds * 0.85  // start is asynchronous (~0.3 s)
    if !ok { failures += 1 }
    print(String(format: "%@  %@: recorded %.1f s → %.2f s of audio, RMS %.4f",
                 ok ? "OK  " : "FAIL", target.name, seconds, audio, AudioCaptureEngine.computeRMS(of: data)))
}
exit(failures == 0 ? 0 : 2)
