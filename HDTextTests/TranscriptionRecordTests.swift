import XCTest
@testable import HDText

final class TranscriptionRecordTests: XCTestCase {
    func testRecordCreation() {
        let record = TranscriptionRecord(
            roughTranscript: "um like hello world",
            cleanedText: "Hello world.",
            targetApp: "Notes"
        )

        XCTAssertFalse(record.id.uuidString.isEmpty)
        XCTAssertEqual(record.roughTranscript, "um like hello world")
        XCTAssertEqual(record.cleanedText, "Hello world.")
        XCTAssertEqual(record.targetApp, "Notes")
        XCTAssertFalse(record.isFavorite)
    }

    func testRecordCodable() throws {
        let record = TranscriptionRecord(
            roughTranscript: "test rough",
            cleanedText: "Test cleaned.",
            targetApp: "Slack"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TranscriptionRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.roughTranscript, record.roughTranscript)
        XCTAssertEqual(decoded.cleanedText, record.cleanedText)
        XCTAssertEqual(decoded.targetApp, record.targetApp)
    }
}
