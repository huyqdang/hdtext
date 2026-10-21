import AppKit

enum AccessibilityPermission {
    /// A rebuilt (ad-hoc signed) app keeps its row in System Settings but loses the grant.
    /// Clearing the stale entry lets macOS prompt again.
    @MainActor static func resetAndRegrant() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hdtext.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            hdLog("tccutil reset Accessibility \(bundleID) → \(process.terminationStatus)")
        } catch {
            hdLog("tccutil failed: \(error.localizedDescription)")
        }
        (NSApp.delegate as? AppDelegate)?.menuRetryHotkey()
    }
}
