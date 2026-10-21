import Foundation

struct GeminiModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let apiModelName: String
    /// thinkingConfig.thinkingLevel sent with requests; nil = omit.
    let thinkingLevel: String?
}

enum GeminiModelCatalog {
    static let allModels: [GeminiModel] = [
        GeminiModel(id: "3.5-flash-lite", displayName: "Gemini 3.5 Flash-Lite", apiModelName: "gemini-3.5-flash-lite", thinkingLevel: "minimal"),
        GeminiModel(id: "3.1-flash-lite", displayName: "Gemini 3.1 Flash-Lite", apiModelName: "gemini-3.1-flash-lite", thinkingLevel: "minimal"),
        GeminiModel(id: "3.8-flash",      displayName: "Gemini 3.8 Flash",      apiModelName: "gemini-3.8-flash",      thinkingLevel: "low"),
        GeminiModel(id: "3.6-flash",      displayName: "Gemini 3.6 Flash",      apiModelName: "gemini-3.6-flash",      thinkingLevel: "low"),
        GeminiModel(id: "4-argon",        displayName: "Gemini 4 Argon",        apiModelName: "gemini-4-argon",        thinkingLevel: "low"),
    ]

    static var textModels: [GeminiModel] { allModels }
    static var transcriptionModels: [GeminiModel] { allModels }

    static let defaultTranscriptionID = "3.5-flash-lite"
    static let defaultTextID = "3.8-flash"

    static func model(forID id: String) -> GeminiModel? {
        allModels.first { $0.id == id }
    }

    static func model(forAPIName name: String) -> GeminiModel? {
        allModels.first { $0.apiModelName == name }
    }

    static func apiName(forID id: String, fallback: String) -> String {
        model(forID: id)?.apiModelName ?? fallback
    }

    /// Returns `id` if it is still in the catalog, otherwise `fallback` (retired models).
    static func migrate(id: String?, fallback: String) -> String {
        guard let id, model(forID: id) != nil else { return fallback }
        return id
    }

    static func thinkingLevel(forAPIName name: String) -> String? {
        model(forAPIName: name)?.thinkingLevel
    }
}
