import AppKit
import Carbon

final class HotkeyManager {
    var onHoldStarted: (() -> Void)?
    var onHoldEnded: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var releasePoller: Timer?
    private(set) var isHolding = false
    private(set) var isMonitoring = false

    private var modifierFlags: CGEventFlags = [.maskControl, .maskAlternate]
    private var triggerKeyCode: CGKeyCode = 49  // spacebar

    var shortcutDescription: String {
        var parts: [String] = []
        if modifierFlags.contains(.maskControl) { parts.append("⌃") }
        if modifierFlags.contains(.maskAlternate) { parts.append("⌥") }
        if modifierFlags.contains(.maskCommand) { parts.append("⌘") }
        if modifierFlags.contains(.maskShift) { parts.append("⇧") }
        parts.append(keyCodeName(triggerKeyCode))
        return parts.joined()
    }

    init() {
        loadSavedShortcut()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()
        createEventTap()
    }

    func stopMonitoring() {
        releasePoller?.invalidate()
        releasePoller = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        isHolding = false
        isMonitoring = false
    }

    func updateShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        self.modifierFlags = nsToCGFlags(modifiers)
        self.triggerKeyCode = CGKeyCode(keyCode)
        UserDefaults.standard.set(modifiers.rawValue, forKey: "hotkeyModifiers")
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
    }

    func forceRelease() {
        guard isHolding else { return }
        NSLog("[HD Text] Force-released")
        isHolding = false
        releasePoller?.invalidate()
        releasePoller = nil
        onHoldEnded?()
    }

    func resetHoldState() {
        isHolding = false
        releasePoller?.invalidate()
        releasePoller = nil
    }

    func pauseTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func resumeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    // MARK: - CGEvent Tap (active tap — can suppress events)

    private func createEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            hdLog("CGEvent tap FAILED — Accessibility not granted")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isMonitoring = true

        hdLog("Hotkey monitoring active: \(shortcutDescription)")
    }

    /// Returns true if the event is our hotkey and should be suppressed.
    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .keyUp && isHolding {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == triggerKeyCode { return true }
        }

        guard type == .keyDown else { return false }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == triggerKeyCode else { return false }

        let relevantFlags = event.flags.intersection(
            [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        )
        guard relevantFlags == modifierFlags else { return false }

        if !isHolding {
            hdLog("▶ HOLD STARTED")
            isHolding = true
            startReleasePoller()
            onHoldStarted?()
        }
        return true
    }

    // MARK: - Release Detection via Polling

    private func startReleasePoller() {
        releasePoller?.invalidate()
        pollCount = 0

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self = self, self.isHolding else {
                t.invalidate()
                return
            }

            self.pollCount += 1

            let nsFlags = NSEvent.modifierFlags
            let held = self.nsModifiersContainRequired(nsFlags)

            if self.pollCount <= 3 {
                hdLog("Poll #\(self.pollCount): NSEvent.modifierFlags=\(nsFlags.rawValue) held=\(held)")
            }

            if !held {
                hdLog("■ RELEASED after \(self.pollCount) polls")
                self.isHolding = false
                t.invalidate()
                self.releasePoller = nil
                self.onHoldEnded?()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.releasePoller = timer
    }

    private var pollCount = 0

    private func nsModifiersContainRequired(_ nsFlags: NSEvent.ModifierFlags) -> Bool {
        if modifierFlags.contains(.maskControl) && !nsFlags.contains(.control) { return false }
        if modifierFlags.contains(.maskAlternate) && !nsFlags.contains(.option) { return false }
        if modifierFlags.contains(.maskCommand) && !nsFlags.contains(.command) { return false }
        if modifierFlags.contains(.maskShift) && !nsFlags.contains(.shift) { return false }
        return true
    }

    fileprivate func handleTapDisabled() {
        NSLog("[HD Text] Event tap disabled by system — re-enabling")
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    // MARK: - Persistence

    private func loadSavedShortcut() {
        guard UserDefaults.standard.object(forKey: "hotkeyModifiers") != nil,
              UserDefaults.standard.object(forKey: "hotkeyKeyCode") != nil else {
            return
        }
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")

        guard savedModifiers != 0 else { return }
        modifierFlags = nsToCGFlags(NSEvent.ModifierFlags(rawValue: UInt(savedModifiers)))
        triggerKeyCode = CGKeyCode(savedKeyCode)
    }

    private func nsToCGFlags(_ ns: NSEvent.ModifierFlags) -> CGEventFlags {
        var cg: CGEventFlags = []
        if ns.contains(.control)  { cg.insert(.maskControl) }
        if ns.contains(.option)   { cg.insert(.maskAlternate) }
        if ns.contains(.command)  { cg.insert(.maskCommand) }
        if ns.contains(.shift)    { cg.insert(.maskShift) }
        return cg
    }

    private func keyCodeName(_ code: CGKeyCode) -> String {
        let names: [CGKeyCode: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
            6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
            41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            53: "Escape",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 109: "F10",
            111: "F12", 118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[code] ?? "Key\(code)"
    }
}

// MARK: - C Callback

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        manager.handleTapDisabled()
        return Unmanaged.passUnretained(event)
    }

    let shouldSuppress = manager.handleTapEvent(type: type, event: event)
    if shouldSuppress {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
