import AppKit
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        observeState()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        populate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func rebuildMenu() {
        if let menu = statusItem?.menu { populate(menu) }
    }

    private func observeState() {
        appState.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.updateIcon(for: mode)
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for mode: AppMode) {
        let symbolName: String
        switch mode {
        case .idle:       symbolName = "waveform"
        case .listening:  symbolName = "mic.fill"
        case .processing: symbolName = "ellipsis.circle"
        case .error:      symbolName = "exclamationmark.triangle"
        }

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "HDText")?
                .withSymbolConfiguration(config)
        }
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusTitle: String
        switch appState.mode {
        case .idle:       statusTitle = "Ready  (\(appState.hotkeyManager.shortcutDescription) to talk)"
        case .listening:  statusTitle = "Listening..."
        case .processing: statusTitle = "Processing..."
        case .error:      statusTitle = "Error"
        }

        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        if appState.mode == .listening {
            statusMenuItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        }
        menu.addItem(statusMenuItem)

        if let errorMsg = appState.errorMessage {
            let errorItem = NSMenuItem(title: errorMsg, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(NSMenuItem.separator())

        let axOK = AXIsProcessTrusted()
        let axStatus = axOK ? "Accessibility: Granted" : "Accessibility: NOT GRANTED — click to reset & re-grant"
        let axItem = NSMenuItem(title: axStatus, action: axOK ? nil : #selector(resetAccessibility), keyEquivalent: "")
        axItem.target = axOK ? nil : self
        axItem.isEnabled = !axOK
        axItem.image = NSImage(
            systemSymbolName: axOK ? "checkmark.circle.fill" : "xmark.circle",
            accessibilityDescription: nil
        )
        menu.addItem(axItem)

        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let micStatus = micOK ? "Microphone: Granted" : "Microphone: NOT GRANTED"
        let micItem = NSMenuItem(title: micStatus, action: micOK ? nil : #selector(openMicrophoneSettings), keyEquivalent: "")
        micItem.target = micOK ? nil : self
        micItem.isEnabled = !micOK
        micItem.image = NSImage(
            systemSymbolName: micOK ? "checkmark.circle.fill" : "xmark.circle",
            accessibilityDescription: nil
        )
        menu.addItem(micItem)

        let keyStatus = appState.hasAPIKey ? "API Key: Configured" : "API Key: NOT SET"
        let keyItem = NSMenuItem(title: keyStatus, action: nil, keyEquivalent: "")
        keyItem.isEnabled = false
        keyItem.image = NSImage(
            systemSymbolName: appState.hasAPIKey ? "checkmark.circle.fill" : "xmark.circle",
            accessibilityDescription: nil
        )
        menu.addItem(keyItem)

        let hotkeyOK = appState.hotkeyManager.isMonitoring
        let hotkeyStatus = hotkeyOK ? "Hotkey: Active (\(appState.hotkeyManager.shortcutDescription))" : "Hotkey: NOT ACTIVE"
        let hotkeyItem = NSMenuItem(title: hotkeyStatus, action: hotkeyOK ? nil : #selector(AppDelegate.menuRetryHotkey), keyEquivalent: "")
        hotkeyItem.target = hotkeyOK ? nil : (NSApp.delegate as? AppDelegate)
        hotkeyItem.isEnabled = !hotkeyOK
        hotkeyItem.image = NSImage(
            systemSymbolName: hotkeyOK ? "checkmark.circle.fill" : "xmark.circle",
            accessibilityDescription: nil
        )
        menu.addItem(hotkeyItem)

        if appState.isLockMode {
            let lockItem = NSMenuItem(title: "🔒 Lock Mode Active (double-tap to stop)", action: nil, keyEquivalent: "")
            lockItem.isEnabled = false
            menu.addItem(lockItem)
        }

        if appState.mode == .listening || appState.mode == .processing {
            let cancelItem = NSMenuItem(
                title: "Cancel Dictation",
                action: #selector(AppDelegate.menuCancelDictation),
                keyEquivalent: ""
            )
            cancelItem.target = NSApp.delegate as? AppDelegate
            cancelItem.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
            menu.addItem(cancelItem)
        }

        menu.addItem(NSMenuItem.separator())

        let delegate = NSApp.delegate as? AppDelegate

        let historyItem = NSMenuItem(title: "Transcription History", action: #selector(AppDelegate.menuOpenHistory), keyEquivalent: "h")
        historyItem.target = delegate
        menu.addItem(historyItem)

        let calibrationItem = NSMenuItem(title: "Calibrate Microphone", action: #selector(AppDelegate.menuOpenCalibration), keyEquivalent: "")
        calibrationItem.target = delegate
        menu.addItem(calibrationItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(AppDelegate.menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = delegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit HDText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func resetAccessibility() {
        AccessibilityPermission.resetAndRegrant()
    }

    @objc private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
