import SwiftUI

struct HistoryDetailView: View {
    let record: TranscriptionRecord
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Cleaned Text", systemImage: "checkmark.circle")
                            .font(.headline)

                        Text(record.cleanedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.06))
                            .cornerRadius(8)

                        HStack {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.cleanedText, forType: .string)
                            }
                            Button("Re-insert") {
                                appState.textInsertionService.paste(record.cleanedText, into: nil)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Rough Transcript", systemImage: "waveform")
                            .font(.headline)

                        Text(record.roughTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(8)

                        Button("Copy Rough") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.roughTranscript, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.timestamp, format: .dateTime)
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    appState.historyStore.toggleFavorite(record)
                } label: {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(record.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
            }

            Text("Inserted into \(record.targetApp)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
