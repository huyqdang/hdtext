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

    func testOverlappingPastesRestoreTheUsersOriginalClipboard() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        let snapshotA = TextInsertionService.captureOriginal(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("A", forType: .string)
        TextInsertionService.markOurWrite(snapshotA, changeCount: pasteboard.changeCount, on: pasteboard)

        let snapshotB = TextInsertionService.captureOriginal(pasteboard)
        XCTAssertEqual(snapshotB.items.first?[.string], Data("original".utf8))
        pasteboard.clearContents()
        pasteboard.setString("B", forType: .string)
        let ourB = pasteboard.changeCount
        TextInsertionService.markOurWrite(snapshotB, changeCount: ourB, on: pasteboard)

        XCTAssertTrue(TextInsertionService.restore(snapshotB, to: pasteboard, ifChangeCountIs: ourB))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
