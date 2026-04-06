import Foundation
import os.log

private let logger = Logger(subsystem: "com.hdtext.app", category: "general")

func hdLog(_ message: String) {
    logger.info("\(message, privacy: .public)")
}
