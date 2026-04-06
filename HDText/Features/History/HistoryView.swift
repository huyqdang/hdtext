import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedRecord: TranscriptionRecord?
    @State private var showDeleteConfirmation = false

    private var filteredRecords: [TranscriptionRecord] {
        appState.historyStore.search(query: searchText)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let record = selectedRecord {
                HistoryDetailView(record: record)
                    .environmentObject(appState)
            } else {
                ContentUnavailableView(
                    "Select a Transcription",
                    systemImage: "text.bubble",
                    description: Text("Choose a transcription from the sidebar to view details.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search transcriptions")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(appState.historyStore.records.isEmpty)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    exportHistory()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(appState.historyStore.records.isEmpty)
            }
        }
        .alert("Clear All History?", isPresented: $showDeleteConfirmation) {
            Button("Delete All", role: .destructive) {
                appState.historyStore.deleteAll()
                selectedRecord = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all transcription history.")
        }
    }

    private var sidebar: some View {
        List(filteredRecords, selection: $selectedRecord) { record in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.cleanedText)
                        .lineLimit(2)
                        .font(.body)

                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }

                HStack {
                    Text(record.targetApp)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)

                    Spacer()

                    Text(relativeTime(record.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .tag(record)
            .contextMenu {
                Button("Copy Cleaned Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.cleanedText, forType: .string)
                }
                Button(record.isFavorite ? "Unfavorite" : "Favorite") {
                    appState.historyStore.toggleFavorite(record)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    appState.historyStore.delete(record)
                    if selectedRecord?.id == record.id {
                        selectedRecord = nil
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func exportHistory() {
        guard let data = appState.historyStore.exportJSON() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "hdtext-history.json"

        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}
