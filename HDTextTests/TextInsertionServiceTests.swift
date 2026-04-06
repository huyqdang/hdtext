import XCTest
@testable import HDText

final class TextInsertionServiceTests: XCTestCase {
    private var service: TextInsertionService!

    override func setUp() {
        super.setUp()
        service = TextInsertionService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testFrontmostAppNameReturnsString() {
        let name = TextInsertionService.frontmostAppName()
        XCTAssertFalse(name.isEmpty)
    }

    func testCheckAccessibilityPermissionReturnsBool() {
        let result = TextInsertionService.checkAccessibilityPermission()
        XCTAssertNotNil(result)
    }

    func testInsertTextReturnsBoolResult() {
        let result = service.insertText("Test text")
        // May return false without accessibility permission, but must not crash
        XCTAssertNotNil(result)
    }
}
