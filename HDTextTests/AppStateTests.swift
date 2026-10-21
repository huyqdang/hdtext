import XCTest
@testable import HDText

@MainActor
final class AppStateTests: XCTestCase {
    func testInitialModeIsIdle() {
        let state = AppState(keychainStore: KeychainStore(service: "com.hdtext.app.tests"))
        XCTAssertEqual(state.mode, .idle)
    }

    func testInitialTranscriptsAreEmpty() {
        let state = AppState(keychainStore: KeychainStore(service: "com.hdtext.app.tests"))
        XCTAssertTrue(state.roughTranscript.isEmpty)
        XCTAssertTrue(state.cleanedText.isEmpty)
    }

    func testDefaultRewriteAggressiveness() {
        let state = AppState(keychainStore: KeychainStore(service: "com.hdtext.app.tests"))
        XCTAssertEqual(state.rewriteAggressiveness, .balanced)
    }

    func testAPIKeySaveTrimsAndCachesWithoutRealKeychainItem() {
        let store = KeychainStore(service: "com.hdtext.app.tests")
        store.deleteAPIKey()
        let state = AppState(keychainStore: store)
        XCTAssertFalse(state.hasAPIKey)

        XCTAssertTrue(state.saveAPIKey("  AQ.Ab-test-key \n"))
        XCTAssertEqual(state.apiKey, "AQ.Ab-test-key")
        XCTAssertEqual(store.retrieveAPIKey(), "AQ.Ab-test-key")

        state.removeAPIKey()
        XCTAssertNil(state.apiKey)
        XCTAssertNil(store.retrieveAPIKey())
    }

    func testModeTransitions() {
        let state = AppState(keychainStore: KeychainStore(service: "com.hdtext.app.tests"))

        state.mode = .listening
        XCTAssertEqual(state.mode, .listening)

        state.mode = .processing
        XCTAssertEqual(state.mode, .processing)

        state.mode = .error
        XCTAssertEqual(state.mode, .error)

        state.mode = .idle
        XCTAssertEqual(state.mode, .idle)
    }
}
