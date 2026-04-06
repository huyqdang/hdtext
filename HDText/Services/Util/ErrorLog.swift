import Foundation

@MainActor
final class ErrorLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
        let detail: String?

        enum Level: String {
            case error = "ERROR"
            case warning = "WARN"
            case info = "INFO"
        }

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: timestamp)
        }
    }

    @Published var entries: [Entry] = []

    func log(_ message: String, detail: String? = nil, level: Entry.Level = .error) {
        let entry = Entry(timestamp: Date(), level: level, message: message, detail: detail)
        entries.insert(entry, at: 0)
        if entries.count > 100 { entries.removeLast() }
        hdLog("[\(level.rawValue)] \(message)\(detail.map { " — \($0)" } ?? "")")
    }

    func clear() {
        entries.removeAll()
    }
}
