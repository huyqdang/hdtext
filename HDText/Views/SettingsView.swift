import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedSection: SettingsSection = .general
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var availableDevices: [AudioDevice] = []
    @State private var isRecordingShortcut = false
    @State private var apiKeySaveStatus: APIKeySaveStatus = .none

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, models, microphone, apiKey, history, calibration, debug
        var id: String { rawValue }

        var label: String {
            switch self {
            case .general:     return "General"
            case .models:      return "Models"
            case .microphone:  return "Microphone"
            case .apiKey:      return "API Key"
            case .history:     return "History"
            case .calibration: return "Calibration"
            case .debug:       return "Debug"
            }
        }

        var icon: String {
            switch self {
            case .general:     return "gear"
            case .models:      return "cpu"
            case .microphone:  return "mic"
            case .apiKey:      return "key"
            case .history:     return "clock.arrow.circlepath"
            case .calibration: return "waveform"
            case .debug:       return "ladybug"
            }
        }
    }

    enum APIKeySaveStatus: Equatable {
        case none, saved, removed, failed
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentPanel
        }
        .frame(width: 700, height: 520)
        .onAppear {
            availableDevices = AudioDeviceManager.availableInputDevices()
            if let key = appState.keychainStore.retrieveAPIKey() {
                apiKeyInput = key
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                if section == .history {
                    Divider().padding(.horizontal, 12).padding(.vertical, 4)
                }
                sidebarItem(section)
            }
            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(appState.hotkeyManager.isMonitoring ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(appState.hotkeyManager.isMonitoring ? "Hotkey Active" : "Hotkey Inactive")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(section.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Content

    private var contentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedSection {
                case .general:     generalContent
                case .models:      modelsContent
                case .microphone:  microphoneContent
                case .apiKey:      apiKeyContent
                case .history:     historyContent
                case .calibration: calibrationContent
                case .debug:       debugContent
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("General")

            GroupBox("Shortcut") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Hold-to-talk:")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                        ShortcutRecorderView(
                            isRecording: $isRecordingShortcut
                        ) { modifiers, keyCode in
                            appState.hotkeyManager.updateShortcut(modifiers: modifiers, keyCode: keyCode)
                        }
                    }
                    Text("Click the badge, then press your desired key combo.")
                        .font(.caption).foregroundStyle(.secondary)

                    Divider()

                    HStack(spacing: 12) {
                        Circle()
                            .fill(appState.hotkeyManager.isMonitoring ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.hotkeyManager.isMonitoring ? "Hotkeys are active" : "Hotkeys are not active")
                            .font(.subheadline)

                        Spacer()

                        Button {
                            if AXIsProcessTrusted() {
                                appState.hotkeyManager.startMonitoring()
                            }
                            if !appState.hotkeyManager.isMonitoring {
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.ensureAccessibilityThenStart()
                                }
                            }
                        } label: {
                            Label(
                                appState.hotkeyManager.isMonitoring ? "Reactivate" : "Activate Hotkeys",
                                systemImage: "bolt.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(8)
            }

            GroupBox("Cleanup Style") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(RewriteAggressiveness.allCases) { level in
                        HStack(spacing: 10) {
                            Image(systemName: appState.rewriteAggressiveness == level ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(appState.rewriteAggressiveness == level ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(level.displayName).font(.body)
                                Text(level.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { appState.rewriteAggressiveness = level }
                    }
                }
                .padding(8)
            }

            GroupBox("Smart Correction") {
                Toggle(isOn: $appState.smartCorrectionEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Predict misrecognized words").font(.body)
                        Text("Replace words that don't fit the sentence with the most likely intended word")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            GroupBox("Status Indicator & Modes") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        SoundWaveBars()
                            .frame(width: 14, height: 14).padding(2)
                            .background(Circle().fill(.green))
                        Text("Recording").font(.caption)
                        SpinnerArc()
                            .frame(width: 14, height: 14).padding(2)
                            .background(Circle().fill(.blue))
                            .padding(.leading, 8)
                        Text("Processing").font(.caption)
                        Circle().fill(.red).frame(width: 14, height: 14)
                            .padding(.leading, 8)
                        Text("Error").font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.top, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hold shortcut to record, release to finish.").font(.caption)
                        Text("Double-tap shortcut for hands-free mode. Double-tap again to stop.")
                            .font(.caption).foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Models

    private var modelsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Models")

            GroupBox("Transcription Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Used for speech-to-text transcription and cleanup.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Model:", selection: $appState.selectedTranscriptionModelID) {
                        ForEach(GeminiModelCatalog.transcriptionModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Refine Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Used for the Refine text actions (Elaborate, Polish, etc).")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Model:", selection: $appState.selectedRewriteModelID) {
                        ForEach(GeminiModelCatalog.textModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Flash Lite is fastest. Flash is a good balance. Pro is highest quality but slower.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(4)
            }
        }
    }

    // MARK: - Microphone

    private var microphoneContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Microphone")

            GroupBox("Input Device") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Microphone:", selection: Binding(
                        get: { appState.selectedMicrophoneID ?? "" },
                        set: { appState.selectedMicrophoneID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("System Default").tag("")
                        ForEach(availableDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }

                    HStack {
                        Button("Refresh Devices") {
                            availableDevices = AudioDeviceManager.availableInputDevices()
                        }
                        Spacer()
                    }

                    if let defaultDevice = AudioDeviceManager.defaultInputDevice() {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text("Current system default: \(defaultDevice.name)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - API Key

    private var apiKeyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("API Key")

            GroupBox("Gemini API Key") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if showAPIKey {
                            TextField("Paste your API key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Paste your API key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }

                    HStack(spacing: 10) {
                        Button("Save Key") {
                            let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if appState.keychainStore.saveAPIKey(trimmed) {
                                apiKeySaveStatus = .saved
                                appState.objectWillChange.send()
                            } else {
                                apiKeySaveStatus = .failed
                            }
                            clearStatusAfterDelay()
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Key") {
                            appState.keychainStore.deleteAPIKey()
                            apiKeyInput = ""
                            apiKeySaveStatus = .removed
                            appState.objectWillChange.send()
                            clearStatusAfterDelay()
                        }
                        .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.red)

                        Spacer()
                        statusBadge
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield").foregroundStyle(.secondary)
                        Text("Stored securely in the macOS Keychain.").foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        Label("Get a Gemini API key", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch apiKeySaveStatus {
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green).transition(.opacity)
        case .removed:
            Label("Removed", systemImage: "minus.circle.fill")
                .font(.caption).foregroundStyle(.orange).transition(.opacity)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red).transition(.opacity)
        case .none:
            EmptyView()
        }
    }

    private func clearStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { apiKeySaveStatus = .none }
        }
    }

    // MARK: - History

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Transcription History")
                Spacer()
                Text("\(appState.historyStore.records.count) entries")
                    .font(.caption).foregroundStyle(.secondary)

                Button("Open in Window") {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showHistoryWindow()
                    }
                }
                .controlSize(.small)
            }

            if appState.historyStore.records.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("No transcriptions yet")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Use the hotkey to start dictating.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.historyStore.records.prefix(30)) { record in
                        historyRow(record)
                    }
                }
            }
        }
    }

    private func historyRow(_ record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.cleanedText)
                .font(.system(.body, design: .default))
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(record.targetApp)
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
                Spacer()
                Text(relativeTime(record.timestamp))
                    .font(.caption2).foregroundStyle(.secondary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.cleanedText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Calibration

    private var calibrationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Microphone Calibration")
            CalibrationInlineView()
                .environmentObject(appState)
        }
    }

    // MARK: - Debug

    private var debugContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Debug")
                Spacer()
                Text("\(appState.errorLog.entries.count)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Button("Clear") { appState.errorLog.clear() }
                    .controlSize(.small)
            }

            if appState.errorLog.entries.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28)).foregroundStyle(.green)
                        Text("No events yet")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                List(appState.errorLog.entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.timeString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Circle()
                            .fill(levelColor(entry.level))
                            .frame(width: 8, height: 8).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message).font(.caption).fontWeight(.medium)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }

            GroupBox {
                HStack(spacing: 8) {
                    Text("Hotkey: \(appState.hotkeyManager.isMonitoring ? "Active" : "Inactive")")
                        .font(.caption)
                    Text("·").foregroundStyle(.secondary)
                    Text("Mode: \(appState.mode.rawValue)").font(.caption)
                    Text("·").foregroundStyle(.secondary)
                    Text("Lock: \(appState.isLockMode ? "ON" : "OFF")").font(.caption)
                    Spacer()
                }
                .padding(4)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3).fontWeight(.semibold)
            .padding(.bottom, 4)
    }

    private func levelColor(_ level: ErrorLog.Entry.Level) -> Color {
        switch level {
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .blue
        }
    }
}

