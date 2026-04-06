import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayPanelController {
    private var panel: NSPanel?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private static let panelSize: CGFloat = 22
    private static let cursorOffset = NSPoint(x: 16, y: -22)

    init(appState: AppState) {
        self.appState = appState
        observeState()
    }

    private func observeState() {
        Publishers.CombineLatest(appState.$mode, appState.$isLockMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] mode, _ in
                switch mode {
                case .listening, .processing, .error:
                    self?.showAtCursor()
                case .idle:
                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Show / Hide

    private func showAtCursor() {
        if panel == nil {
            panel = createPanel()
        }
        updateView()
        positionAtCursor()
        panel?.orderFront(nil)
        startTrackingCursor()
    }

    private func hide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard self?.appState.mode == .idle else { return }
            self?.panel?.orderOut(nil)
            self?.stopTrackingCursor()
        }
    }

    // MARK: - Cursor Tracking

    private func startTrackingCursor() {
        stopTrackingCursor()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.positionAtCursor()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.positionAtCursor()
            return event
        }
    }

    private func stopTrackingCursor() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
    }

    private func positionAtCursor() {
        let p = NSEvent.mouseLocation
        panel?.setFrameOrigin(NSPoint(x: p.x + Self.cursorOffset.x, y: p.y + Self.cursorOffset.y))
    }

    private func updateView() {
        guard let panel = panel,
              let hostingView = panel.contentView as? NSHostingView<CursorIndicatorView> else { return }
        hostingView.rootView = CursorIndicatorView(mode: appState.mode, isLocked: appState.isLockMode)
    }

    // MARK: - Panel

    private func createPanel() -> NSPanel {
        let s = Self.panelSize
        let view = CursorIndicatorView(mode: appState.mode, isLocked: appState.isLockMode)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: s, height: s),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.ignoresMouseEvents = true
        p.contentView = hosting
        p.isReleasedWhenClosed = false
        return p
    }
}

// MARK: - Cursor Indicator View

struct CursorIndicatorView: View {
    let mode: AppMode
    let isLocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.9))
                .overlay(Circle().stroke(backgroundColor.opacity(0.5), lineWidth: 1))
                .shadow(color: backgroundColor.opacity(0.6), radius: 4)

            content
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .listening:
            SoundWaveBars()
        case .processing:
            SpinnerArc()
        case .error:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        case .idle:
            EmptyView()
        }
    }

    private var backgroundColor: Color {
        switch mode {
        case .listening:  return .green
        case .processing: return .blue
        case .error:      return .red
        case .idle:       return .clear
        }
    }
}

// MARK: - Sound Wave Bars (green — recording)

struct SoundWaveBars: View {
    @State private var phase = false

    private let barHeights: [[CGFloat]] = [
        [3, 8, 5, 9, 4],
        [7, 4, 9, 3, 7],
    ]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 1.5, height: phase ? barHeights[1][i] : barHeights[0][i])
            }
        }
        .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = true }
    }
}

// MARK: - Spinner Arc (blue — processing)

struct SpinnerArc: View {
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.7).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}
