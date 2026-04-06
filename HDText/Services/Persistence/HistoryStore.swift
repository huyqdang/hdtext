import Foundation

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("HDText", isDirectory: true)

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent("history.json")
        loadRecords()
    }

    func save(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        persistRecords()
    }

    func delete(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }
        persistRecords()
    }

    func deleteAll() {
        records.removeAll()
        persistRecords()
    }

    func toggleFavorite(_ record: TranscriptionRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].isFavorite.toggle()
        persistRecords()
    }

    func search(query: String) -> [TranscriptionRecord] {
        guard !query.isEmpty else { return records }
        let lowered = query.lowercased()
        return records.filter {
            $0.cleanedText.lowercased().contains(lowered) ||
            $0.roughTranscript.lowercased().contains(lowered) ||
            $0.targetApp.lowercased().contains(lowered)
        }
    }

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(records)
    }

    private func loadRecords() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        guard let data = try? Data(contentsOf: storageURL) else { return }
        records = (try? JSONDecoder().decode([TranscriptionRecord].self, from: data)) ?? []
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
