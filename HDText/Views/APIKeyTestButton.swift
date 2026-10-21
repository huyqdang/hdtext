import SwiftUI

struct APIKeyTestButton: View {
    @EnvironmentObject var appState: AppState
    let keyProvider: () -> String

    @State private var state: TestState = .idle

    init(keyProvider: @escaping () -> String) {
        self.keyProvider = keyProvider
    }

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
        .onChange(of: keyProvider()) { state = .idle }
    }

    private func runTest() {
        let key = keyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        state = .testing
        let needed = [appState.transcriptionModelAPIName, appState.rewriteModelAPIName]
        Task { @MainActor in
            let result: TestState
            do {
                let available = try await GeminiClient().listModels(apiKey: key)
                let missing = needed.filter { !available.contains($0) }
                result = missing.isEmpty
                    ? .ok("Key works")
                    : .warning("Key works, but unavailable: \(missing.joined(separator: ", "))")
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard keyProvider().trimmingCharacters(in: .whitespacesAndNewlines) == key else { return }
            state = result
        }
    }
}
