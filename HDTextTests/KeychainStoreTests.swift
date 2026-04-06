import XCTest
@testable import HDText

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore()
        store.deleteAPIKey()
    }

    override func tearDown() {
        store.deleteAPIKey()
        store = nil
        super.tearDown()
    }

    func testSaveAndRetrieveAPIKey() {
        let key = "test-api-key-12345"

        let saved = store.saveAPIKey(key)
        XCTAssertTrue(saved)

        let retrieved = store.retrieveAPIKey()
        XCTAssertEqual(retrieved, key)
    }

    func testRetrieveReturnsNilWhenNoKey() {
        let retrieved = store.retrieveAPIKey()
        XCTAssertNil(retrieved)
    }

    func testDeleteAPIKey() {
        store.saveAPIKey("to-be-deleted")
        store.deleteAPIKey()

        let retrieved = store.retrieveAPIKey()
        XCTAssertNil(retrieved)
    }

    func testSaveOverwritesPreviousKey() {
        store.saveAPIKey("first-key")
        store.saveAPIKey("second-key")

        let retrieved = store.retrieveAPIKey()
        XCTAssertEqual(retrieved, "second-key")
    }
}
