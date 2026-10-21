import SwiftUI

struct RefinePreviewView: View {
    @ObservedObject var viewModel: RefinePreviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            actionBar
        }
        .frame(minWidth: 480, minHeight: 380)
        .onChange(of: viewModel.action) { _, _ in Task { await viewModel.generate() } }
        .onChange(of: viewModel.selectedModelID) { _, _ in Task { await viewModel.generate() } }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Style:", selection: $viewModel.action) {
                ForEach(RefineAction.allCases) { action in
                    Label(action.displayName, systemImage: actionIcon(action))
                        .tag(action)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            Picker("Model:", selection: $viewModel.selectedModelID) {
                ForEach(GeminiModelCatalog.textModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .frame(width: 180)

            Button {
                Task { await viewModel.generate() }
            } label: {
                Label("Generate", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    private var content: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                Label("Input (editable)", systemImage: "pencil.line")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TextEditor(text: $viewModel.inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }
            .padding(12)
            .frame(minWidth: 180)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Refined", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Refining with \(viewModel.action.displayName)...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                } else {
                    TextEditor(text: $viewModel.refinedText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.blue.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .frame(minWidth: 180)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                viewModel.onCancel?()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                viewModel.onCopy?(viewModel.refinedText)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.isLoading || viewModel.refinedText.isEmpty)

            Button {
                viewModel.onReplace?(viewModel.refinedText)
            } label: {
                Label("Replace", systemImage: "arrow.triangle.swap")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isLoading || viewModel.refinedText.isEmpty)
        }
        .padding(16)
    }

    private func actionIcon(_ action: RefineAction) -> String {
        switch action {
        case .elaborate:  return "text.append"
        case .polish:     return "sparkles"
        case .shorten:    return "scissors"
        case .formalize:  return "briefcase"
        }
    }
}
