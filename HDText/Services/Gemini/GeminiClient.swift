import Foundation

enum GeminiAPIError: LocalizedError, Equatable {
    case invalidKey
    case modelUnavailable(String)
    case rateLimited
    case server(Int)
    case badRequest(String)
    case blocked
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Gemini rejected the API key. Check it in Settings › API Key."
        case .modelUnavailable(let model):
            return "Model \(model) isn't available for this key. Pick another in Settings › Models."
        case .rateLimited:
            return "Gemini rate limit reached. Wait a moment and try again."
        case .server(let status):
            return "Gemini server error (\(status)). Try again shortly."
        case .badRequest(let message):
            return "Gemini request failed: \(message)"
        case .blocked:
            return "Gemini blocked this response."
        case .emptyResponse:
            return "Gemini returned an empty response."
        case .network(let description):
            return "Network error: \(description)"
        }
    }
}

enum GeminiPart: Equatable {
    case text(String)
    case inlineData(mimeType: String, data: Data)
}

struct GeminiGenerationOptions: Equatable {
    var temperature: Double
    var maxOutputTokens: Int? = nil
    var thinkingLevel: String? = nil
}

/// Minimal REST client for the Gemini Developer API (generateContent + models list).
final class GeminiClient {
    static let baseURLString = "https://generativelanguage.googleapis.com/v1beta"

    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private let session: URLSession

    init(session: URLSession = GeminiClient.defaultSession) {
        self.session = session
    }

    func generate(
        model: String,
        apiKey: String,
        systemPrompt: String?,
        parts: [GeminiPart],
        options: GeminiGenerationOptions
    ) async throws -> String {
        let wantsThinking = options.thinkingLevel != nil
        do {
            return try await send(model: model, apiKey: apiKey, systemPrompt: systemPrompt,
                                  parts: parts, options: options, includeThinking: wantsThinking)
        } catch GeminiAPIError.badRequest(let message) where wantsThinking && message.lowercased().contains("thinking") {
            hdLog("Model \(model) rejected thinkingConfig — retrying without it")
            return try await send(model: model, apiKey: apiKey, systemPrompt: systemPrompt,
                                  parts: parts, options: options, includeThinking: false)
        }
    }

    func listModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(Self.baseURLString)/models?pageSize=1000")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let data = try await perform(request, model: "")
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let models = json["models"] as? [[String: Any]] ?? []
        return models.compactMap { entry in
            guard let name = entry["name"] as? String,
                  (entry["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
    }

    // MARK: - Internals

    private func send(
        model: String, apiKey: String, systemPrompt: String?,
        parts: [GeminiPart], options: GeminiGenerationOptions, includeThinking: Bool
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "\(Self.baseURLString)/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Self.makeRequestBody(systemPrompt: systemPrompt, parts: parts,
                                        options: options, includeThinking: includeThinking)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request, model: model)
        return try Self.parseText(from: data)
    }

    private func perform(_ request: URLRequest, model: String) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            throw GeminiAPIError.network(error.localizedDescription)
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = Self.mapError(status: status, body: data, model: model)
            hdLog("Gemini HTTP \(status) → \(error)")
            throw error
        }
        return data
    }

    static func makeRequestBody(
        systemPrompt: String?, parts: [GeminiPart],
        options: GeminiGenerationOptions, includeThinking: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        if let systemPrompt {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }
        let partObjects: [[String: Any]] = parts.map { part in
            switch part {
            case .text(let text):
                return ["text": text]
            case .inlineData(let mimeType, let data):
                return ["inlineData": ["mimeType": mimeType, "data": data.base64EncodedString()]]
            }
        }
        body["contents"] = [["role": "user", "parts": partObjects]]

        var generationConfig: [String: Any] = ["temperature": options.temperature]
        if let maxOutputTokens = options.maxOutputTokens {
            generationConfig["maxOutputTokens"] = maxOutputTokens
        }
        if includeThinking, let level = options.thinkingLevel {
            generationConfig["thinkingConfig"] = ["thinkingLevel": level]
        }
        body["generationConfig"] = generationConfig
        return body
    }

    static func parseText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiAPIError.emptyResponse
        }
        if let feedback = json["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            throw GeminiAPIError.blocked
        }
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            throw GeminiAPIError.emptyResponse
        }
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            let blockedReasons = ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION"]
            if let reason = candidate["finishReason"] as? String, blockedReasons.contains(reason) {
                throw GeminiAPIError.blocked
            }
            throw GeminiAPIError.emptyResponse
        }
        return text
    }

    static func mapError(status: Int, body: Data, model: String) -> GeminiAPIError {
        let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? ""
        let raw = String(data: body, encoding: .utf8) ?? ""
        switch status {
        case 401, 403:
            return .invalidKey
        case 400:
            if raw.contains("API_KEY_INVALID") || message.localizedCaseInsensitiveContains("api key") {
                return .invalidKey
            }
            return .badRequest(message.isEmpty ? "HTTP 400" : message)
        case 404:
            return .modelUnavailable(model)
        case 429:
            return .rateLimited
        case 500...599:
            return .server(status)
        default:
            return .badRequest(message.isEmpty ? "HTTP \(status)" : message)
        }
    }
}
