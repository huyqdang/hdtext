import XCTest
import AppKit
@testable import HDText

final class TextInsertionServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private let customType = NSPasteboard.PasteboardType("com.hdtext.tests.custom")

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.hdtext.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testRestoreBringsBackAllOriginalTypes() {
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([9, 8, 7]), forType: customType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)

        XCTAssertTrue(TextInsertionService.restore(snapshot, to: pasteboard, ifChangeCountIs: pasteboard.changeCount))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: customType), Data([9, 8, 7]))
    }

    func testRestoreSkippedWhenUserCopiedSomethingNewer() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot.capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let ours = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("user copied", forType: .string)

        XCTAssertFalse(TextInsertionService.restore(snapshot, to: pasteboard, ifChangeCountIs: ours))
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied")
    }
}
