import Foundation

struct GeminiModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let apiModelName: String
    let supportsLive: Bool
    let supportsText: Bool
}

enum GeminiModelCatalog {
    static let allModels: [GeminiModel] = [
        GeminiModel(id: "2.5-flash",           displayName: "Gemini 2.5 Flash",          apiModelName: "gemini-2.5-flash",                supportsLive: false, supportsText: true),
        GeminiModel(id: "2.5-flash-lite",      displayName: "Gemini 2.5 Flash Lite",     apiModelName: "gemini-2.5-flash-lite",           supportsLive: false, supportsText: true),
        GeminiModel(id: "2.5-pro",             displayName: "Gemini 2.5 Pro",            apiModelName: "gemini-2.5-pro",                  supportsLive: false, supportsText: true),
        GeminiModel(id: "3-flash",             displayName: "Gemini 3 Flash",            apiModelName: "gemini-3-flash-preview",           supportsLive: false, supportsText: true),
        GeminiModel(id: "3.1-flash-lite",      displayName: "Gemini 3.1 Flash Lite",     apiModelName: "gemini-3.1-flash-lite-preview",    supportsLive: false, supportsText: true),
        GeminiModel(id: "3.1-pro",             displayName: "Gemini 3.1 Pro",            apiModelName: "gemini-3.1-pro-preview",           supportsLive: false, supportsText: true),
    ]

    static var liveModels: [GeminiModel] { allModels.filter(\.supportsLive) }
    static var textModels: [GeminiModel] { allModels.filter(\.supportsText) }
    static var transcriptionModels: [GeminiModel] { allModels.filter(\.supportsText) }

    static let defaultTranscriptionID = "2.5-flash-lite"
    static let defaultTextID = "2.5-flash"

    static func model(forID id: String) -> GeminiModel? {
        allModels.first { $0.id == id }
    }

    static func apiName(forID id: String, fallback: String) -> String {
        model(forID: id)?.apiModelName ?? fallback
    }
}
