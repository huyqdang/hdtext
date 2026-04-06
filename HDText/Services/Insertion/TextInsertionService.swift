import AppKit
import ApplicationServices

final class TextInsertionService {
    func insertText(_ text: String) -> Bool {
        guard let focusedElement = getFocusedElement() else { return false }

        if setAXValue(focusedElement, text: text) {
            return true
        }

        return pasteViaClipboard(text)
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

    private func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        guard appResult == .success else { return nil }

        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard elementResult == .success else { return nil }

        return (focusedElement as! AXUIElement)
    }

    private func setAXValue(_ element: AXUIElement, text: String) -> Bool {
        var selectedRange: AnyObject?
        _ = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        let textValue = text as CFTypeRef
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            textValue
        )

        if setResult == .success {
            return true
        }

        let valueResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            textValue
        )

        return valueResult == .success
    }

    private func pasteViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }

        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand

        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        return true
    }
}
