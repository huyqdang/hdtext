import XCTest
@testable import HDText

final class GeminiTranscriptionServiceTests: XCTestCase {
    private var service: GeminiTranscriptionService!

    override func setUp() {
        super.setUp()
        service = GeminiTranscriptionService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testEmptyAudioThrows() async {
        do {
            _ = try await service.transcribe(audioData: Data(), apiKey: "test-key")
            XCTFail("Expected error for empty audio")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .noAudio)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
