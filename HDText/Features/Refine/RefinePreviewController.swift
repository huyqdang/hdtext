import AppKit
import SwiftUI
import Combine

@MainActor
final class RefinePreviewController {
    private var window: NSWindow?
    private let inserter = TextInsertionService()

    func showPreview(
        originalText: String,
        action: RefineAction,
        modelName: String,
        apiKey: String,
        sourceApp: NSRunningApplication?
    ) {
        dismissWindow()

        let viewModel = RefinePreviewViewModel(
            originalText: originalText,
            action: action,
            modelID: GeminiModelCatalog.model(forAPIName: modelName)?.id ?? GeminiModelCatalog.defaultTextID,
            apiKey: apiKey
        )

        viewModel.onReplace = { [weak self] finalText in
            self?.dismissWindow()
            self?.inserter.paste(finalText, into: sourceApp)
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
            await viewModel.generate()
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
    private let service = RefineService()
    private var generation = 0

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
        GeminiModelCatalog.apiName(
            forID: selectedModelID,
            fallback: GeminiModelCatalog.apiName(forID: GeminiModelCatalog.defaultTextID, fallback: "gemini-3.8-flash"))
    }

    init(originalText: String, action: RefineAction, modelID: String, apiKey: String) {
        self.inputText = originalText
        self.action = action
        self.selectedModelID = modelID
        self.apiKey = apiKey
    }

    func generate() async {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await service.refine(text: inputText, action: action,
                                                  modelName: selectedModelAPIName, apiKey: apiKey)
            guard current == generation else { return }
            refinedText = result
        } catch {
            guard current == generation else { return }
            errorMessage = error.localizedDescription
            refinedText = inputText
        }
        isLoading = false
    }
}
