import AppKit
import SwiftUI
import Combine

/// On-screen record button: click to record / stop (transcript is copied), drag to move, right-click for options.
@MainActor
final class FloatingRecordButtonController: NSObject {
    static let panelSize = NSSize(width: 60, height: 60)

    private let appState: AppState
    private let onClick: () -> Void
    private let onOpenSettings: () -> Void
    private let model = FloatingButtonModel()
    private var panel: FloatingButtonPanel?
    private var hostView: FloatingButtonHostView?
    private var cancellables = Set<AnyCancellable>()
    private var latest: (mode: AppMode, origin: RecordingOrigin?, copiedAt: Date?, error: String?) = (.idle, nil, nil, nil)

    init(appState: AppState, onClick: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.appState = appState
        self.onClick = onClick
        self.onOpenSettings = onOpenSettings
        super.init()

        // $publishers emit before the property changes, so use the emitted values, not appState.*.
        Publishers.CombineLatest4(appState.$mode, appState.$recordingOrigin, appState.$lastCopiedAt, appState.$errorMessage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode, origin, copiedAt, error in
                self?.latest = (mode, origin, copiedAt, error)
                self?.refreshState()
            }
            .store(in: &cancellables)

        appState.$showFloatingButton
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in visible ? self?.show() : self?.hide() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.keepOnScreen(save: false) }
            .store(in: &cancellables)
    }

    // MARK: - State

    private func refreshState() {
        let state = FloatingButtonState.from(mode: latest.mode, origin: latest.origin,
                                             lastCopiedAt: latest.copiedAt, errorMessage: latest.error)
        model.state = state
        hostView?.toolTip = state.helpText
        if state == .copied {
            DispatchQueue.main.asyncAfter(deadline: .now() + FloatingButtonState.copiedDisplay + 0.05) { [weak self] in
                self?.refreshState()
            }
        }
    }

    // MARK: - Show / hide / position

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = Self.panelSize
        let saved = NSPoint(x: appState.overlayX, y: appState.overlayY)
        let origin: NSPoint
        if appState.hasCustomOverlayPosition {
            origin = saved
        } else {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            origin = FloatingButtonPlacement.defaultOrigin(size: size, visibleFrame: screen.visibleFrame)
        }
        panel.setFrameOrigin(FloatingButtonPlacement.clampedOrigin(origin, size: size, visibleFrames: NSScreen.screens.map(\.visibleFrame)))
        panel.orderFrontRegardless()
        refreshState()
    }

    private func hide() {
        model.hovering = false
        panel?.orderOut(nil)
    }

    private func keepOnScreen(save: Bool) {
        guard let panel, panel.isVisible else { return }
        let origin = FloatingButtonPlacement.clampedOrigin(panel.frame.origin, size: Self.panelSize,
                                                           visibleFrames: NSScreen.screens.map(\.visibleFrame))
        panel.setFrameOrigin(origin)
        if save {
            appState.overlayX = origin.x
            appState.overlayY = origin.y
        }
    }

    private func makePanel() -> FloatingButtonPanel {
        let panel = FloatingButtonPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = FloatingButtonHostView(rootView: FloatingRecordButtonView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        host.onClick = { [weak self] in self?.onClick() }
        host.onDragEnded = { [weak self] in self?.keepOnScreen(save: true) }
        host.onHover = { [weak self] inside in self?.model.hovering = inside }
        host.onRightClick = { [weak self] event in self?.showContextMenu(for: event) }
        panel.contentView = host
        hostView = host
        return panel
    }

    // MARK: - Context menu

    private func showContextMenu(for event: NSEvent) {
        guard let hostView else { return }
        let menu = NSMenu()
        let hideItem = NSMenuItem(title: "Hide Button", action: #selector(hideFromMenu), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        NSMenu.popUpContextMenu(menu, with: event, for: hostView)
        model.hovering = panel?.frame.contains(NSEvent.mouseLocation) ?? false
    }

    @objc private func hideFromMenu() {
        appState.showFloatingButton = false
    }

    @objc private func openSettingsFromMenu() {
        onOpenSettings()
    }
}

@MainActor
final class FloatingButtonModel: ObservableObject {
    @Published var state: FloatingButtonState = .idle
    @Published var hovering = false
}

/// Never becomes key or main, so clicking it leaves focus in the user's app.
final class FloatingButtonPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Handles click vs drag and hover itself; the SwiftUI content is purely visual.
final class FloatingButtonHostView: NSHostingView<FloatingRecordButtonView> {
    var onClick: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var dragging = false
    private var trackingArea: NSTrackingArea?

    required init(rootView: FloatingRecordButtonView) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onRightClick?(event); return }
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = windowStart else { return }
        let now = NSEvent.mouseLocation
        if !dragging, FloatingButtonPlacement.isDrag(from: start, to: now) {
            dragging = true
        }
        if dragging {
            window?.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            windowStart = nil
            dragging = false
        }
        guard dragStart != nil else { return }
        if !dragging, event.clickCount > 1 { return }
        if dragging {
            onDragEnded?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

struct FloatingRecordButtonView: View {
    @ObservedObject var model: FloatingButtonModel
    @State private var pulse = false

    var body: some View {
        ZStack {
            if model.state == .recording {
                Circle()
                    .stroke(Color.red.opacity(0.6), lineWidth: 3)
                    .frame(width: 52, height: 52)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.25 : 0.9)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            }

            Circle()
                .fill(fill)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)

            icon
        }
        .frame(width: 60, height: 60)
        .opacity(model.state == .idle && !model.hovering ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: model.hovering)
        .animation(.easeOut(duration: 0.15), value: model.state)
        .help(model.state.helpText)
    }

    private var fill: Color {
        switch model.state {
        case .idle, .busy: return Color.black.opacity(0.75)
        case .recording, .error: return .red
        case .processing: return .blue
        case .copied: return .green
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .idle:
            Image(systemName: "mic.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
        case .busy:
            Image(systemName: "mic.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
        case .recording:
            Image(systemName: "stop.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
        case .processing:
            SpinnerArc().scaleEffect(1.8)
        case .copied:
            Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
        case .error:
            Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        }
    }
}
