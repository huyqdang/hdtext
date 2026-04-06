import AppKit
import SwiftUI
import Combine

@MainActor
final class RefinePreviewController {
    private var window: NSWindow?
    private let refineService = RefineService()

    func showPreview(
        originalText: String,
        action: RefineAction,
        modelName: String,
        apiKey: String,
        sourceApp: NSRunningApplication?
    ) {
        let viewModel = RefinePreviewViewModel(
            originalText: originalText,
            action: action,
            modelID: GeminiModelCatalog.allModels.first(where: { $0.apiModelName == modelName })?.id
                ?? GeminiModelCatalog.defaultTextID,
            apiKey: apiKey
        )

        viewModel.onReplace = { [weak self] finalText in
            self?.replaceInSourceApp(finalText, sourceApp: sourceApp)
            self?.dismissWindow()
        }

        viewModel.onCopy = { [weak self] finalText in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(finalText, forType: .string)
            self?.dismissWindow()
        }

        viewModel.onCancel = { [weak self] in
            self?.dismissWindow()
        }

        let view = RefinePreviewView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "HD Text — Refine"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 480, height: 380)
        w.level = .floating

        self.window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task {
            await viewModel.generate(service: refineService)
        }
    }

    private func replaceInSourceApp(_ text: String, sourceApp: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if let app = sourceApp {
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func dismissWindow() {
        window?.close()
        window = nil
    }
}

@MainActor
final class RefinePreviewViewModel: ObservableObject {
    let apiKey: String

    @Published var inputText: String
    @Published var action: RefineAction
    @Published var selectedModelID: String
    @Published var refinedText: String = ""
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?

    var onReplace: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onCancel: (() -> Void)?

    var selectedModelAPIName: String {
        GeminiModelCatalog.apiName(forID: selectedModelID, fallback: "gemini-2.5-flash")
    }

    init(originalText: String, action: RefineAction, modelID: String, apiKey: String) {
        self.inputText = originalText
        self.action = action
        self.selectedModelID = modelID
        self.apiKey = apiKey
    }

    func generate(service: RefineService) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await service.refine(
                text: inputText,
                action: action,
                modelName: selectedModelAPIName,
                apiKey: apiKey
            )
            refinedText = result
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            refinedText = inputText
            isLoading = false
        }
    }
}
