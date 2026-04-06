import XCTest
@testable import HDText

final class GeminiLiveServiceTests: XCTestCase {
    private var service: GeminiLiveTranscriptionService!

    override func setUp() {
        super.setUp()
        service = GeminiLiveTranscriptionService()
    }

    override func tearDown() {
        service.endSession()
        service = nil
        super.tearDown()
    }

    func testInitialTranscriptIsEmpty() {
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testEndSessionBeforeStartDoesNotCrash() {
        service.endSession()
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testSendAudioBeforeStartIsNoOp() {
        let data = Data(repeating: 0, count: 320)
        service.sendAudio(data)
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testDoubleEndSessionDoesNotCrash() {
        service.endSession()
        service.endSession()
    }
}
