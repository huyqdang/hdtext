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
