import XCTest
@testable import HDText

final class FloatingButtonLogicTests: XCTestCase {
    private let size = NSSize(width: 60, height: 60)
    private let main = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = NSRect(x: 1440, y: 0, width: 1920, height: 1055)

    func testOffScreenOriginIsClampedIntoNearestScreen() {
        let clamped = FloatingButtonPlacement.clampedOrigin(NSPoint(x: 5000, y: -300), size: size, visibleFrames: [main, right])
        XCTAssertEqual(clamped, NSPoint(x: right.maxX - 60, y: right.minY))
    }

    func testOriginOnSecondScreenIsKept() {
        let origin = NSPoint(x: 2000, y: 400)
        XCTAssertEqual(FloatingButtonPlacement.clampedOrigin(origin, size: size, visibleFrames: [main, right]), origin)
    }

    func testDefaultOriginIsBottomRightWithInset() {
        XCTAssertEqual(FloatingButtonPlacement.defaultOrigin(size: size, visibleFrame: main), NSPoint(x: 1440 - 60 - 24, y: 24))
    }

    func testSmallMoveIsClickLargerMoveIsDrag() {
        XCTAssertFalse(FloatingButtonPlacement.isDrag(from: .zero, to: NSPoint(x: 3, y: 0)))
        XCTAssertTrue(FloatingButtonPlacement.isDrag(from: .zero, to: NSPoint(x: 5, y: 0)))
    }

    func testStateFollowsModeOriginAndCopyTime() {
        let now = Date()
        XCTAssertEqual(FloatingButtonState.from(mode: .idle, origin: nil, lastCopiedAt: nil, errorMessage: nil, now: now), .idle)
        XCTAssertEqual(FloatingButtonState.from(mode: .listening, origin: .button, lastCopiedAt: nil, errorMessage: nil, now: now), .recording)
        XCTAssertEqual(FloatingButtonState.from(mode: .listening, origin: .hotkey, lastCopiedAt: nil, errorMessage: nil, now: now), .busy)
        XCTAssertEqual(FloatingButtonState.from(mode: .processing, origin: nil, lastCopiedAt: nil, errorMessage: nil, now: now), .processing)
        XCTAssertEqual(FloatingButtonState.from(mode: .idle, origin: nil, lastCopiedAt: now.addingTimeInterval(-0.5), errorMessage: nil, now: now), .copied)
        XCTAssertEqual(FloatingButtonState.from(mode: .idle, origin: nil, lastCopiedAt: now.addingTimeInterval(-2), errorMessage: nil, now: now), .idle)
        XCTAssertEqual(FloatingButtonState.from(mode: .error, origin: nil, lastCopiedAt: nil, errorMessage: "No speech", now: now), .error("No speech"))
    }
}
