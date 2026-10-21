import Foundation

final class RefineService {
    private let client: GeminiClient

    init(client: GeminiClient = GeminiClient()) {
        self.client = client
    }

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

        return try await client.generate(
            model: modelName,
            apiKey: apiKey,
            systemPrompt: action.systemPrompt,
            parts: [.text(trimmed)],
            options: GeminiGenerationOptions(
                temperature: 0.7,
                thinkingLevel: GeminiModelCatalog.thinkingLevel(forAPIName: modelName)))
    }
}

enum RefineError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "No text to refine"
        }
    }
}
