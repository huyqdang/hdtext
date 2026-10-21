import Foundation
import os.log

private let logger = Logger(subsystem: "com.hdtext.app", category: "general")

func hdLog(_ message: String) {
    logger.info("\(message, privacy: .public)")
}

/// Like hdLog, but persisted in the system log (info lines are memory-only and age out).
func hdLogWarning(_ message: String) {
    logger.error("\(message, privacy: .public)")
}
