import Foundation

struct TranscriptionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let roughTranscript: String
    let cleanedText: String
    let targetApp: String
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        roughTranscript: String,
        cleanedText: String,
        targetApp: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.roughTranscript = roughTranscript
        self.cleanedText = cleanedText
        self.targetApp = targetApp
        self.isFavorite = isFavorite
    }
}
