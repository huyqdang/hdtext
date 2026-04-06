import XCTest
@testable import HDText

final class GeminiRewriteServiceTests: XCTestCase {
    private var service: GeminiRewriteService!

    override func setUp() {
        super.setUp()
        service = GeminiRewriteService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testEmptyTranscriptThrows() async {
        do {
            _ = try await service.rewrite(
                roughTranscript: "",
                aggressiveness: .balanced,
                apiKey: "fake-key"
            )
            XCTFail("Should have thrown emptyTranscript")
        } catch let error as RewriteError {
            XCTAssertEqual(error, .emptyTranscript)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhitespaceOnlyTranscriptThrows() async {
        do {
            _ = try await service.rewrite(
                roughTranscript: "   \n  ",
                aggressiveness: .balanced,
                apiKey: "fake-key"
            )
            XCTFail("Should have thrown emptyTranscript")
        } catch let error as RewriteError {
            XCTAssertEqual(error, .emptyTranscript)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVeryShortTranscriptReturnedAsIs() async throws {
        let result = try await service.rewrite(
            roughTranscript: "yes",
            aggressiveness: .balanced,
            apiKey: "fake-key"
        )
        XCTAssertEqual(result, "yes")
    }

    func testTwoWordTranscriptReturnedAsIs() async throws {
        let result = try await service.rewrite(
            roughTranscript: "hello world",
            aggressiveness: .minimal,
            apiKey: "fake-key"
        )
        XCTAssertEqual(result, "hello world")
    }
}

extension RewriteError: Equatable {
    public static func == (lhs: RewriteError, rhs: RewriteError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyResponse, .emptyResponse): return true
        case (.emptyTranscript, .emptyTranscript): return true
        default: return false
        }
    }
}
