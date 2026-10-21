import AppKit
import ApplicationServices

/// All items/types on a pasteboard, so a paste can put the user's clipboard back exactly.
struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict.isEmpty ? nil : dict
        }
        return PasteboardSnapshot(items: items)
    }

    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let objects: [NSPasteboardItem] = items.map { typeMap in
            let item = NSPasteboardItem()
            for (type, data) in typeMap { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(objects)
    }
}

final class TextInsertionService {
    private let pasteboard: NSPasteboard
    private let activationDelay: TimeInterval = 0.25
    private let restoreDelay: TimeInterval = 0.8

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Puts `text` on the clipboard, activates `app`, sends ⌘V, then restores the previous
    /// clipboard if nothing else has changed it in the meantime.
    func paste(_ text: String, into app: NSRunningApplication?, completion: (() -> Void)? = nil) {
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        if let app {
            app.activate()
            hdLog("Reactivated: \(app.localizedName ?? "?")")
        }

        let pasteboard = self.pasteboard
        let restoreDelay = self.restoreDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            Self.postCommandKey(0x09)
            hdLog("Pasted via Cmd+V")
            completion?()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                Self.restore(snapshot, to: pasteboard, ifChangeCountIs: ourChangeCount)
            }
        }
    }

    @discardableResult
    static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard, ifChangeCountIs expected: Int) -> Bool {
        guard pasteboard.changeCount == expected else {
            hdLog("Clipboard changed since paste — not restoring")
            return false
        }
        snapshot.write(to: pasteboard)
        return true
    }

    static func postCommandKey(_ virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
