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
            _ = try await service.transcribe(audioData: Data(), modelName: "gemini-3.5-flash-lite", apiKey: "test-key")
            XCTFail("Expected error for empty audio")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .noAudio)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTranscribeSendsWavWithModelThinkingLevel() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses = [(200, Data(#"{"candidates":[{"content":{"parts":[{"text":"Hello there, this is a dictation test."}]}}]}"#.utf8))]
        let service = GeminiTranscriptionService(client: GeminiClient(session: StubURLProtocol.makeSession()))

        let text = try await service.transcribeAndClean(
            audioData: Data(repeating: 1, count: 3200), modelName: "gemini-3.5-flash-lite", apiKey: "AQ.k")

        XCTAssertEqual(text, "Hello there, this is a dictation test.")
        let body = StubURLProtocol.bodyJSON(of: try XCTUnwrap(StubURLProtocol.requests.first))
        let parts = ((body["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]]
        let inline = parts?.first?["inlineData"] as? [String: Any]
        XCTAssertEqual(inline?["mimeType"] as? String, "audio/wav")
        let gen = body["generationConfig"] as? [String: Any]
        XCTAssertEqual((gen?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "minimal")
        StubURLProtocol.reset()
    }

    func testPhantomFilterKeepsRealSentencesAndRejectsExactPhrase() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses = [
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"Thank you for sending that over."}]}}]}"#.utf8)),
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"Thank you."}]}}]}"#.utf8)),
        ]
        let service = GeminiTranscriptionService(client: GeminiClient(session: StubURLProtocol.makeSession()))
        let audio = Data(repeating: 1, count: 3200)

        let text = try await service.transcribeAndClean(audioData: audio, modelName: "gemini-3.5-flash-lite", apiKey: "k")
        XCTAssertEqual(text, "Thank you for sending that over.")

        do {
            _ = try await service.transcribeAndClean(audioData: audio, modelName: "gemini-3.5-flash-lite", apiKey: "k")
            XCTFail("Expected exact phantom phrase to be rejected")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .noSpeechDetected)
        }
        StubURLProtocol.reset()
    }

    // MARK: - Prompt Construction: Filler Removal

    func testBalancedPromptIncludesAggressiveFillerRemoval() {
        let prompt = service.buildSystemPrompt(aggressiveness: .balanced, smartCorrection: false)
        XCTAssertTrue(prompt.contains("umm"), "Should list umm as a filler variant")
        XCTAssertTrue(prompt.contains("ahh"), "Should list ahh as a filler variant")
        XCTAssertTrue(prompt.contains("uhh"), "Should list uhh as a filler variant")
        XCTAssertTrue(prompt.contains("Remove ALL filler words"), "Should emphasize removing ALL fillers")
        XCTAssertTrue(prompt.contains("middle, or end of a sentence"), "Should specify mid-sentence removal")
    }

    func testBalancedCleanupLevelReinforcesFillerRemoval() {
        let prompt = service.buildSystemPrompt(aggressiveness: .balanced, smartCorrection: false)
        XCTAssertTrue(
            prompt.contains("Remove ALL filler words and hesitation sounds, even mid-sentence"),
            "Balanced cleanup level should explicitly reinforce filler removal"
        )
    }

    func testMinimalPromptKeepsOriginalPhrasing() {
        let prompt = service.buildSystemPrompt(aggressiveness: .minimal, smartCorrection: false)
        XCTAssertTrue(prompt.contains("Keep original phrasing"))
    }

    func testPolishedPromptImprovesStructure() {
        let prompt = service.buildSystemPrompt(aggressiveness: .polished, smartCorrection: false)
        XCTAssertTrue(prompt.contains("Improve sentence structure"))
    }

    // MARK: - Prompt Construction: Smart Correction

    func testSmartCorrectionEnabledIncludesGuardrails() {
        let prompt = service.buildSystemPrompt(aggressiveness: .balanced, smartCorrection: true)
        XCTAssertTrue(prompt.contains("SMART CORRECTION"), "Should include smart correction block")
        XCTAssertTrue(prompt.contains("phonetically similar"), "Should require phonetic similarity")
        XCTAssertTrue(prompt.contains("If unsure, keep the original"), "Should have conservative fallback")
        XCTAssertTrue(
            prompt.contains("NEVER replace names, numbers, technical terms"),
            "Should protect domain vocabulary"
        )
    }

    func testSmartCorrectionDisabledExcludesBlock() {
        let prompt = service.buildSystemPrompt(aggressiveness: .balanced, smartCorrection: false)
        XCTAssertFalse(prompt.contains("SMART CORRECTION"), "Should not include smart correction block")
        XCTAssertFalse(prompt.contains("phonetically similar"))
    }

    // MARK: - Prompt Construction: Invariants

    func testAllModesPreserveNames() {
        for mode in RewriteAggressiveness.allCases {
            let prompt = service.buildSystemPrompt(aggressiveness: mode, smartCorrection: false)
            XCTAssertTrue(
                prompt.contains("Preserve ALL names, numbers, technical terms"),
                "\(mode.rawValue) mode should preserve names"
            )
        }
    }

    func testAllModesIncludeNoSpeechRule() {
        for mode in RewriteAggressiveness.allCases {
            let prompt = service.buildSystemPrompt(aggressiveness: mode, smartCorrection: false)
            XCTAssertTrue(
                prompt.contains("[NO_SPEECH]"),
                "\(mode.rawValue) mode should include NO_SPEECH rule"
            )
        }
    }
}
