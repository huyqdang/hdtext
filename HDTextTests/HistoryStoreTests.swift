import XCTest
@testable import HDText

final class HistoryStoreTests: XCTestCase {
    private var store: HistoryStore!

    override func setUp() {
        super.setUp()
        store = HistoryStore()
        store.deleteAll()
    }

    override func tearDown() {
        store.deleteAll()
        store = nil
        super.tearDown()
    }

    func testSaveAndRetrieveRecord() {
        let record = TranscriptionRecord(
            roughTranscript: "um so like hello world",
            cleanedText: "Hello world.",
            targetApp: "Notes"
        )
        store.save(record)

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.cleanedText, "Hello world.")
        XCTAssertEqual(store.records.first?.roughTranscript, "um so like hello world")
    }

    func testNewRecordsInsertedAtTop() {
        let first = TranscriptionRecord(roughTranscript: "first", cleanedText: "First.", targetApp: "Notes")
        let second = TranscriptionRecord(roughTranscript: "second", cleanedText: "Second.", targetApp: "Slack")

        store.save(first)
        store.save(second)

        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.records[0].cleanedText, "Second.")
        XCTAssertEqual(store.records[1].cleanedText, "First.")
    }

    func testDeleteRecord() {
        let record = TranscriptionRecord(roughTranscript: "test", cleanedText: "Test.", targetApp: "Notes")
        store.save(record)

        store.delete(record)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testDeleteAll() {
        store.save(TranscriptionRecord(roughTranscript: "a", cleanedText: "A", targetApp: "Notes"))
        store.save(TranscriptionRecord(roughTranscript: "b", cleanedText: "B", targetApp: "Notes"))

        store.deleteAll()
        XCTAssertTrue(store.records.isEmpty)
    }

    func testToggleFavorite() {
        let record = TranscriptionRecord(roughTranscript: "test", cleanedText: "Test.", targetApp: "Notes")
        store.save(record)

        XCTAssertFalse(store.records[0].isFavorite)

        store.toggleFavorite(store.records[0])
        XCTAssertTrue(store.records[0].isFavorite)

        store.toggleFavorite(store.records[0])
        XCTAssertFalse(store.records[0].isFavorite)
    }

    func testSearchByCleanedText() {
        store.save(TranscriptionRecord(roughTranscript: "a", cleanedText: "Hello world", targetApp: "Notes"))
        store.save(TranscriptionRecord(roughTranscript: "b", cleanedText: "Goodbye moon", targetApp: "Slack"))

        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.cleanedText, "Hello world")
    }

    func testSearchByTargetApp() {
        store.save(TranscriptionRecord(roughTranscript: "a", cleanedText: "Text A", targetApp: "Notes"))
        store.save(TranscriptionRecord(roughTranscript: "b", cleanedText: "Text B", targetApp: "Slack"))

        let results = store.search(query: "slack")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.targetApp, "Slack")
    }

    func testEmptySearchReturnsAll() {
        store.save(TranscriptionRecord(roughTranscript: "a", cleanedText: "A", targetApp: "Notes"))
        store.save(TranscriptionRecord(roughTranscript: "b", cleanedText: "B", targetApp: "Slack"))

        let results = store.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testExportJSON() {
        store.save(TranscriptionRecord(roughTranscript: "test", cleanedText: "Test.", targetApp: "Notes"))

        guard let data = store.exportJSON() else {
            XCTFail("Export returned nil")
            return
        }

        let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?.cleanedText, "Test.")
    }
}
