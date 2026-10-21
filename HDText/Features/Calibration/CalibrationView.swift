import SwiftUI
import AVFoundation

struct CalibrationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = CalibrationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Microphone Calibration")
                .font(.title2.bold())

            currentDeviceInfo

            levelMeter

            testPhraseSection

            resultSection

            controlButtons
        }
        .padding(24)
        .onAppear {
            viewModel.setup(with: appState)
        }
        .onDisappear {
            viewModel.stopCalibration()
        }
    }

    private var currentDeviceInfo: some View {
        HStack {
            Image(systemName: "mic.fill")
                .foregroundStyle(.blue)
            if let micID = appState.selectedMicrophoneID,
               let device = AudioDeviceManager.device(forUID: micID) {
                Text("Using: \(device.name)")
            } else if let defaultDevice = AudioDeviceManager.defaultInputDevice() {
                Text("Using: \(defaultDevice.name) (system default)")
            } else {
                Text("No microphone detected")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
    }

    private var levelMeter: some View {
        VStack(spacing: 8) {
            Text("Input Level")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelColor)
                        .frame(width: geo.size.width * CGFloat(viewModel.currentLevel))
                        .animation(.easeOut(duration: 0.08), value: viewModel.currentLevel)
                }
            }
            .frame(height: 16)

            HStack {
                Text("Quiet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Loud")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var levelColor: Color {
        if viewModel.currentLevel < 0.3 { return .green }
        if viewModel.currentLevel < 0.7 { return .yellow }
        return .red
    }

    private var testPhraseSection: some View {
        VStack(spacing: 8) {
            Text("Read this phrase to test your microphone:")
                .font(.subheadline)

            Text(viewModel.testPhrase)
                .font(.body.italic())
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if viewModel.isCalibrating {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Listening...")
                    .foregroundStyle(.blue)
            }
        }

        if !viewModel.calibrationResult.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Heard:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.calibrationResult)
                    .font(.body)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(6)
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 12) {
            Button(viewModel.isCalibrating ? "Stop" : "Start Test") {
                if viewModel.isCalibrating {
                    viewModel.stopCalibration()
                } else {
                    viewModel.startCalibration()
                }
            }
            .buttonStyle(.borderedProminent)

            if !viewModel.calibrationResult.isEmpty {
                Button("Done") {
                    appState.isCalibrated = true
                    dismiss()
                }
            }
        }
    }
}

@MainActor
final class CalibrationViewModel: ObservableObject {
    @Published var currentLevel: Float = 0
    @Published var isCalibrating = false
    @Published var calibrationResult = ""

    let testPhrase = "The quick brown fox jumps over the lazy dog near the river bank on a warm summer evening."

    private var appState: AppState?
    private var captureEngine: AudioCaptureEngine?

    func setup(with appState: AppState) {
        self.appState = appState
    }

    func startCalibration() {
        guard let appState = appState else { return }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startCalibration()
                    } else {
                        self?.calibrationResult = "Microphone permission denied. Open System Settings > Privacy & Security > Microphone and enable HDText."
                    }
                }
            }
            return
        } else if micStatus != .authorized {
            calibrationResult = "Microphone permission denied. Open System Settings > Privacy & Security > Microphone and enable HDText."
            return
        }

        isCalibrating = true
        calibrationResult = ""

        let engine = AudioCaptureEngine()
        self.captureEngine = engine

        engine.onLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.currentLevel = level
            }
        }
        engine.onCaptureError = { [weak self] error in
            self?.isCalibrating = false
            self?.calibrationResult = "Microphone error: \(error.localizedDescription)"
        }

        do {
            try engine.startCapture(deviceID: appState.selectedMicrophoneID)
        } catch {
            isCalibrating = false
            calibrationResult = "Microphone error: \(error.localizedDescription)"
            hdLog("Calibration capture error: \(error.localizedDescription)")
        }
    }

    func stopCalibration() {
        guard let appState = appState else {
            captureEngine = nil
            isCalibrating = false
            currentLevel = 0
            return
        }

        let audioData = captureEngine?.stopCapture() ?? Data()
        captureEngine = nil
        currentLevel = 0

        guard !audioData.isEmpty,
              let apiKey = appState.apiKey else {
            isCalibrating = false
            return
        }

        Task {
            do {
                let transcript = try await appState.geminiTranscriptionService.transcribe(
                    audioData: audioData,
                    modelName: appState.transcriptionModelAPIName,
                    apiKey: apiKey
                )
                await MainActor.run {
                    self.calibrationResult = transcript
                    self.isCalibrating = false
                }
            } catch {
                await MainActor.run {
                    self.calibrationResult = "Could not transcribe: \(error.localizedDescription)"
                    self.isCalibrating = false
                }
            }
        }
    }
}
