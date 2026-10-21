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
