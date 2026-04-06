import XCTest
@testable import HDText

final class HotkeyManagerTests: XCTestCase {
    private var manager: HotkeyManager!

    override func setUp() {
        super.setUp()
        manager = HotkeyManager()
    }

    override func tearDown() {
        manager.stopMonitoring()
        manager = nil
        super.tearDown()
    }

    func testDefaultShortcutDescription() {
        let description = manager.shortcutDescription
        XCTAssertTrue(description.contains("⌃"))
        XCTAssertTrue(description.contains("⌥"))
        XCTAssertTrue(description.contains("Space"))
    }

    func testUpdateShortcutPersists() {
        manager.updateShortcut(
            modifiers: [.command, .shift],
            keyCode: 1
        )

        let newManager = HotkeyManager()
        let desc = newManager.shortcutDescription
        XCTAssertTrue(desc.contains("⌘"))
        XCTAssertTrue(desc.contains("⇧"))

        manager.updateShortcut(modifiers: [.control, .option], keyCode: 49)
    }

    func testCallbacksAreSettable() {
        var holdStarted = false
        var holdEnded = false

        manager.onHoldStarted = { holdStarted = true }
        manager.onHoldEnded = { holdEnded = true }

        XCTAssertNotNil(manager.onHoldStarted)
        XCTAssertNotNil(manager.onHoldEnded)
    }
}
