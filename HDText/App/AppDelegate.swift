import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var overlayController: OverlayPanelController?
    private var floatingButtonController: FloatingRecordButtonController?
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
    private var lockActivationReleasePending = false
    private var selectionLookupToken: UUID?

    private var transcriptionTask: Task<Void, Never>?
    private var dictationSession = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(appState: appState)
        overlayController = OverlayPanelController(appState: appState)
        floatingButtonController = FloatingRecordButtonController(
            appState: appState,
            onClick: { [weak self] in self?.toggleButtonRecording() },
            onOpenSettings: { [weak self] in self?.showSettingsWindow() }
        )
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
        guard let apiKey = appState.apiKey else {
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
        transcriptionTask?.cancel()
        transcriptionTask = nil
        dictationSession = UUID()
        selectionLookupToken = nil
        appState.isLockMode = false
        lockActivationReleasePending = false
        lockExitTapTime = nil
        lastTapEndTime = nil
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
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
            let view = OnboardingView(onFinish: { [weak self] in self?.completeOnboarding() }).environmentObject(appState)
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

    func completeOnboarding() {
        appState.isOnboardingComplete = true
        onboardingWindow?.close()
        DispatchQueue.main.async { [weak self] in self?.onboardingWindow = nil }
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
        appState.audioCaptureEngine.onCaptureError = { [weak self] error in
            guard let self, self.appState.mode == .listening else { return }
            _ = self.appState.audioCaptureEngine.stopCapture()
            self.appState.isLockMode = false
            self.lockActivationReleasePending = false
            self.appState.errorLog.log("Audio capture failed", detail: error.localizedDescription)
            self.showTemporaryError("Microphone: \(error.localizedDescription)")
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleDictationStart),
                                               name: .hdtextDictationStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDictationEnd),
                                               name: .hdtextDictationEnd, object: nil)

        appState.hotkeyManager.onHoldStarted = {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hdtextDictationStart, object: nil)
            }
        }
        appState.hotkeyManager.onHoldEnded = {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hdtextDictationEnd, object: nil)
            }
        }
    }

    // MARK: - Double-Tap + Hold-to-Talk Logic

    @objc private func handleDictationStart(_ notification: Notification) {
        if appState.recordingOrigin == .button { return }  // the hotkey never touches a button recording
        hdLog("handleDictationStart")
        dictationStartTime = Date()
        selectionLookupToken = nil

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
            lockActivationReleasePending = true
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
        if appState.recordingOrigin == .button { return }  // the hotkey never touches a button recording
        hdLog("handleDictationEnd")
        let holdDuration = dictationStartTime.map { Date().timeIntervalSince($0) } ?? 1.0

        // --- Lock mode: check for double-tap exit ---
        if appState.isLockMode {
            if lockActivationReleasePending {
                lockActivationReleasePending = false
                return
            }
            if holdDuration < 0.5 {
                if let lastExit = lockExitTapTime, Date().timeIntervalSince(lastExit) < 0.5 {
                    // Second quick tap in lock mode → EXIT
                    appState.isLockMode = false
                    lockActivationReleasePending = false
                    lockExitTapTime = nil
                    appState.errorLog.log("Lock mode deactivated", level: .info)
                    hdLog("🔓 LOCK MODE OFF — finalizing")
                    finalizeDictation()
                } else {
                    let stamp = Date()
                    lockExitTapTime = stamp
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        if self?.lockExitTapTime == stamp { self?.lockExitTapTime = nil }
                    }
                }
            }
            return
        }

        // --- Normal mode: quick tap ---
        if holdDuration < 0.5 {
            guard appState.mode == .listening else {
                return
            }
            cancelCapture()
            armDoubleTapTimer()
            hdLog("Quick tap detected (\(Int(holdDuration * 1000))ms) — looking for selected text")

            if let axText = getSelectedTextViaAX() {
                if axText.isEmpty {
                    hdLog("AX reports no selection")
                } else {
                    hdLog("AX selected text found (\(axText.count) chars) — showing refine")
                    showRefineActionPicker(for: axText)
                }
                return
            }

            let token = UUID()
            selectionLookupToken = token
            attemptSelectedTextViaClipboard { [weak self] text in
                guard let self = self,
                      self.selectionLookupToken == token,
                      self.appState.mode == .idle,
                      !self.appState.isLockMode else { return }
                self.selectionLookupToken = nil
                if let text, !text.isEmpty {
                    hdLog("Clipboard selected text found (\(text.count) chars) — showing refine")
                    self.showRefineActionPicker(for: text)
                } else {
                    hdLog("No selected text from AX or clipboard")
                }
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

    private func beginCapture(origin: RecordingOrigin = .hotkey) {
        if appState.mode == .processing {
            hdLog("beginCapture: transcription still running — ignoring")
            appState.isLockMode = false
            lockActivationReleasePending = false
            return
        }
        guard appState.mode == .idle || appState.isLockMode else { return }

        guard appState.hasAPIKey else {
            appState.isLockMode = false
            lockActivationReleasePending = false
            appState.errorLog.log("No API key configured")
            showTemporaryError("No API key configured. Open Settings > API Key.")
            return
        }

        sourceApp = NSWorkspace.shared.frontmostApplication

        hdLog("beginCapture — source app: \(sourceApp?.localizedName ?? "none")")
        if !appState.isLockMode { playSound("Tink") }

        appState.mode = .listening
        appState.recordingOrigin = origin
        appState.roughTranscript = ""
        appState.cleanedText = ""
        appState.errorMessage = nil
        listeningTimer?.invalidate()
        listeningTimer = nil

        do {
            try appState.audioCaptureEngine.startCapture(deviceID: appState.selectedMicrophoneID)
            hdLog("Audio capture started OK")
        } catch {
            appState.isLockMode = false
            lockActivationReleasePending = false
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

    private func armDoubleTapTimer() {
        lastTapEndTime = Date()
        doubleTapTimer?.invalidate()
        doubleTapTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.lastTapEndTime = nil }
        }
    }

    /// nil = AX could not answer (use the clipboard fallback); "" = AX answered, nothing selected.
    private func getSelectedTextViaAX() -> String? {
        guard AXIsProcessTrusted() else {
            hdLog("getSelectedTextViaAX: Accessibility not trusted")
            return nil
        }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusResult == .success, let focusedElement = focused else {
            hdLog("getSelectedTextViaAX: system-wide focus failed (\(focusResult.rawValue))")
            return nil
        }
        var selected: AnyObject?
        let selectResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected)
        guard selectResult == .success else {
            hdLog("getSelectedTextViaAX: selected-text failed (\(selectResult.rawValue))")
            return nil
        }
        return selected as? String
    }

    private func attemptSelectedTextViaClipboard(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let snapshot = TextInsertionService.captureOriginal(pasteboard)
        let originalChangeCount = pasteboard.changeCount

        let deadline = Date().addingTimeInterval(0.4)

        TextInsertionService.postCommandKey(0x08)

        func poll() {
            let copiedChangeCount = pasteboard.changeCount
            if copiedChangeCount != originalChangeCount {
                let copied = pasteboard.string(forType: .string)
                TextInsertionService.restore(snapshot, to: pasteboard, ifChangeCountIs: copiedChangeCount)
                completion(copied)
                return
            }
            guard Date() < deadline else {
                hdLog("Clipboard fallback: changeCount unchanged — no selection copied")
                completion(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { poll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { poll() }
    }

    private func showRefineActionPicker(for text: String) {
        appState.hotkeyManager.resetHoldState()
        lastTapEndTime = nil
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
        dictationStartTime = nil
        appState.mode = .idle

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
        guard let apiKey = appState.apiKey else {
            showTemporaryError("No API key configured."); return
        }
        hdLog("Refine via hotkey: \(ctx.action.displayName) on \(ctx.text.count) chars")
        refinePreviewController?.showPreview(
            originalText: ctx.text, action: ctx.action, modelName: appState.rewriteModelAPIName,
            apiKey: apiKey, sourceApp: sourceApp
        )
    }

    // MARK: - Floating Button

    func toggleButtonRecording() {
        switch appState.mode {
        case .idle, .error:
            appState.errorMessage = nil
            appState.mode = .idle
            beginCapture(origin: .button)
        case .listening:
            guard appState.recordingOrigin == .button else { return }
            finalizeDictation()
        case .processing:
            return
        }
    }

    // MARK: - Finalize Dictation

    private func finalizeDictation() {
        let origin = appState.recordingOrigin ?? .hotkey
        hdLog("finalizeDictation called — mode=\(appState.mode)")
        listeningTimer?.invalidate()
        listeningTimer = nil

        let audioData = appState.audioCaptureEngine.stopCapture()
        hdLog("Audio captured: \(audioData.count) bytes")

        if appState.mode == .processing {
            hdLog("finalizeDictation: transcription still running — ignoring release")
            return
        }
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

        guard let apiKey = appState.apiKey else {
            appState.errorLog.log("API key missing at finalize")
            showTemporaryError("API key missing")
            return
        }

        hdLog("Starting transcribe+clean with \(audioData.count) bytes...")

        let session = UUID()
        dictationSession = session
        let targetApp = sourceApp

        transcriptionTask = Task {
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
                    guard session == self.dictationSession, !Task.isCancelled else { return }
                    self.transcriptionTask = nil
                    appState.cleanedText = cleaned
                    appState.roughTranscript = cleaned

                    let record = TranscriptionRecord(
                        roughTranscript: cleaned, cleanedText: cleaned,
                        targetApp: origin == .button ? "Clipboard" : (targetApp?.localizedName ?? "Unknown")
                    )
                    appState.historyStore.save(record)
                    appState.mode = .idle

                    switch origin {
                    case .hotkey:
                        appState.textInsertionService.paste(cleaned, into: targetApp) { [weak self] in
                            self?.playSound("Glass")
                        }
                    case .button:
                        appState.textInsertionService.copyToClipboard(cleaned)
                        appState.lastCopiedAt = Date()
                        playSound("Glass")
                        hdLog("Copied transcript to clipboard (\(cleaned.count) chars)")
                    }
                }
            } catch let error as TranscriptionError where error == .noSpeechDetected {
                await MainActor.run {
                    guard session == self.dictationSession, !Task.isCancelled else { return }
                    self.transcriptionTask = nil
                    appState.errorLog.log("No speech detected by model", level: .warning)
                    showTemporaryError("No speech detected. Try speaking louder.")
                }
            } catch {
                await MainActor.run {
                    guard session == self.dictationSession, !Task.isCancelled else { return }
                    self.transcriptionTask = nil
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
