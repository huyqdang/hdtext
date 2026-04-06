import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isRecording: Bool
    let onShortcutRecorded: (NSEvent.ModifierFlags, UInt16) -> Void

    @State private var localMonitor: Any?
    @State private var displayedShortcut: String = ""

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 6) {
                if isRecording {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    Text("Press keys...")
                        .foregroundStyle(.red)
                } else {
                    Text(displayedShortcut)
                        .fontDesign(.monospaced)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isRecording ? Color.red.opacity(0.12) : Color.secondary.opacity(0.12))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isRecording ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            displayedShortcut = appState.hotkeyManager.shortcutDescription
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        appState.hotkeyManager.pauseTap()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])

            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            guard !mods.isEmpty else { return nil }

            onShortcutRecorded(mods, event.keyCode)
            DispatchQueue.main.async {
                displayedShortcut = appState.hotkeyManager.shortcutDescription
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        isRecording = false
        appState.hotkeyManager.resumeTap()
    }
}
