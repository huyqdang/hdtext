import AppKit

/// What the floating record button shows; derived from app state so it can be tested without UI.
enum FloatingButtonState: Equatable {
    case idle, recording, busy, processing, copied, error(String)

    static let copiedDisplay: TimeInterval = 1.5

    var helpText: String {
        switch self {
        case .idle: return "Click to record · drag to move · right-click for options"
        case .recording: return "Recording — click to stop and copy"
        case .busy: return "Recording with the hotkey"
        case .processing: return "Transcribing…"
        case .copied: return "Copied to clipboard"
        case .error(let message): return message
        }
    }

    static func from(mode: AppMode, origin: RecordingOrigin?, lastCopiedAt: Date?, errorMessage: String?, now: Date = Date()) -> FloatingButtonState {
        switch mode {
        case .listening:
            return origin == .button ? .recording : .busy
        case .processing:
            return .processing
        case .error:
            return .error(errorMessage ?? "Something went wrong")
        case .idle:
            if let lastCopiedAt, now.timeIntervalSince(lastCopiedAt) < copiedDisplay {
                return .copied
            }
            return .idle
        }
    }
}

enum FloatingButtonPlacement {
    static let dragThreshold: CGFloat = 4
    static let inset: CGFloat = 24

    static func isDrag(from start: NSPoint, to end: NSPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > dragThreshold
    }

    static func defaultOrigin(size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.maxX - size.width - inset, y: visibleFrame.minY + inset)
    }

    /// Keeps the whole button inside the screen that holds its centre, else the nearest screen.
    static func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrames: [NSRect]) -> NSPoint {
        guard !visibleFrames.isEmpty else { return origin }
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let frame = visibleFrames.first { $0.contains(center) } ?? visibleFrames.min {
            distance(from: center, to: $0) < distance(from: center, to: $1)
        }!
        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
