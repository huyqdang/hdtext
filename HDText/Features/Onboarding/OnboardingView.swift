import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var apiKeyInput = ""
    @State private var micGranted = false
    @State private var axGranted = false
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 4
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                permissionsStep.tag(1)
                apiKeyStep.tag(2)
                readyStep.tag(3)
            }
            .tabViewStyle(.automatic)

            navigationButtons
        }
        .padding(24)
        .onAppear {
            refreshPermissions()
        }
        .onReceive(permissionTimer) { _ in
            if currentStep == 1 {
                refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.bottom, 20)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to HDText")
                .font(.title.bold())

            Text("Hold a keyboard shortcut to dictate, release to get clean, polished text inserted right where you're typing.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions Needed")
                .font(.title2.bold())

            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                description: micGranted
                    ? "Microphone access granted."
                    : "Tap the button below, then allow microphone access.",
                granted: micGranted
            )

            permissionRow(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: axGranted
                    ? "Accessibility access granted."
                    : "Add HDText in System Settings > Privacy & Security > Accessibility.",
                granted: axGranted
            )

            HStack(spacing: 12) {
                if !micGranted {
                    Button("Request Microphone") {
                        let status = AVCaptureDevice.authorizationStatus(for: .audio)
                        if status == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                Task { @MainActor in
                                    micGranted = granted
                                }
                            }
                        } else {
                            openPrivacySettings("Microphone")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !axGranted {
                    Button("Open Accessibility Settings") {
                        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if micGranted && axGranted {
                Label("All permissions granted!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Text("Permissions update automatically. If you already granted access, wait a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Open System Settings") {
                openPrivacySettings("Privacy")
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gemini API Key")
                .font(.title2.bold())

            Text("HDText uses Google's Gemini AI to transcribe and clean up your speech. Enter your API key below.")
                .font(.body)
                .foregroundStyle(.secondary)

            SecureField("Paste your Gemini API key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)

            Button("Save Key") {
                if appState.keychainStore.saveAPIKey(apiKeyInput) {
                    appState.objectWillChange.send()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

            if appState.hasAPIKey {
                Label("API key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Link("Get a free Gemini API key",
                 destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var hotkeyActive = false
    private let hotkeyTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 8) {
                instructionRow("Hold \(appState.hotkeyManager.shortcutDescription) to start dictating")
                instructionRow("Release the shortcut when you're done")
                instructionRow("Your cleaned text will be typed into the active app")
                instructionRow("Double-tap the shortcut for hands-free mode")
            }

            if hotkeyActive {
                Label("Hotkeys active — ready to use!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.green)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 10) {
                    Button {
                        activateHotkey()
                    } label: {
                        Label("Activate Hotkeys", systemImage: "bolt.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Grants HDText the ability to listen for your keyboard shortcut.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            }

            Text("You can change the shortcut, models, and other settings from the menu bar icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            hotkeyActive = appState.hotkeyManager.isMonitoring
        }
        .onReceive(hotkeyTimer) { _ in
            if currentStep == 3 {
                hotkeyActive = appState.hotkeyManager.isMonitoring
            }
        }
    }

    private func activateHotkey() {
        if AXIsProcessTrusted() {
            appState.hotkeyManager.startMonitoring()
        }
        if !appState.hotkeyManager.isMonitoring {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.ensureAccessibilityThenStart()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            hotkeyActive = appState.hotkeyManager.isMonitoring
        }
    }

    private func instructionRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.blue)
            Text(text)
                .font(.body)
        }
    }

    private func permissionRow(icon: String, title: String, description: String, granted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(granted ? .green : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
        }
        .padding(10)
        .background(granted ? Color.green.opacity(0.04) : Color.red.opacity(0.04))
        .cornerRadius(8)
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Continue") {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    appState.isOnboardingComplete = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 16)
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
