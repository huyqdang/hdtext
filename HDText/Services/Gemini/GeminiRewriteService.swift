import Foundation
import GoogleGenerativeAI

final class GeminiRewriteService {
    private let maxOutputRatio = 1.5

    func rewrite(
        roughTranscript: String,
        aggressiveness: RewriteAggressiveness,
        modelName: String = "gemini-2.5-flash",
        apiKey: String
    ) async throws -> String {
        let trimmed = roughTranscript.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw RewriteError.emptyTranscript
        }

        if trimmed.split(separator: " ").count <= 2 {
            return trimmed
        }

        let systemInstruction = ModelContent(
            role: "system",
            parts: buildSystemPrompt(for: aggressiveness)
        )

        let model = GenerativeModel(
            name: modelName,
            apiKey: apiKey,
            systemInstruction: systemInstruction
        )

        let prompt = """
        Transcript to clean up:

        \(trimmed)
        """

        let response = try await model.generateContent(prompt)

        guard let text = response.text else {
            throw RewriteError.emptyResponse
        }

        let cleaned = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if Double(cleaned.count) > Double(trimmed.count) * maxOutputRatio && cleaned.count > trimmed.count + 100 {
            return trimmed
        }

        return cleaned
    }

    private func buildSystemPrompt(for aggressiveness: RewriteAggressiveness) -> String {
        let base = """
        You are an editor, not an author. Your task is to clean up a speech transcript.

        STRICT RULES:
        - NEVER add new information or facts
        - NEVER change the speaker's intent or meaning
        - ALWAYS preserve: names, numbers, technical terms, negations, modal verbs (might, must, should)
        - ALWAYS preserve the speaker's original language
        - Output ONLY the cleaned text, nothing else — no preamble, no explanation
        """

        switch aggressiveness {
        case .minimal:
            return base + """

            MINIMAL CLEANUP MODE:
            - Remove filler words (um, uh, like, you know, basically, literally)
            - Remove false starts and repeated words
            - Add basic punctuation (periods, commas, question marks)
            - Do NOT restructure sentences
            - Do NOT change word choices
            """

        case .balanced:
            return base + """

            BALANCED MODE:
            - Remove all filler words and verbal tics
            - Remove false starts, repeated words, and self-corrections
            - Fix grammar errors
            - Add proper punctuation and sentence breaks
            - Light restructuring for readability only when the original is confusing
            - Preserve the speaker's natural tone and vocabulary
            """

        case .polished:
            return base + """

            POLISHED MODE:
            - Remove all filler words, false starts, and repetition
            - Fix grammar and improve sentence structure
            - Add proper punctuation and paragraph breaks
            - Restructure for clarity and flow
            - Maintain the speaker's voice and intent
            - The result should read as well-written prose
            """
        }
    }
}

enum RewriteError: LocalizedError {
    case emptyResponse
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .emptyResponse: return "Gemini returned an empty response"
        case .emptyTranscript: return "No speech was captured"
        }
    }
}
