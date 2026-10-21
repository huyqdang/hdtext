import XCTest
@testable import HDText

final class HotkeyManagerTests: XCTestCase {
    private var manager: HotkeyManager!
    private var savedMods: Any?
    private var savedKeyCode: Any?

    override func setUp() {
        super.setUp()
        savedMods = UserDefaults.standard.object(forKey: "hotkeyModifiers")
        savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        manager = HotkeyManager()
    }

    override func tearDown() {
        manager.stopMonitoring()
        manager = nil
        if let savedMods { UserDefaults.standard.set(savedMods, forKey: "hotkeyModifiers") }
        else { UserDefaults.standard.removeObject(forKey: "hotkeyModifiers") }
        if let savedKeyCode { UserDefaults.standard.set(savedKeyCode, forKey: "hotkeyKeyCode") }
        else { UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode") }
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

    // MARK: - Hold State Management

    func testResetHoldStateClearsHolding() {
        manager.onHoldStarted = {}
        manager.onHoldEnded = {}

        manager.resetHoldState()
        XCTAssertFalse(manager.isHolding, "resetHoldState should clear isHolding")
    }

    func testForceReleaseCallsOnHoldEnded() {
        var endedCalled = false
        manager.onHoldEnded = { endedCalled = true }

        manager.forceRelease()
        XCTAssertFalse(endedCalled, "forceRelease should not fire when not holding")
    }

    func testStopMonitoringResetsState() {
        manager.stopMonitoring()
        XCTAssertFalse(manager.isHolding)
        XCTAssertFalse(manager.isMonitoring)
    }
}
