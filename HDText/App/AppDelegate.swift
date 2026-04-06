import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var overlayController: OverlayPanelController?
    private var refinePreviewController: RefinePreviewController?
    private var cancellables = Set<AnyCancellable>()
    private var listeningTimer: Timer?

    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var calibrationWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // Double-tap state
    private var dictationStartTime: Date?
    private var lastTapEndTime: Date?
    private var doubleTapTimer: Timer?
    private var lockExitTapTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(appState: appState)
        overlayController = OverlayPanelController(appState: appState)
        refinePreviewController = RefinePreviewController()
        setupDictationPipeline()

        NSApp.servicesProvider = self
        NSApp.registerServicesMenuSendTypes([.string], returnTypes: [.string])
        NSUpdateDynamicServices()
        hdLog("Services registered — provider set, dynamic services updated")

        let shouldOnboard = !appState.isOnboardingComplete || !appState.hasAPIKey
        if shouldOnboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboardingWindow()
            }
        } else {
            ensureAccessibilityThenStart()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Accessibility

    private var accessibilityTimer: Timer?

    func ensureAccessibilityThenStart() {
        AudioCaptureEngine.requestPermission { granted in
            hdLog("Microphone permission: \(granted ? "granted" : "denied")")
        }
        attemptStartMonitoring()
    }

    private func attemptStartMonitoring() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil

        if !AXIsProcessTrusted() {
            hdLog("Accessibility: NOT granted — prompting and polling")
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        var attempts = 0
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            attempts += 1
            guard let self = self else { timer.invalidate(); return }
            DispatchQueue.main.async {
                if !AXIsProcessTrusted() {
                    if attempts % 5 == 0 { hdLog("Still waiting for Accessibility (attempt \(attempts))") }
                    return
                }
                if self.appState.hotkeyManager.isMonitoring {
                    timer.invalidate(); self.accessibilityTimer = nil; return
                }
                self.appState.hotkeyManager.startMonitoring()
                if self.appState.hotkeyManager.isMonitoring {
                    timer.invalidate(); self.accessibilityTimer = nil; self.playSound("Purr")
                }
            }
        }

        DispatchQueue.main.async {
            if AXIsProcessTrusted() {
                self.appState.hotkeyManager.startMonitoring()
                if self.appState.hotkeyManager.isMonitoring {
                    self.accessibilityTimer?.invalidate(); self.accessibilityTimer = nil
                    self.playSound("Purr")
                }
            }
        }
    }

    @objc func menuRetryHotkey() {
        hdLog("Manual retry of hotkey monitoring")
        attemptStartMonitoring()
    }

    // MARK: - macOS Services (Refine)

    @objc func refineText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pboard.string(forType: .string)
            ?? pboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        guard let text, !text.isEmpty else {
            error.pointee = "No text selected" as NSString
            return
        }
        guard let apiKey = appState.keychainStore.retrieveAPIKey() else {
            error.pointee = "No API key configured." as NSString
            return
        }

        let action: RefineAction
        switch userData {
        case "elaborate":  action = .elaborate
        case "polish":     action = .polish
        case "shorten":    action = .shorten
        case "formalize":  action = .formalize
        default:           action = .polish
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let modelName = appState.rewriteModelAPIName
        Task { @MainActor in
            refinePreviewController?.showPreview(
                originalText: text, action: action, modelName: modelName,
                apiKey: apiKey, sourceApp: sourceApp
            )
        }
    }

    // MARK: - Menu Actions

    @objc func menuOpenHistory() { showHistoryWindow() }
    @objc func menuOpenCalibration() { showCalibrationWindow() }
    @objc func menuOpenSettings() { showSettingsWindow() }

    @objc func menuCancelDictation() {
        hdLog("Cancel dictation from menu")
        listeningTimer?.invalidate()
        listeningTimer = nil
        appState.hotkeyManager.resetHoldState()
        _ = appState.audioCaptureEngine.stopCapture()
        appState.isLockMode = false
        appState.mode = .idle
        appState.roughTranscript = ""
        appState.errorMessage = nil
        playSound("Funk")
    }

    // MARK: - Window Management

    func showHistoryWindow() {
        if historyWindow == nil || !historyWindow!.isVisible {
            let view = HistoryView().environmentObject(appState)
            historyWindow = makeWindow(title: "HDText History", view: view, width: 700, height: 500, minWidth: 500, minHeight: 350)
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboardingWindow() {
        if onboardingWindow == nil || !onboardingWindow!.isVisible {
            let view = OnboardingView().environmentObject(appState)
            onboardingWindow = makeWindow(title: "Welcome to HDText", view: view, width: 520, height: 480, resizable: false)
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showCalibrationWindow() {
        if calibrationWindow == nil || !calibrationWindow!.isVisible {
            let view = CalibrationView().environmentObject(appState)
            calibrationWindow = makeWindow(title: "Calibrate Microphone", view: view, width: 460, height: 400, resizable: false)
        }
        calibrationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsWindow() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView().environmentObject(appState)
        settingsWindow = makeWindow(title: "HDText Settings", view: view, width: 700, height: 520, resizable: false)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func onOnboardingComplete() {
        ensureAccessibilityThenStart()
    }

    private func makeWindow<V: View>(
        title: String, view: V, width: CGFloat, height: CGFloat,
        minWidth: CGFloat? = nil, minHeight: CGFloat? = nil, resizable: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: style, backing: .buffered, defer: false)
        w.title = title
        w.contentView = NSHostingView(rootView: view)
        w.center()
        w.isReleasedWhenClosed = false
        if let mw = minWidth, let mh = minHeight { w.minSize = NSSize(width: mw, height: mh) }
        return w
    }

    // MARK: - Dictation Pipeline

    private func setupDictationPipeline() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleDictationStart),
                                               name: .hdtextDictationStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDictationEnd),
                                               name: .hdtextDictationEnd, object: nil)

        appState.hotkeyManager.onHoldStarted = {
            NotificationCenter.default.post(name: .hdtextDictationStart, object: nil)
        }
        appState.hotkeyManager.onHoldEnded = {
            NotificationCenter.default.post(name: .hdtextDictationEnd, object: nil)
        }
    }

    // MARK: - Double-Tap + Hold-to-Talk Logic

    @objc private func handleDictationStart(_ notification: Notification) {
        hdLog("handleDictationStart")
        dictationStartTime = Date()

        if appState.isLockMode {
            // In lock mode — this tap might be to exit
            return
        }

        // Check if this is the second tap of a double-tap
        if let lastEnd = lastTapEndTime, Date().timeIntervalSince(lastEnd) < 0.5 {
            lastTapEndTime = nil
            doubleTapTimer?.invalidate()
            doubleTapTimer = nil
            appState.isLockMode = true
            appState.errorLog.log("Lock mode activated — double-tap to stop", level: .info)
            hdLog("🔒 LOCK MODE ON")
            playSound("Tink")

            if appState.mode != .listening {
                beginCapture()
            }
            return
        }

        beginCapture()
    }

    @objc private func handleDictationEnd(_ notification: Notification) {
        hdLog("handleDictationEnd")
        let holdDuration = dictationStartTime.map { Date().timeIntervalSince($0) } ?? 1.0

        // --- Lock mode: check for double-tap exit ---
        if appState.isLockMode {
            if holdDuration < 0.35 {
                if let lastExit = lockExitTapTime, Date().timeIntervalSince(lastExit) < 0.5 {
                    // Second quick tap in lock mode → EXIT
                    appState.isLockMode = false
                    lockExitTapTime = nil
                    appState.errorLog.log("Lock mode deactivated", level: .info)
                    hdLog("🔓 LOCK MODE OFF — finalizing")
                    playSound("Pop")
                    finalizeDictation()
                } else {
                    lockExitTapTime = Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.lockExitTapTime = nil
                    }
                }
            }
            return
        }

        // --- Normal mode ---
        if holdDuration < 0.35 {
            // Quick tap — potential first of double-tap
            cancelCapture()
            lastTapEndTime = Date()
            doubleTapTimer?.invalidate()
            doubleTapTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.lastTapEndTime = nil }
            }
            return
        }

        // Normal hold release — finalize immediately
        lastTapEndTime = nil
        doubleTapTimer?.invalidate()
        finalizeDictation()
    }

    // MARK: - Capture Start / Cancel

    private var sourceApp: NSRunningApplication?
    private var refineActionMenu: NSMenu?

    private func beginCapture() {
        guard appState.mode == .idle || appState.isLockMode else { return }

        guard appState.hasAPIKey else {
            appState.errorLog.log("No API key configured")
            showTemporaryError("No API key configured. Open Settings > API Key.")
            return
        }

        sourceApp = NSWorkspace.shared.frontmostApplication

        if !appState.isLockMode, let selectedText = getSelectedTextFromFrontmostApp(), !selectedText.isEmpty {
            hdLog("Text selected — showing refine picker (\(selectedText.count) chars)")
            showRefineActionPicker(for: selectedText)
            return
        }

        hdLog("beginCapture — source app: \(sourceApp?.localizedName ?? "none")")
        if !appState.isLockMode { playSound("Tink") }

        appState.mode = .listening
        appState.roughTranscript = ""
        appState.cleanedText = ""
        appState.errorMessage = nil
        listeningTimer?.invalidate()
        listeningTimer = nil

        do {
            try appState.audioCaptureEngine.startCapture(deviceID: appState.selectedMicrophoneID)
            hdLog("Audio capture started OK")
        } catch {
            appState.errorLog.log("Audio capture failed", detail: error.localizedDescription)
            showTemporaryError("Microphone: \(error.localizedDescription)")
        }
    }

    private func cancelCapture() {
        _ = appState.audioCaptureEngine.stopCapture()
        appState.mode = .idle
        appState.roughTranscript = ""
        appState.errorMessage = nil
    }

    // MARK: - Refine via Hotkey

    private func getSelectedTextFromFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else { return nil }
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success else { return nil }
        return selectedText as? String
    }

    private func showRefineActionPicker(for text: String) {
        appState.hotkeyManager.resetHoldState()
        let menu = NSMenu(title: "Refine Text")
        for action in RefineAction.allCases {
            let item = NSMenuItem(title: action.displayName, action: #selector(handleRefineMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = RefineMenuContext(text: text, action: action)
            switch action {
            case .elaborate:  item.image = NSImage(systemSymbolName: "text.append", accessibilityDescription: nil)
            case .polish:     item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            case .shorten:    item.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
            case .formalize:  item.image = NSImage(systemSymbolName: "briefcase", accessibilityDescription: nil)
            }
            menu.addItem(item)
        }
        self.refineActionMenu = menu
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func handleRefineMenuAction(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? RefineMenuContext else { return }
        guard let apiKey = appState.keychainStore.retrieveAPIKey() else {
            showTemporaryError("No API key configured."); return
        }
        hdLog("Refine via hotkey: \(ctx.action.displayName) on \(ctx.text.count) chars")
        refinePreviewController?.showPreview(
            originalText: ctx.text, action: ctx.action, modelName: appState.rewriteModelAPIName,
            apiKey: apiKey, sourceApp: sourceApp
        )
    }

    // MARK: - Finalize Dictation

    private func finalizeDictation() {
        hdLog("finalizeDictation called — mode=\(appState.mode)")
        listeningTimer?.invalidate()
        listeningTimer = nil

        let audioData = appState.audioCaptureEngine.stopCapture()
        hdLog("Audio captured: \(audioData.count) bytes")

        guard appState.mode == .listening else {
            hdLog("finalizeDictation: mode is \(appState.mode) not .listening — resetting")
            appState.errorLog.log("finalizeDictation skipped", detail: "mode was \(appState.mode.rawValue), expected listening", level: .warning)
            appState.mode = .idle
            return
        }

        playSound("Pop")

        let minBytes = 16000 * 2 / 4
        guard audioData.count > minBytes else {
            appState.errorLog.log("Recording too short", detail: "\(audioData.count) bytes", level: .warning)
            showTemporaryError("Recording too short. Hold the key longer while speaking.")
            return
        }

        if AudioCaptureEngine.isSilence(audioData, threshold: 0.004) {
            appState.errorLog.log("Silence detected", detail: "RMS below threshold — skipped API call", level: .info)
            showTemporaryError("No speech detected. Try speaking louder.")
            return
        }

        appState.mode = .processing
        appState.roughTranscript = "Processing..."

        guard let apiKey = appState.keychainStore.retrieveAPIKey() else {
            appState.errorLog.log("API key missing at finalize")
            showTemporaryError("API key missing")
            return
        }

        hdLog("Starting transcribe+clean with \(audioData.count) bytes...")

        Task {
            do {
                let cleaned = try await appState.geminiTranscriptionService.transcribeAndClean(
                    audioData: audioData,
                    aggressiveness: appState.rewriteAggressiveness,
                    smartCorrection: appState.smartCorrectionEnabled,
                    modelName: appState.transcriptionModelAPIName,
                    apiKey: apiKey
                )
                hdLog("Result: \(cleaned)")

                await MainActor.run {
                    appState.cleanedText = cleaned
                    appState.roughTranscript = cleaned

                    let record = TranscriptionRecord(
                        roughTranscript: cleaned, cleanedText: cleaned,
                        targetApp: self.sourceApp?.localizedName ?? "Unknown"
                    )
                    appState.historyStore.save(record)
                    appState.mode = .idle

                    if let app = self.sourceApp {
                        app.activate()
                        hdLog("Reactivated: \(app.localizedName ?? "?")")
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        guard let self = self else { return }
                        let pasteboard = NSPasteboard.general
                        let previousClip = pasteboard.string(forType: .string)
                        pasteboard.clearContents()
                        pasteboard.setString(cleaned, forType: .string)

                        let src = CGEventSource(stateID: .combinedSessionState)
                        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
                           let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
                            down.flags = .maskCommand
                            up.flags = .maskCommand
                            down.post(tap: .cghidEventTap)
                            up.post(tap: .cghidEventTap)
                            hdLog("Pasted via Cmd+V")
                        }
                        self.playSound("Glass")

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let prev = previousClip {
                                pasteboard.clearContents()
                                pasteboard.setString(prev, forType: .string)
                            }
                        }
                    }
                }
            } catch let error as TranscriptionError where error == .noSpeechDetected {
                await MainActor.run {
                    appState.errorLog.log("No speech detected by model", level: .warning)
                    showTemporaryError("No speech detected. Try speaking louder.")
                }
            } catch {
                await MainActor.run {
                    appState.errorLog.log("Transcription failed", detail: error.localizedDescription)
                    appState.mode = .error
                    appState.errorMessage = error.localizedDescription
                    playSound("Basso")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                        if self?.appState.mode == .error {
                            self?.appState.mode = .idle
                            self?.appState.errorMessage = nil
                        }
                    }
                }
            }
        }
    }

    private func showTemporaryError(_ message: String) {
        appState.errorMessage = message
        appState.mode = .error
        playSound("Basso")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.appState.mode == .error {
                self?.appState.mode = .idle
                self?.appState.errorMessage = nil
            }
        }
    }

    // MARK: - Audio Feedback

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let hdtextDictationStart = Notification.Name("hdtextDictationStart")
    static let hdtextDictationEnd = Notification.Name("hdtextDictationEnd")
}

final class RefineMenuContext: NSObject {
    let text: String
    let action: RefineAction
    init(text: String, action: RefineAction) {
        self.text = text
        self.action = action
    }
}
