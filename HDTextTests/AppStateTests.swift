import XCTest
@testable import HDText

@MainActor
final class AppStateTests: XCTestCase {
    func testInitialModeIsIdle() {
        let state = AppState()
        XCTAssertEqual(state.mode, .idle)
    }

    func testInitialTranscriptsAreEmpty() {
        let state = AppState()
        XCTAssertTrue(state.roughTranscript.isEmpty)
        XCTAssertTrue(state.cleanedText.isEmpty)
    }

    func testDefaultRewriteAggressiveness() {
        let state = AppState()
        XCTAssertEqual(state.rewriteAggressiveness, .balanced)
    }

    func testHasAPIKeyReturnsFalseWhenNoKey() {
        let state = AppState()
        state.keychainStore.deleteAPIKey()
        XCTAssertFalse(state.hasAPIKey)
    }

    func testModeTransitions() {
        let state = AppState()

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
