# HDText Revival Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make HDText work on today's Gemini API (REST client, current models, any key format) and fix the reliability bugs in the last build.

**Architecture:** Replace the archived `generative-ai-swift` SDK with a small URLSession `GeminiClient`. Services (`GeminiTranscriptionService`, `RefineService`) call it. Clipboard paste goes through one `TextInsertionService.paste` path with full snapshot/restore. `AppState` caches the API key in memory.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 14+, XcodeGen (`project.yml`), XCTest.

Spec: `docs/superpowers/specs/2026-10-21-hdtext-revival-design.md`

## Global Constraints
- Worktree: `/Users/huydang/Desktop/projects/hdtext-revive` (branch `revive-2026-10`). Never edit `/Users/huydang/Desktop/projects/hdtext` (the user's main tree).
- The `.xcodeproj` is gitignored and generated. After adding/removing files run `xcodegen generate`.
- Build/test env: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. DerivedData: `-derivedDataPath /private/tmp/claude-501/-Users-huydang-Documents/ce759666-9dc7-49e4-af61-951e51bca006/scratchpad/dd-revive`.
- Focused test command (replace `<Suite>`):
  ```bash
  cd /Users/huydang/Desktop/projects/hdtext-revive && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild -project HDText.xcodeproj -scheme HDText -derivedDataPath /private/tmp/claude-501/-Users-huydang-Documents/ce759666-9dc7-49e4-af61-951e51bca006/scratchpad/dd-revive test -only-testing:HDTextTests/<Suite> 2>&1 | grep -E "error:|Executed|FAILED|failed \(|\*\* TEST" | head -40
  ```
  Full suite: same without `-only-testing:...`. Run full suite once at the end of each task.
- Gemini endpoint: `https://generativelanguage.googleapis.com/v1beta`. Auth ONLY via header `x-goog-api-key`. Never `?key=`, never `Authorization: Bearer`.
- Never validate API-key format/prefix (new keys start `AQ.`, old `AIza`). Trim whitespace/newlines only.
- Tests must never touch the real Keychain item (service `com.hdtext.app`), the real clipboard, or post real keystrokes.
- Tests run inside the app test host: `UserDefaults.standard` is the user's real prefs. Tests that change a pref must save and restore the original value.
- Tests: core behaviour only, one good test per behaviour. No UI-copy assertions.
- Commit at the end of each task with a message ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Match surrounding code style (4-space indent, `hdLog(...)` for logging, no excess comments).

## File Map
| File | Task | Responsibility |
|---|---|---|
| `HDText/Services/Gemini/GeminiClient.swift` (new) | 1 | REST generateContent + listModels + error mapping |
| `HDText/Services/Gemini/GeminiModelCatalog.swift` | 1 | curated models, thinking level, migration |
| `HDTextTests/Support/StubURLProtocol.swift` (new) | 1 | URLProtocol stub for HTTP tests |
| `HDTextTests/GeminiClientTests.swift` (new) | 1 | client tests |
| `HDText/Services/Insertion/TextInsertionService.swift` | 2 | `PasteboardSnapshot`, `paste(_:into:)`, `postCommandKey` |
| `HDText/Services/Audio/AudioCaptureEngine.swift` | 3 | `PCM16Resampler` via AVAudioConverter |
| `HDText/Services/Security/KeychainStore.swift`, `HDText/App/AppState.swift` | 4 | key cache, injectable service, model migration |
| `HDText/Services/Gemini/GeminiTranscriptionService.swift`, `HDText/Features/Refine/RefineService.swift`, deletions, `project.yml` | 5 | services on GeminiClient, drop SDK |
| `HDText/Views/APIKeyTestButton.swift` (new), `HDText/Services/Util/AccessibilityPermission.swift` (new), `SettingsView.swift`, `MenuBarController.swift`, `CalibrationView.swift`, `HistoryDetailView.swift` | 6 | UI call sites, Test key, AX reset, menu delegate |
| `HDText/App/AppDelegate.swift`, `HDText/Features/Onboarding/OnboardingView.swift` | 7 | dictation flow fixes, onboarding |
| `HDText/Features/Refine/RefinePreviewController.swift`, `RefinePreviewView.swift` | 8 | refine window fixes |
| `README.md`, `project.yml` version, `scripts/build-dmg.sh` | 9 | docs, version, release build |

Tasks run sequentially (shared worktree + one Xcode build dir). Each task leaves the app compiling and tests green.

---

### Task 1: GeminiClient + model catalog  (model: opus)

**Files:**
- Create: `HDText/Services/Gemini/GeminiClient.swift`
- Modify: `HDText/Services/Gemini/GeminiModelCatalog.swift` (full rewrite)
- Create: `HDTextTests/Support/StubURLProtocol.swift`, `HDTextTests/GeminiClientTests.swift`

**Interfaces — Produces:**
```swift
enum GeminiAPIError: LocalizedError, Equatable {
    case invalidKey, modelUnavailable(String), rateLimited, server(Int), badRequest(String), blocked, emptyResponse, network(String)
}
enum GeminiPart: Equatable { case text(String); case inlineData(mimeType: String, data: Data) }
struct GeminiGenerationOptions: Equatable { var temperature: Double; var maxOutputTokens: Int? = nil; var thinkingLevel: String? = nil }
final class GeminiClient {
    static let baseURLString = "https://generativelanguage.googleapis.com/v1beta"
    init(session: URLSession = GeminiClient.defaultSession)
    func generate(model: String, apiKey: String, systemPrompt: String?, parts: [GeminiPart], options: GeminiGenerationOptions) async throws -> String
    func listModels(apiKey: String) async throws -> [String]   // ids without "models/" prefix, only those supporting generateContent
    static func makeRequestBody(systemPrompt: String?, parts: [GeminiPart], options: GeminiGenerationOptions, includeThinking: Bool) -> [String: Any]
    static func parseText(from data: Data) throws -> String
    static func mapError(status: Int, body: Data, model: String) -> GeminiAPIError
}
struct GeminiModel: Identifiable, Hashable { let id: String; let displayName: String; let apiModelName: String; let thinkingLevel: String? }
enum GeminiModelCatalog {
    static let allModels: [GeminiModel]
    static var textModels: [GeminiModel]; static var transcriptionModels: [GeminiModel]
    static let defaultTranscriptionID = "3.5-flash-lite"; static let defaultTextID = "3.8-flash"
    static func model(forID: String) -> GeminiModel?
    static func model(forAPIName: String) -> GeminiModel?
    static func apiName(forID: String, fallback: String) -> String
    static func migrate(id: String?, fallback: String) -> String
    static func thinkingLevel(forAPIName: String) -> String?
}
// Test support (HDTextTests target)
final class StubURLProtocol: URLProtocol {
    static var responses: [(Int, Data)]; static var requests: [URLRequest]
    static func reset(); static func makeSession() -> URLSession; static func bodyJSON(of: URLRequest) -> [String: Any]
}
```

- [ ] **Step 1: Write the stub + failing tests**

`HDTextTests/Support/StubURLProtocol.swift`:
```swift
import Foundation

/// Serves queued (status, body) responses in order and records every request.
final class StubURLProtocol: URLProtocol {
    static var responses: [(Int, Data)] = []
    static var requests: [URLRequest] = []

    static func reset() {
        responses = []
        requests = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func bodyJSON(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.responses.isEmpty ? (500, Data()) : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

`HDTextTests/GeminiClientTests.swift`:
```swift
import XCTest
@testable import HDText

final class GeminiClientTests: XCTestCase {
    private var client: GeminiClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = GeminiClient(session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testGenerateSendsKeyHeaderAndAudioAndSkipsThoughtParts() async throws {
        StubURLProtocol.responses = [(200, json("""
        {"candidates":[{"content":{"role":"model","parts":[
          {"text":"let me think","thought":true},{"text":"Hello world"}]},"finishReason":"STOP"}]}
        """))]
        let audio = Data([1, 2, 3, 4])

        let text = try await client.generate(
            model: "gemini-3.5-flash-lite", apiKey: "AQ.test-key", systemPrompt: "SYS",
            parts: [.inlineData(mimeType: "audio/wav", data: audio), .text("Transcribe.")],
            options: GeminiGenerationOptions(temperature: 0.2, thinkingLevel: "minimal"))

        XCTAssertEqual(text, "Hello world")
        let req = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "AQ.test-key")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))

        let body = StubURLProtocol.bodyJSON(of: req)
        let sys = (body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]]
        XCTAssertEqual(sys?.first?["text"] as? String, "SYS")
        let parts = ((body["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]]
        let inline = parts?.first?["inlineData"] as? [String: Any]
        XCTAssertEqual(inline?["mimeType"] as? String, "audio/wav")
        XCTAssertEqual(inline?["data"] as? String, audio.base64EncodedString())
        let gen = body["generationConfig"] as? [String: Any]
        XCTAssertEqual((gen?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "minimal")
    }

    func testErrorMapping() {
        XCTAssertEqual(GeminiClient.mapError(status: 401, body: Data(), model: "m"), .invalidKey)
        XCTAssertEqual(GeminiClient.mapError(status: 400, body: json("""
            {"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}
            """), model: "m"), .invalidKey)
        XCTAssertEqual(GeminiClient.mapError(status: 404, body: Data(), model: "gemini-x"), .modelUnavailable("gemini-x"))
        XCTAssertEqual(GeminiClient.mapError(status: 429, body: Data(), model: "m"), .rateLimited)
        XCTAssertEqual(GeminiClient.mapError(status: 503, body: Data(), model: "m"), .server(503))
    }

    func testRetriesWithoutThinkingWhenModelRejectsIt() async throws {
        StubURLProtocol.responses = [
            (400, json(#"{"error":{"code":400,"message":"Thinking level minimal is not supported for this model.","status":"INVALID_ARGUMENT"}}"#)),
            (200, json(#"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#)),
        ]

        let text = try await client.generate(
            model: "gemini-3.8-flash", apiKey: "k", systemPrompt: nil, parts: [.text("hi")],
            options: GeminiGenerationOptions(temperature: 0.7, thinkingLevel: "minimal"))

        XCTAssertEqual(text, "ok")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        let retryGen = StubURLProtocol.bodyJSON(of: StubURLProtocol.requests[1])["generationConfig"] as? [String: Any]
        XCTAssertNil(retryGen?["thinkingConfig"])
    }

    func testListModelsReturnsGenerateContentModelsWithoutPrefix() async throws {
        StubURLProtocol.responses = [(200, json("""
        {"models":[
          {"name":"models/gemini-3.8-flash","supportedGenerationMethods":["generateContent","countTokens"]},
          {"name":"models/text-embedding-005","supportedGenerationMethods":["embedContent"]}]}
        """))]

        let models = try await client.listModels(apiKey: "k")

        XCTAssertEqual(models, ["gemini-3.8-flash"])
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "x-goog-api-key"), "k")
        XCTAssertFalse(StubURLProtocol.requests.first?.url?.query?.contains("key=") ?? false)
    }

    func testCatalogMigrationKeepsKnownIDsAndReplacesRetiredOnes() {
        XCTAssertEqual(GeminiModelCatalog.migrate(id: "3.8-flash", fallback: "x"), "3.8-flash")
        XCTAssertEqual(GeminiModelCatalog.migrate(id: "3.1-pro", fallback: "3.8-flash"), "3.8-flash")
        XCTAssertEqual(GeminiModelCatalog.migrate(id: nil, fallback: "3.5-flash-lite"), "3.5-flash-lite")
        XCTAssertEqual(GeminiModelCatalog.thinkingLevel(forAPIName: "gemini-3.5-flash-lite"), "minimal")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail** — focused command with `<Suite>` = `GeminiClientTests`. Expected: compile errors (`GeminiClient` not found).

- [ ] **Step 3: Implement `GeminiClient.swift`**
```swift
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
```

- [ ] **Step 4: Rewrite `GeminiModelCatalog.swift`**
```swift
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
```
(`liveModels`/`supportsLive`/`supportsText` are removed; their only users are deleted in Task 5. If anything else fails to compile because of them, remove that reference.)

- [ ] **Step 5: Run focused tests** — `<Suite>` = `GeminiClientTests`. Expected: 5 tests pass. Then run the full suite (existing tests must still compile; `GeminiLiveTranscriptionService` does not reference the catalog).

- [ ] **Step 6: Commit** — `git add -A && git commit -m "Add REST GeminiClient and refresh model catalog"` (+ Co-Authored-By line).

---

### Task 2: Single paste path with clipboard snapshot  (model: sonnet)

**Files:**
- Modify: `HDText/Services/Insertion/TextInsertionService.swift` (full rewrite)
- Modify: `HDTextTests/TextInsertionServiceTests.swift` (full rewrite)

**Interfaces — Produces:**
```swift
struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot
    func write(to pasteboard: NSPasteboard)
}
final class TextInsertionService {
    init(pasteboard: NSPasteboard = .general)
    func paste(_ text: String, into app: NSRunningApplication?, completion: (() -> Void)? = nil)
    @discardableResult static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard, ifChangeCountIs expected: Int) -> Bool
    static func postCommandKey(_ virtualKey: CGKeyCode)   // 0x09 = V, 0x08 = C
    static func frontmostAppName() -> String
    static func checkAccessibilityPermission() -> Bool
    static func requestAccessibilityPermission()
}
```
`insertText(_:)` is removed (its AX `kAXValue` write replaced whole text fields). Its one caller (`HistoryDetailView`) is updated in Task 6; until then change that call to `appState.textInsertionService.paste(record.cleanedText, into: nil)` so the build stays green.

- [ ] **Step 1: Write failing tests** (`HDTextTests/TextInsertionServiceTests.swift`, replace whole file; uses a private named pasteboard, never `.general`):
```swift
import XCTest
import AppKit
@testable import HDText

final class TextInsertionServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private let customType = NSPasteboard.PasteboardType("com.hdtext.tests.custom")

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.hdtext.tests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testRestoreBringsBackAllOriginalTypes() {
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([9, 8, 7]), forType: customType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)

        XCTAssertTrue(TextInsertionService.restore(snapshot, to: pasteboard, ifChangeCountIs: pasteboard.changeCount))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: customType), Data([9, 8, 7]))
    }

    func testRestoreSkippedWhenUserCopiedSomethingNewer() {
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot.capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let ours = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("user copied", forType: .string)

        XCTAssertFalse(TextInsertionService.restore(snapshot, to: pasteboard, ifChangeCountIs: ours))
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied")
    }
}
```

- [ ] **Step 2: Run** `<Suite>` = `TextInsertionServiceTests`. Expected: compile failure (`PasteboardSnapshot` missing).

- [ ] **Step 3: Implement** (replace whole file):
```swift
import AppKit
import ApplicationServices

/// All items/types on a pasteboard, so a paste can put the user's clipboard back exactly.
struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict.isEmpty ? nil : dict
        }
        return PasteboardSnapshot(items: items)
    }

    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let objects: [NSPasteboardItem] = items.map { typeMap in
            let item = NSPasteboardItem()
            for (type, data) in typeMap { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(objects)
    }
}

final class TextInsertionService {
    private let pasteboard: NSPasteboard
    private let activationDelay: TimeInterval = 0.25
    private let restoreDelay: TimeInterval = 0.8

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Puts `text` on the clipboard, activates `app`, sends ⌘V, then restores the previous
    /// clipboard if nothing else has changed it in the meantime.
    func paste(_ text: String, into app: NSRunningApplication?, completion: (() -> Void)? = nil) {
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        if let app {
            app.activate()
            hdLog("Reactivated: \(app.localizedName ?? "?")")
        }

        let pasteboard = self.pasteboard
        let restoreDelay = self.restoreDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            Self.postCommandKey(0x09)
            hdLog("Pasted via Cmd+V")
            completion?()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                Self.restore(snapshot, to: pasteboard, ifChangeCountIs: ourChangeCount)
            }
        }
    }

    @discardableResult
    static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard, ifChangeCountIs expected: Int) -> Bool {
        guard pasteboard.changeCount == expected else {
            hdLog("Clipboard changed since paste — not restoring")
            return false
        }
        snapshot.write(to: pasteboard)
        return true
    }

    static func postCommandKey(_ virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    static func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
```
Then in `HDText/Features/History/HistoryDetailView.swift` change `_ = appState.textInsertionService.insertText(record.cleanedText)` to `appState.textInsertionService.paste(record.cleanedText, into: nil)`.

- [ ] **Step 4: Run** focused suite → 2 pass; then full suite.
- [ ] **Step 5: Commit** — "Unify paste path with full clipboard snapshot/restore".

---

### Task 3: Proper audio resampling  (model: sonnet)

**Files:**
- Modify: `HDText/Services/Audio/AudioCaptureEngine.swift`
- Create: `HDTextTests/PCM16ResamplerTests.swift`

**Interfaces — Produces:**
```swift
final class PCM16Resampler {
    init?(inputFormat: AVAudioFormat, targetSampleRate: Double = 16000)
    func convert(_ buffer: AVAudioPCMBuffer) -> Data?   // mono Int16 little-endian at target rate
}
```
`AudioCaptureEngine` public API is unchanged (`startCapture(deviceID:)`, `stopCapture() -> Data`, `onLevelUpdate`, `computeRMS`, `isSilence`).

- [ ] **Step 1: Failing test** (`HDTextTests/PCM16ResamplerTests.swift`):
```swift
import XCTest
import AVFoundation
@testable import HDText

final class PCM16ResamplerTests: XCTestCase {
    func testStereo48kBecomesMono16kWithSignal() throws {
        let input = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false))
        let resampler = try XCTUnwrap(PCM16Resampler(inputFormat: input))

        var total = Data()
        var phase = 0.0
        for _ in 0..<10 {   // 10 × 4800 frames = 1 s of 440 Hz tone
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4800))
            buffer.frameLength = 4800
            for i in 0..<4800 {
                let v = Float(sin(phase) * 0.5)
                buffer.floatChannelData![0][i] = v
                buffer.floatChannelData![1][i] = v
                phase += 2 * .pi * 440 / 48000
            }
            if let chunk = resampler.convert(buffer) { total.append(chunk) }   // converter may buffer the first chunk
        }

        let samples = total.count / 2
        XCTAssertEqual(Double(samples), 16000, accuracy: 400)
        XCTAssertGreaterThan(AudioCaptureEngine.computeRMS(of: total), 0.2)
    }
}
```
- [ ] **Step 2: Run** `<Suite>` = `PCM16ResamplerTests` → compile failure.
- [ ] **Step 3: Implement.** Add to `AudioCaptureEngine.swift` (below the class, above `AudioCaptureError`):
```swift
/// Streams capture buffers into 16 kHz mono Int16 PCM with proper anti-aliased resampling.
final class PCM16Resampler {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat, targetSampleRate: Double = 16000) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate,
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: output) else { return nil }
        converter.downmix = true
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0 else { return nil }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            hdLog("Resampler error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        guard out.frameLength > 0, let channel = out.int16ChannelData else { return nil }
        return Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }
}
```
In `startCapture`: after `hwFormat` is built and `guard hwRate > 0`, add
```swift
guard let resampler = PCM16Resampler(inputFormat: hwFormat) else {
    throw AudioCaptureError.tapInstallFailed("Could not create 16 kHz converter")
}
```
In the tap block replace `if let data = self.convertToInt16PCM(buffer: buffer) {` with `if let data = resampler.convert(buffer) {`. Delete the `convertToInt16PCM(buffer:)` method.
- [ ] **Step 4: Run** focused → pass; full suite.
- [ ] **Step 5: Commit** — "Resample mic audio with AVAudioConverter".

---

### Task 4: API key cache, Keychain test isolation, model migration  (model: sonnet)

**Files:**
- Modify: `HDText/Services/Security/KeychainStore.swift`, `HDText/App/AppState.swift`
- Modify: `HDTextTests/KeychainStoreTests.swift`, `HDTextTests/AppStateTests.swift`, `HDTextTests/HotkeyManagerTests.swift`

**Interfaces:**
- Consumes: `GeminiModelCatalog.migrate(id:fallback:)`, `defaultTranscriptionID`, `defaultTextID`, `apiName(forID:fallback:)` (Task 1).
- Produces:
```swift
final class KeychainStore { init(service: String = "com.hdtext.app") }   // existing save/retrieve/delete unchanged
@MainActor final class AppState {
    init(keychainStore: KeychainStore = KeychainStore())
    @Published private(set) var apiKey: String?
    var hasAPIKey: Bool                         // apiKey != nil
    @discardableResult func saveAPIKey(_ raw: String) -> Bool   // trims; false if empty or Keychain fails
    func removeAPIKey()
}
```
`AppState.geminiRewriteService` and `AppState.refineService` properties are removed (unused).

- [ ] **Step 1: Failing tests.**
`KeychainStoreTests.swift`: in `setUp` use `store = KeychainStore(service: "com.hdtext.app.tests")` (keep existing test bodies).
`AppStateTests.swift`: replace `testHasAPIKeyReturnsFalseWhenNoKey` with
```swift
func testAPIKeySaveTrimsAndCachesWithoutRealKeychainItem() {
    let store = KeychainStore(service: "com.hdtext.app.tests")
    store.deleteAPIKey()
    let state = AppState(keychainStore: store)
    XCTAssertFalse(state.hasAPIKey)

    XCTAssertTrue(state.saveAPIKey("  AQ.Ab-test-key \n"))
    XCTAssertEqual(state.apiKey, "AQ.Ab-test-key")
    XCTAssertEqual(store.retrieveAPIKey(), "AQ.Ab-test-key")

    state.removeAPIKey()
    XCTAssertNil(state.apiKey)
    XCTAssertNil(store.retrieveAPIKey())
}
```
and make every other `AppState()` in that file `AppState(keychainStore: KeychainStore(service: "com.hdtext.app.tests"))`.
`HotkeyManagerTests.swift`: the current setUp/tearDown delete the user's real `hotkeyModifiers`/`hotkeyKeyCode` prefs. Save them in `setUp` (`savedMods = UserDefaults.standard.object(forKey: "hotkeyModifiers")`, same for key code) before removing, and in `tearDown` write them back (`set` if non-nil, else `removeObject`).
- [ ] **Step 2: Run** `<Suite>` = `AppStateTests` → compile failure.
- [ ] **Step 3: Implement.**
KeychainStore:
```swift
private let serviceName: String
private let apiKeyAccount = "gemini-api-key"

init(service: String = "com.hdtext.app") {
    self.serviceName = service
}
```
AppState:
- Add `@Published private(set) var apiKey: String?`.
- `init(keychainStore: KeychainStore = KeychainStore())`; assign `self.keychainStore = keychainStore` and, after all stored properties are set, `self.apiKey = keychainStore.retrieveAPIKey()` (the only Keychain read per launch).
- Model ids:
```swift
self.selectedTranscriptionModelID = GeminiModelCatalog.migrate(
    id: UserDefaults.standard.string(forKey: "selectedTranscriptionModelID"),
    fallback: GeminiModelCatalog.defaultTranscriptionID)
self.selectedRewriteModelID = GeminiModelCatalog.migrate(
    id: UserDefaults.standard.string(forKey: "selectedRewriteModelID"),
    fallback: GeminiModelCatalog.defaultTextID)
```
  and at the end of `init` persist both (`UserDefaults.standard.set(selectedTranscriptionModelID, forKey: "selectedTranscriptionModelID")`, same for rewrite) because `didSet` does not run in `init`.
- Fallbacks in `transcriptionModelAPIName` / `rewriteModelAPIName`: `GeminiModelCatalog.apiName(forID: selectedTranscriptionModelID, fallback: GeminiModelCatalog.apiName(forID: GeminiModelCatalog.defaultTranscriptionID, fallback: "gemini-3.5-flash-lite"))` and the text equivalent with `defaultTextID` / `"gemini-3.8-flash"`.
- Replace `hasAPIKey` with `var hasAPIKey: Bool { apiKey != nil }`.
- Add:
```swift
@discardableResult
func saveAPIKey(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, keychainStore.saveAPIKey(trimmed) else { return false }
    apiKey = trimmed
    return true
}

func removeAPIKey() {
    keychainStore.deleteAPIKey()
    apiKey = nil
}
```
- Remove `geminiRewriteService` and `refineService` properties + their init lines.
- [ ] **Step 4: Run** `AppStateTests`, `KeychainStoreTests`, `HotkeyManagerTests` → pass; full suite.
- [ ] **Step 5: Commit** — "Cache API key in memory; isolate Keychain/defaults in tests; migrate retired model ids".

---

### Task 5: Services on GeminiClient; remove obsolete SDK and dead code  (model: sonnet)

**Files:**
- Modify: `HDText/Services/Gemini/GeminiTranscriptionService.swift`, `HDText/Features/Refine/RefineService.swift`, `project.yml`, `HDTextTests/GeminiTranscriptionServiceTests.swift`
- Delete: `HDText/Services/Gemini/GeminiLiveTranscriptionService.swift`, `HDText/Services/Gemini/GeminiRewriteService.swift`, `HDText/Views/TranscriptionOverlayView.swift`, `HDTextTests/GeminiLiveServiceTests.swift`, `HDTextTests/GeminiRewriteServiceTests.swift`

**Interfaces:**
- Consumes: `GeminiClient`, `GeminiPart`, `GeminiGenerationOptions`, `GeminiAPIError`, `GeminiModelCatalog.thinkingLevel(forAPIName:)` (Task 1); `StubURLProtocol` (Task 1 tests).
- Produces:
```swift
final class GeminiTranscriptionService {
    init(client: GeminiClient = GeminiClient())
    func buildSystemPrompt(aggressiveness: RewriteAggressiveness, smartCorrection: Bool) -> String   // unchanged text
    func transcribeAndClean(audioData: Data, aggressiveness: RewriteAggressiveness = .balanced, smartCorrection: Bool = true, modelName: String, apiKey: String) async throws -> String
    func transcribe(audioData: Data, modelName: String, apiKey: String) async throws -> String
}
final class RefineService {
    init(client: GeminiClient = GeminiClient())
    func refine(text: String, action: RefineAction, modelName: String, apiKey: String) async throws -> String
}
```
Call sites already pass `modelName:` explicitly; if any call relied on the removed default, pass `appState.transcriptionModelAPIName`.

- [ ] **Step 1: Failing test** — add to `GeminiTranscriptionServiceTests.swift`; also update the existing `testEmptyAudioThrows` call to pass `modelName: "gemini-3.5-flash-lite"`:
```swift
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
```
- [ ] **Step 2: Run** `<Suite>` = `GeminiTranscriptionServiceTests` → compile failure.
- [ ] **Step 3: Implement.**
`GeminiTranscriptionService`: remove `import GoogleGenerativeAI`, `cachedModel`, `cachedModelKey`. Add `private let client: GeminiClient` + `init(client: GeminiClient = GeminiClient())`. In `transcribeAndClean` replace the model-construction + `generateContent` block with:
```swift
let text: String
do {
    text = try await client.generate(
        model: modelName,
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        parts: [.inlineData(mimeType: "audio/wav", data: wavData), .text("Transcribe.")],
        options: GeminiGenerationOptions(
            temperature: 0.2,
            thinkingLevel: GeminiModelCatalog.thinkingLevel(forAPIName: modelName)))
} catch GeminiAPIError.emptyResponse {
    throw TranscriptionError.noSpeechDetected
}
```
then keep the existing `[NO_SPEECH]` / phantom-phrase checks operating on `text` (drop the old `response.text` guard). Remove the `modelName` default values in both `transcribeAndClean` and `transcribe`.
`RefineService`: remove `import GoogleGenerativeAI`; add `private let client: GeminiClient` + `init(client: GeminiClient = GeminiClient())`; body after the empty-input guard:
```swift
return try await client.generate(
    model: modelName,
    apiKey: apiKey,
    systemPrompt: action.systemPrompt,
    parts: [.text(trimmed)],
    options: GeminiGenerationOptions(
        temperature: 0.7,
        thinkingLevel: GeminiModelCatalog.thinkingLevel(forAPIName: modelName)))
```
(`RefineError.emptyResponse` stays; it is now unused by RefineService but harmless — delete the case only if nothing references it.)
Delete the five files listed above (`git rm`).
`project.yml`: delete the whole `packages:` block and the `- package: GoogleGenerativeAI` dependency line under `HDText.dependencies` (remove `dependencies:` key if it becomes empty).
`grep -rn "GoogleGenerativeAI\|GenerativeModel\|ModelContent" HDText HDTextTests` must return nothing.
- [ ] **Step 4: Run** focused → pass; full suite.
- [ ] **Step 5: Commit** — "Move services to GeminiClient; drop archived generative-ai-swift and dead code".

---

### Task 6: Settings, menu bar, calibration, history UI  (model: sonnet)

**Files:**
- Create: `HDText/Views/APIKeyTestButton.swift`, `HDText/Services/Util/AccessibilityPermission.swift`
- Modify: `HDText/Views/SettingsView.swift`, `HDText/App/MenuBarController.swift`, `HDText/Features/Calibration/CalibrationView.swift`, `HDText/Features/History/HistoryDetailView.swift`

**Interfaces:**
- Consumes: `AppState.apiKey/saveAPIKey/removeAPIKey/hasAPIKey/transcriptionModelAPIName/rewriteModelAPIName` (Task 4), `GeminiClient.listModels` (Task 1), `TextInsertionService.paste(_:into:)` (Task 2), existing `AppDelegate.menuRetryHotkey()`.
- Produces:
```swift
struct APIKeyTestButton: View { init(keyProvider: @escaping () -> String) }   // needs @EnvironmentObject AppState
enum AccessibilityPermission { static func resetAndRegrant() }
```

- [ ] **Step 1: Create `AccessibilityPermission.swift`**
```swift
import AppKit

enum AccessibilityPermission {
    /// A rebuilt (ad-hoc signed) app keeps its row in System Settings but loses the grant.
    /// Clearing the stale entry lets macOS prompt again.
    static func resetAndRegrant() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hdtext.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            hdLog("tccutil reset Accessibility \(bundleID) → \(process.terminationStatus)")
        } catch {
            hdLog("tccutil failed: \(error.localizedDescription)")
        }
        (NSApp.delegate as? AppDelegate)?.menuRetryHotkey()
    }
}
```
- [ ] **Step 2: Create `APIKeyTestButton.swift`**
```swift
import SwiftUI

struct APIKeyTestButton: View {
    @EnvironmentObject var appState: AppState
    let keyProvider: () -> String

    @State private var state: TestState = .idle

    enum TestState: Equatable {
        case idle, testing
        case ok(String), warning(String), failed(String)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("Test Key") { runTest() }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(state == .testing || keyProvider().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            switch state {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
            case .ok(let message):
                Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .warning(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func runTest() {
        let key = keyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        state = .testing
        let needed = [appState.transcriptionModelAPIName, appState.rewriteModelAPIName]
        Task { @MainActor in
            do {
                let available = try await GeminiClient().listModels(apiKey: key)
                let missing = needed.filter { !available.contains($0) }
                state = missing.isEmpty
                    ? .ok("Key works")
                    : .warning("Key works, but unavailable: \(missing.joined(separator: ", "))")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
```
- [ ] **Step 3: SettingsView edits**
  - `onAppear`: replace the Keychain read with `apiKeyInput = appState.apiKey ?? ""`.
  - Save button action: `if appState.saveAPIKey(apiKeyInput) { apiKeyInput = appState.apiKey ?? ""; apiKeySaveStatus = .saved } else { apiKeySaveStatus = .failed }; clearStatusAfterDelay()` (remove `objectWillChange.send()`).
  - Remove button action: `appState.removeAPIKey(); apiKeyInput = ""; apiKeySaveStatus = .removed; clearStatusAfterDelay()`.
  - In the API Key GroupBox, below the Save/Remove row add `APIKeyTestButton(keyProvider: { apiKeyInput })`, and below the Keychain note add `Text("Keys from Google AI Studio work in either format (AQ.… or AIza…).").font(.caption).foregroundStyle(.secondary)`.
  - Models info text → `"Flash-Lite is fastest and cheapest. Flash is a good balance. 4 Argon is highest quality but slower."`
  - General › Shortcut GroupBox: after the Activate button row add, shown only when `!AXIsProcessTrusted()`:
    ```swift
    VStack(alignment: .leading, spacing: 4) {
        Text("Accessibility isn't granted. After installing a new build, macOS may still list HDText as enabled while the grant is stale.")
            .font(.caption).foregroundStyle(.secondary)
        Button("Reset & Re-grant Accessibility") { AccessibilityPermission.resetAndRegrant() }
            .controlSize(.small)
    }
    ```
- [ ] **Step 4: MenuBarController edits**
  - Conform: `final class MenuBarController: NSObject, NSMenuDelegate`.
  - Delete `refreshTimer` and its creation in `init`.
  - `setupStatusItem`: create one `let menu = NSMenu(); menu.delegate = self; statusItem?.menu = menu; populate(menu)`.
  - Rename `rebuildMenu()` body into `private func populate(_ menu: NSMenu)` which starts with `menu.removeAllItems()` and adds items to the passed menu (drop the final `self.statusItem?.menu = menu`). Keep a `private func rebuildMenu() { if let menu = statusItem?.menu { populate(menu) } }` used by `observeState`.
  - Add `func menuNeedsUpdate(_ menu: NSMenu) { populate(menu) }`.
  - Accessibility item when not granted: title `"Accessibility: NOT GRANTED — click to reset & re-grant"`, action `#selector(resetAccessibility)`, target `self`; add `@objc private func resetAccessibility() { AccessibilityPermission.resetAndRegrant() }`; delete `openAccessibilitySettings`.
- [ ] **Step 5: Calibration + History**
  - `CalibrationView.swift`: `let apiKey = appState.keychainStore.retrieveAPIKey()` → `let apiKey = appState.apiKey`.
  - `HistoryDetailView.swift` Re-insert button:
    ```swift
    Button("Re-insert") {
        let target = NSWorkspace.shared.runningApplications.first {
            $0.localizedName == record.targetApp && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        appState.textInsertionService.paste(record.cleanedText, into: target)
    }
    .disabled(!NSWorkspace.shared.runningApplications.contains { $0.localizedName == record.targetApp })
    ```
- [ ] **Step 6: Verify** — `grep -rn "retrieveAPIKey()" HDText | grep -v Security/ | grep -v AppState.swift` → only AppDelegate lines remain (Task 7 handles them). Full suite green (no new tests: UI only).
- [ ] **Step 7: Commit** — "Settings Test Key, Accessibility reset, menu rebuilt on open, cached key in UI".

---

### Task 7: Dictation flow + onboarding fixes  (model: opus)

**Files:**
- Modify: `HDText/App/AppDelegate.swift`, `HDText/Features/Onboarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `AppState.apiKey/saveAPIKey/hasAPIKey` (T4), `TextInsertionService.paste(_:into:completion:)`, `PasteboardSnapshot`, `TextInsertionService.restore(_:to:ifChangeCountIs:)`, `TextInsertionService.postCommandKey(_:)` (T2), `APIKeyTestButton(keyProvider:)`, `AccessibilityPermission.resetAndRegrant()` (T6).
- Produces: `OnboardingView(onFinish: @escaping () -> Void)`; `AppDelegate.completeOnboarding()` (replaces `onOnboardingComplete()`).

- [ ] **Step 1: Key cache call sites (AppDelegate)** — the three `appState.keychainStore.retrieveAPIKey()` uses (Services `refineText`, `handleRefineMenuAction`, `finalizeDictation`) become `appState.apiKey`.
- [ ] **Step 2: Hotkey callbacks off the event-tap callback** — in `setupDictationPipeline`:
```swift
appState.hotkeyManager.onHoldStarted = {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .hdtextDictationStart, object: nil)
    }
}
appState.hotkeyManager.onHoldEnded = {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .hdtextDictationEnd, object: nil)
    }
}
```
- [ ] **Step 3: Paste through TextInsertionService** — in `finalizeDictation` success path, replace the `if let app = self.sourceApp { app.activate() ... }` block and the whole `DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ... }` paste block with:
```swift
appState.textInsertionService.paste(cleaned, into: self.sourceApp) { [weak self] in
    self?.playSound("Glass")
}
```
- [ ] **Step 4: Selection-copy fallback uses the snapshot** — rewrite `attemptSelectedTextViaClipboard`:
```swift
private func attemptSelectedTextViaClipboard(completion: @escaping (String?) -> Void) {
    let pasteboard = NSPasteboard.general
    let snapshot = PasteboardSnapshot.capture(pasteboard)
    let originalChangeCount = pasteboard.changeCount

    TextInsertionService.postCommandKey(0x08)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        guard pasteboard.changeCount != originalChangeCount else {
            hdLog("Clipboard fallback: changeCount unchanged — no selection copied")
            completion(nil)
            return
        }
        let copied = pasteboard.string(forType: .string)
        let copiedChangeCount = pasteboard.changeCount
        TextInsertionService.restore(snapshot, to: pasteboard, ifChangeCountIs: copiedChangeCount)
        completion(copied)
    }
}
```
- [ ] **Step 5: Lock-mode activation tap** — add `private var lockActivationReleasePending = false` next to the other double-tap state. In `handleDictationStart`, where lock mode is turned on, set `lockActivationReleasePending = true`. At the top of the `if appState.isLockMode {` branch in `handleDictationEnd` add:
```swift
if lockActivationReleasePending {
    lockActivationReleasePending = false
    return
}
```
Replace the exit-tap timestamp clearing with:
```swift
let stamp = Date()
lockExitTapTime = stamp
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    if self?.lockExitTapTime == stamp { self?.lockExitTapTime = nil }
}
```
Also set `lockActivationReleasePending = false` in `menuCancelDictation` and wherever `isLockMode` is set to `false`.
- [ ] **Step 6: Onboarding wiring (AppDelegate)** — `showOnboardingWindow` builds `OnboardingView(onFinish: { [weak self] in self?.completeOnboarding() }).environmentObject(appState)`. Replace `onOnboardingComplete()` with:
```swift
func completeOnboarding() {
    appState.isOnboardingComplete = true
    onboardingWindow?.close()
    onboardingWindow = nil
    ensureAccessibilityThenStart()
}
```
- [ ] **Step 7: OnboardingView**
  - Add `let onFinish: () -> Void`; delete `@Environment(\.dismiss)`.
  - Replace the `TabView(selection:) { ... }.tabViewStyle(.automatic)` with:
    ```swift
    Group {
        switch currentStep {
        case 0: welcomeStep
        case 1: permissionsStep
        case 2: apiKeyStep
        default: readyStep
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    ```
  - `.onAppear`: also `apiKeyInput = appState.apiKey ?? ""`.
  - API key step Save: `appState.saveAPIKey(apiKeyInput)` (no `objectWillChange`); disable condition uses `.whitespacesAndNewlines`; add `APIKeyTestButton(keyProvider: { apiKeyInput })` under the Save button; link text `"Get a Gemini API key (Google AI Studio)"`.
  - Permissions step: when `!axGranted`, add `Button("Reset & Re-grant") { AccessibilityPermission.resetAndRegrant() }.buttonStyle(.bordered)` beside "Open Accessibility Settings", and caption `"Reinstalled HDText? Use Reset & Re-grant if it already looks enabled in System Settings."`.
  - "Get Started": `onFinish()`; disable it when `!appState.hasAPIKey`.
- [ ] **Step 8: Verify** — `grep -n "retrieveAPIKey\|onOnboardingComplete\|dismiss()" HDText/App/AppDelegate.swift HDText/Features/Onboarding/OnboardingView.swift` → nothing. Full suite green. Then launch the Debug build once (`open <dd-revive>/Build/Products/Debug/HDText.app`), confirm it starts (menu bar icon, no crash in `log show --last 1m --predicate 'subsystem == "com.hdtext.app"'`), then quit it (`osascript -e 'quit app "HDText"'`). Do not interact with other apps.
- [ ] **Step 9: Commit** — "Fix dictation paste/clipboard, lock-mode tap, hotkey tap latency, onboarding flow".

---

### Task 8: Refine window fixes  (model: sonnet)

**Files:** Modify `HDText/Features/Refine/RefinePreviewController.swift`, `HDText/Features/Refine/RefinePreviewView.swift`

**Interfaces:**
- Consumes: `RefineService()` (T5), `TextInsertionService.paste(_:into:)` (T2), `GeminiModelCatalog.model(forAPIName:)`, `defaultTextID` (T1).
- Produces: `RefinePreviewViewModel.generate()` (no parameter); `RefinePreviewController.showPreview(...)` signature unchanged.

- [ ] **Step 1: Controller**
  - Add `private let inserter = TextInsertionService()`; remove `private let refineService`.
  - First line of `showPreview`: `dismissWindow()` (closes any previous refine window).
  - modelID lookup: `GeminiModelCatalog.model(forAPIName: modelName)?.id ?? GeminiModelCatalog.defaultTextID`.
  - `onReplace`: `self?.dismissWindow(); self?.inserter.paste(finalText, into: sourceApp)`; delete `replaceInSourceApp`.
  - Initial generation: `Task { await viewModel.generate() }`.
- [ ] **Step 2: ViewModel** (in the controller file)
  - Add `private let service = RefineService()` and `private var generation = 0`.
  - `selectedModelAPIName` fallback → `GeminiModelCatalog.apiName(forID: GeminiModelCatalog.defaultTextID, fallback: "gemini-3.8-flash")`.
  - Replace `generate(service:)` with:
```swift
func generate() async {
    generation += 1
    let current = generation
    isLoading = true
    errorMessage = nil
    do {
        let result = try await service.refine(text: inputText, action: action,
                                              modelName: selectedModelAPIName, apiKey: apiKey)
        guard current == generation else { return }
        refinedText = result
    } catch {
        guard current == generation else { return }
        errorMessage = error.localizedDescription
        refinedText = inputText
    }
    isLoading = false
}
```
- [ ] **Step 3: View**
  - Remove `private let refineService = RefineService()`; Generate button → `Task { await viewModel.generate() }` and drop its `.disabled(viewModel.isLoading)`.
  - On the root `VStack` add:
```swift
.onChange(of: viewModel.action) { _, _ in Task { await viewModel.generate() } }
.onChange(of: viewModel.selectedModelID) { _, _ in Task { await viewModel.generate() } }
```
- [ ] **Step 4: Verify** — full suite green; `grep -rn "generate(service" HDText` → nothing.
- [ ] **Step 5: Commit** — "Refine window: single window, auto-regenerate, clipboard-safe replace".

---

### Task 9: Docs, version, release build  (model: haiku)

**Files:** Modify `README.md`, `project.yml`, `scripts/build-dmg.sh`

- [ ] **Step 1: `project.yml`** — `MARKETING_VERSION: "1.1.0"`, `CURRENT_PROJECT_VERSION: "2"`.
- [ ] **Step 2: `scripts/build-dmg.sh`** — after the `mkdir -p "$BUILD_DIR"` line add:
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
echo "==> Generating Xcode project..."
(cd "$PROJECT_DIR" && xcodegen generate)
```
and change `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \` to `xcodebuild \`.
- [ ] **Step 3: README** —
  - "Building from Source": `brew install xcodegen`, `cd hdtext`, `xcodegen generate`, `open HDText.xcodeproj` (replace the wrong `cd willow-voice-macos`). Note: if `xcode-select` points at Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
  - Features: "Configurable Gemini model selection (Flash-Lite, Flash, 4 Argon)"; remove the "(draggable, position saved)" claim from the indicator bullet → "Compact indicator that follows the cursor".
  - Requirements: "A Gemini API key from Google AI Studio (new `AQ.` auth keys and older `AIza` keys both work)".
  - Add a short "Troubleshooting" section: (1) hotkey stops working after installing a new build → menu bar › "Accessibility: NOT GRANTED — click to reset & re-grant"; (2) "Model … isn't available" → Settings › Models; (3) Settings › API Key › Test Key.
  - Project Structure: Gemini line → "REST client, transcription, model catalog".
- [ ] **Step 4: Release build check** — `./scripts/build-dmg.sh` must end with `==> Done! DMG at: .../build/HDText.dmg`. (`build/` is gitignored.)
- [ ] **Step 5: Commit** — "Docs and version 1.1.0".

---

## Final wave (controller)
- Full test suite once.
- Whole-branch review (opus) against the spec; fix Critical/Important only, minor list once.
- Optional live smoke test only if the user provides a key: run the Debug app, Settings › API Key › Test Key.