// MARK: - Inline Calibration View (embedded in settings)

struct CalibrationInlineView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = CalibrationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            currentDeviceInfo
            levelMeter
            testPhraseSection
            resultSection
            controlButtons
        }
        .onAppear { viewModel.setup(with: appState) }
        .onDisappear { viewModel.stopCalibration() }
    }

    private var currentDeviceInfo: some View {
        HStack {
            Image(systemName: "mic.fill").foregroundStyle(.blue)
            if let micID = appState.selectedMicrophoneID,
               let device = AudioDeviceManager.device(forUID: micID) {
                Text("Using: \(device.name)")
            } else if let defaultDevice = AudioDeviceManager.defaultInputDevice() {
                Text("Using: \(defaultDevice.name) (system default)")
            } else {
                Text("No microphone detected").foregroundStyle(.red)
            }
        }
        .font(.subheadline)
    }

    private var levelMeter: some View {
        VStack(spacing: 8) {
            Text("Input Level").font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelColor)
                        .frame(width: geo.size.width * CGFloat(viewModel.currentLevel))
                        .animation(.easeOut(duration: 0.08), value: viewModel.currentLevel)
                }
            }
            .frame(height: 14)

            HStack {
                Text("Quiet").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Loud").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var levelColor: Color {
        if viewModel.currentLevel < 0.3 { return .green }
        if viewModel.currentLevel < 0.7 { return .yellow }
        return .red
    }

    private var testPhraseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read this phrase to test your microphone:").font(.subheadline)
            Text(viewModel.testPhrase)
                .font(.body.italic())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if viewModel.isCalibrating {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Listening...").foregroundStyle(.blue)
            }
        }
        if !viewModel.calibrationResult.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Heard:").font(.caption).foregroundStyle(.secondary)
                Text(viewModel.calibrationResult)
                    .font(.body).padding(10)
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
                Button("Mark as Calibrated") {
                    appState.isCalibrated = true
                }
                .buttonStyle(.bordered)

                if appState.isCalibrated {
                    Label("Calibrated", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
    }
}
