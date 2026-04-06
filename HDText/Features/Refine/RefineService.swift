import Foundation
import GoogleGenerativeAI

final class RefineService {
    func refine(
        text: String,
        action: RefineAction,
        modelName: String,
        apiKey: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw RefineError.emptyInput
        }

        let systemInstruction = ModelContent(
            role: "system",
            parts: action.systemPrompt
        )

        let model = GenerativeModel(
            name: modelName,
            apiKey: apiKey,
            systemInstruction: systemInstruction
        )

        let response = try await model.generateContent(trimmed)

        guard let result = response.text else {
            throw RefineError.emptyResponse
        }

        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

enum RefineError: LocalizedError {
    case emptyInput
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "No text to refine"
        case .emptyResponse: return "Gemini returned an empty response"
        }
    }
}
