# Floating Record Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A movable, semi-transparent on-screen button: click to record, click again to stop; the transcript is copied to the clipboard.

**Architecture:** Pure logic (placement, click-vs-drag, button state) lives in `FloatingButtonLogic.swift` and is unit-tested. A non-activating `NSPanel` hosts a SwiftUI view (`FloatingRecordButton.swift`). `AppDelegate` reuses the existing capture → Gemini → history pipeline and delivers by `RecordingOrigin` (`.hotkey` pastes, `.button` copies).

**Tech Stack:** Swift 5.9, AppKit + SwiftUI + Combine, macOS 14+, XcodeGen, XCTest.

Spec: `docs/superpowers/specs/2026-10-26-floating-record-button-design.md`

## Global Constraints
- Worktree: `/Users/huydang/Desktop/projects/hdtext-float` (branch `feature/floating-record-button`). Never edit `/Users/huydang/Desktop/projects/hdtext`.
- `.xcodeproj` is generated: run `xcodegen generate` after adding files. Env: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Focused test command (replace `<Suite>`):
  ```bash
  cd /Users/huydang/Desktop/projects/hdtext-float && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && xcodegen generate >/dev/null && xcodebuild -project HDText.xcodeproj -scheme HDText -derivedDataPath /private/tmp/claude-501/-Users-huydang-Documents/ce759666-9dc7-49e4-af61-951e51bca006/scratchpad/dd-float test -only-testing:HDTextTests/<Suite> 2>&1 | grep -E "error: |failed \(|Executed .* tests|\*\* TEST" | grep -v "linkd\|Unable"
  ```
  Full suite: same without `-only-testing:...`, once at the end of each task.
- Tests run inside the app host: never touch the real Keychain item (`com.hdtext.app`), `NSPasteboard.general`, or post keystrokes/clicks; restore any `UserDefaults.standard` key a test changes.
- Never block the main thread (it services the global hotkey event tap): no synchronous I/O, sleeps or `waitUntilExit` in UI code.
- Button geometry: panel 60×60 pt, circle 44 pt, idle opacity 0.45 (1.0 on hover), drag threshold 4 pt, default inset 24 pt from the main screen's bottom-right `visibleFrame` corner, "copied" check shown 1.5 s.
- Position persists in the existing `AppState.overlayX` / `overlayY` (+ `hasCustomOverlayPosition`). Visibility persists in `UserDefaults` key `showFloatingButton`, default `true`.
- Commit at the end of each task; message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Match surrounding style (4-space indent, `hdLog(...)`, sparse comments).

## File Map
| File | Task |
|---|---|
| `HDText/Views/FloatingButtonLogic.swift` (new), `HDText/App/AppState.swift`, `HDText/Services/Insertion/TextInsertionService.swift`, `HDTextTests/FloatingButtonLogicTests.swift` (new), `HDTextTests/TextInsertionServiceTests.swift` | 1 |
| `HDText/Views/FloatingRecordButton.swift` (new) | 2 |
| `HDText/App/AppDelegate.swift`, `HDText/App/MenuBarController.swift`, `HDText/Views/SettingsView.swift` | 3 |
| `README.md`, `project.yml` | 4 |

---

### Task 1: Button logic, AppState fields, clipboard copy  (model: sonnet)

**Files:** Create `HDText/Views/FloatingButtonLogic.swift`, `HDTextTests/FloatingButtonLogicTests.swift`; modify `HDText/App/AppState.swift`, `HDText/Services/Insertion/TextInsertionService.swift`, `HDTextTests/TextInsertionServiceTests.swift`.

**Interfaces — Produces:**
```swift
enum RecordingOrigin: Equatable { case hotkey, button }                      // AppState.swift
// AppState additions:
@Published var mode: AppMode = .idle   // didSet: if mode != .listening { recordingOrigin = nil }
@Published var recordingOrigin: RecordingOrigin?
@Published var lastCopiedAt: Date?
@Published var showFloatingButton: Bool   // UserDefaults "showFloatingButton", default true

enum FloatingButtonState: Equatable {
    case idle, recording, busy, processing, copied, error(String)
    var helpText: String
    static let copiedDisplay: TimeInterval = 1.5
    static func from(mode: AppMode, origin: RecordingOrigin?, lastCopiedAt: Date?, errorMessage: String?, now: Date = Date()) -> FloatingButtonState
}
enum FloatingButtonPlacement {
    static let dragThreshold: CGFloat = 4
    static let inset: CGFloat = 24
    static func isDrag(from start: NSPoint, to end: NSPoint) -> Bool
    static func defaultOrigin(size: NSSize, visibleFrame: NSRect) -> NSPoint
    static func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrames: [NSRect]) -> NSPoint
}
// TextInsertionService:
func copyToClipboard(_ text: String)
```

- [ ] **Step 1: Failing tests** — `HDTextTests/FloatingButtonLogicTests.swift`:
```swift
import XCTest
@testable import HDText

final class FloatingButtonLogicTests: XCTestCase {
    private let size = NSSize(width: 60, height: 60)
    private let main = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = NSRect(x: 1440, y: 0, width: 1920, height: 1055)

    func testOffScreenOriginIsClampedIntoNearestScreen() {
        let clamped = FloatingButtonPlacement.clampedOrigin(NSPoint(x: 5000, y: -300), size: size, visibleFrames: [main, right])
        XCTAssertEqual(clamped, NSPoint(x: right.maxX - 60, y: right.minY))
    }

    func testOriginOnSecondScreenIsKept() {
        let origin = NSPoint(x: 2000, y: 400)
        XCTAssertEqual(FloatingButtonPlacement.clampedOrigin(origin, size: size, visibleFrames: [main, right]), origin)
    }

    func testDefaultOriginIsBottomRightWithInset() {
        XCTAssertEqual(FloatingButtonPlacement.defaultOrigin(size: size, visibleFrame: main), NSPoint(x: 1440 - 60 - 24, y: 24))
    }

    func testSmallMoveIsClickLargerMoveIsDrag() {
        XCTAssertFalse(FloatingButtonPlacement.isDrag(from: .zero, to: NSPoint(x: 3, y: 0)))
        XCTAssertTrue(FloatingButtonPlacement.isDrag(from: .zero, to: NSPoint(x: 5, y: 0)))
    }

    func testStateFollowsModeOriginAndCopyTime() {
        let now = Date()
        XCTAssertEqual(FloatingButtonState.from(mode: .idle, origin: nil, lastCopiedAt: nil, errorMessage: nil, now: now), .idle)
        XCTAssertEqual(FloatingButtonState.from(mode: .listening, origin: .button, lastCopiedAt: nil, errorMessage: nil, now: now), .recording)
        XCTAssertEqual(FloatingButtonState.from(mode: .listening, origin: .hotkey, lastCopiedAt: nil, errorMessage: nil, now: now), .busy)
        XCTAssertEqual(FloatingButtonState.from(mode: .processing, origin: nil, lastCopiedAt: nil, errorMessage: nil, now: now), .processing)
        XCTAssertEqual(FloatingButtonState.from(mode: .idle, origin: nil, lastCopiedAt: now.addingTimeInterval(-0.5), errorMessage: nil, now: now), .copied)
        XCTAssertEqual(FloatingButtonState.from(mode: .idle, origin: nil, lastCopiedAt: now.addingTimeInterval(-2), errorMessage: nil, now: now), .idle)
        XCTAssertEqual(FloatingButtonState.from(mode: .error, origin: nil, lastCopiedAt: nil, errorMessage: "No speech", now: now), .error("No speech"))
    }
}
```
Add to `HDTextTests/TextInsertionServiceTests.swift` (uses the file's private named `pasteboard`):
```swift
    func testCopyToClipboardLeavesTextOnPasteboard() {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        TextInsertionService(pasteboard: pasteboard).copyToClipboard("Hello from the button")
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello from the button")
    }
```
- [ ] **Step 2: Run** `<Suite>` = `FloatingButtonLogicTests` → compile failure.
- [ ] **Step 3: Implement `HDText/Views/FloatingButtonLogic.swift`:**
```swift
import AppKit

/// What the floating record button shows; derived from app state so it can be tested without UI.
enum FloatingButtonState: Equatable {
    case idle, recording, busy, processing, copied, error(String)

    static let copiedDisplay: TimeInterval = 1.5

    var helpText: String {
        switch self {
        case .idle: return "Click to record · drag to move · right-click for options"
        case .recording: return "Recording — click to stop and copy"
        case .busy: return "Recording with the hotkey"
        case .processing: return "Transcribing…"
        case .copied: return "Copied to clipboard"
        case .error(let message): return message
        }
    }

    static func from(mode: AppMode, origin: RecordingOrigin?, lastCopiedAt: Date?, errorMessage: String?, now: Date = Date()) -> FloatingButtonState {
        switch mode {
        case .listening:
            return origin == .button ? .recording : .busy
        case .processing:
            return .processing
        case .error:
            return .error(errorMessage ?? "Something went wrong")
        case .idle:
            if let lastCopiedAt, now.timeIntervalSince(lastCopiedAt) < copiedDisplay {
                return .copied
            }
            return .idle
        }
    }
}

enum FloatingButtonPlacement {
    static let dragThreshold: CGFloat = 4
    static let inset: CGFloat = 24

    static func isDrag(from start: NSPoint, to end: NSPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > dragThreshold
    }

    static func defaultOrigin(size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.maxX - size.width - inset, y: visibleFrame.minY + inset)
    }

    /// Keeps the whole button inside the screen that holds its centre, else the nearest screen.
    static func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrames: [NSRect]) -> NSPoint {
        guard !visibleFrames.isEmpty else { return origin }
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let frame = visibleFrames.first { $0.contains(center) } ?? visibleFrames.min {
            distance(from: center, to: $0) < distance(from: center, to: $1)
        }!
        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
```
`AppState.swift`: add above the class `enum RecordingOrigin: Equatable { case hotkey, button }`; change `@Published var mode: AppMode = .idle` to
```swift
    @Published var mode: AppMode = .idle {
        didSet { if mode != .listening { recordingOrigin = nil } }
    }
    @Published var recordingOrigin: RecordingOrigin?
    @Published var lastCopiedAt: Date?
```
and next to the other persisted prefs add
```swift
    @Published var showFloatingButton: Bool {
        didSet { UserDefaults.standard.set(showFloatingButton, forKey: "showFloatingButton") }
    }
```
initialised in `init` with `self.showFloatingButton = UserDefaults.standard.object(forKey: "showFloatingButton") as? Bool ?? true`.
`TextInsertionService`: add after `paste(...)`:
```swift
    /// Leaves `text` on the clipboard for the user to paste (no restore).
    func copyToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
```
- [ ] **Step 4: Run** `FloatingButtonLogicTests` and `TextInsertionServiceTests` → pass; then full suite.
- [ ] **Step 5: Commit** — "Floating button logic, recording origin, clipboard copy".

---

### Task 2: Floating panel + SwiftUI button  (model: sonnet)

**Files:** Create `HDText/Views/FloatingRecordButton.swift`.

**Interfaces:**
- Consumes (Task 1): `FloatingButtonState`, `FloatingButtonPlacement`, `AppState.mode/recordingOrigin/lastCopiedAt/errorMessage/showFloatingButton/overlayX/overlayY/hasCustomOverlayPosition`, `RecordingOrigin`. Existing `SpinnerArc` view (in `HDText/Views/OverlayPanelController.swift`).
- Produces:
```swift
@MainActor final class FloatingRecordButtonController: NSObject {
    init(appState: AppState, onClick: @escaping () -> Void, onOpenSettings: @escaping () -> Void)
}
```
Not instantiated yet (Task 3 does it); this task must compile and keep the suite green.

- [ ] **Step 1: Create the file** with exactly:
```swift
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
            .receive(on: RunLoop.main)
            .sink { [weak self] mode, origin, copiedAt, error in
                self?.latest = (mode, origin, copiedAt, error)
                self?.refreshState()
            }
            .store(in: &cancellables)

        appState.$showFloatingButton
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in visible ? self?.show() : self?.hide() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
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
        let origin = appState.hasCustomOverlayPosition
            ? saved
            : FloatingButtonPlacement.defaultOrigin(size: size, visibleFrame: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
        panel.setFrameOrigin(FloatingButtonPlacement.clampedOrigin(origin, size: size, visibleFrames: NSScreen.screens.map(\.visibleFrame)))
        panel.orderFrontRegardless()
        refreshState()
    }

    private func hide() {
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
```
If `NSHostingView` subclassing needs different initializer attributes to compile on this SDK (e.g. `@MainActor` on `init(rootView:)`), adjust only the attributes and note it in the report.
- [ ] **Step 2: Build + full suite** (no new tests: UI-only, logic tested in Task 1).
- [ ] **Step 3: Commit** — "Floating record button panel and view".

---

### Task 3: Wire the button into dictation, menu and settings  (model: opus)

**Files:** Modify `HDText/App/AppDelegate.swift`, `HDText/App/MenuBarController.swift`, `HDText/Views/SettingsView.swift`.

**Interfaces — Consumes:** `RecordingOrigin`, `AppState.recordingOrigin/lastCopiedAt/showFloatingButton` (Task 1), `TextInsertionService.copyToClipboard(_:)` (Task 1), `FloatingRecordButtonController(appState:onClick:onOpenSettings:)` (Task 2).

- [ ] **Step 1: AppDelegate**
  - Property `private var floatingButtonController: FloatingRecordButtonController?`; in `applicationDidFinishLaunching`, right after `overlayController = ...`:
    ```swift
    floatingButtonController = FloatingRecordButtonController(
        appState: appState,
        onClick: { [weak self] in self?.toggleButtonRecording() },
        onOpenSettings: { [weak self] in self?.showSettingsWindow() }
    )
    ```
  - `private func beginCapture()` → `private func beginCapture(origin: RecordingOrigin = .hotkey)`; immediately after its `appState.mode = .listening` line add `appState.recordingOrigin = origin`.
  - First line of both `handleDictationStart` and `handleDictationEnd` (before anything else, including `dictationStartTime = Date()`):
    ```swift
    if appState.recordingOrigin == .button { return }  // the hotkey never touches a button recording
    ```
  - New method (MARK: - Floating Button):
    ```swift
    func toggleButtonRecording() {
        switch appState.mode {
        case .idle, .error:
            appState.errorMessage = nil
            appState.mode = .idle
            beginCapture(origin: .button)
        case .listening:
            guard appState.recordingOrigin == .button else { return }
            finalizeDictation()
        case .processing:
            return
        }
    }
    ```
  - `finalizeDictation()`: first line `let origin = appState.recordingOrigin ?? .hotkey` (read before any mode change). In the success `MainActor.run` block replace the history record's `targetApp:` with `origin == .button ? "Clipboard" : (targetApp?.localizedName ?? "Unknown")`, and replace the `appState.textInsertionService.paste(cleaned, into: targetApp) { ... }` call with:
    ```swift
    switch origin {
    case .hotkey:
        appState.textInsertionService.paste(cleaned, into: targetApp) { [weak self] in
            self?.playSound("Glass")
        }
    case .button:
        appState.textInsertionService.copyToClipboard(cleaned)
        appState.lastCopiedAt = Date()
        playSound("Glass")
        hdLog("Copied transcript to clipboard (\(cleaned.count) chars)")
    }
    ```
  - Leave the "Recording too short. Hold the key longer…" text as is.
- [ ] **Step 2: MenuBarController** — in `populate(_:)`, just before the `historyItem` block:
    ```swift
    let floatingItem = NSMenuItem(title: "Show Floating Button", action: #selector(toggleFloatingButton), keyEquivalent: "")
    floatingItem.target = self
    floatingItem.state = appState.showFloatingButton ? .on : .off
    menu.addItem(floatingItem)
    ```
  and add `@objc private func toggleFloatingButton() { appState.showFloatingButton.toggle() }`.
- [ ] **Step 3: SettingsView** — in General, after the "Smart Correction" GroupBox:
    ```swift
    GroupBox("Floating Record Button") {
        Toggle(isOn: $appState.showFloatingButton) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Show floating record button").font(.body)
                Text("Click to record, click again to copy the transcript. Drag to move; right-click to hide.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
    ```
- [ ] **Step 4: Trace and verify.** In the report, trace these against the code: (a) button click → listening(.button) → click → processing → idle + clipboard + `lastCopiedAt`; (b) during (a) hold/release ⌃P → ignored; (c) ⌃P hold during idle, then button click while listening(.hotkey) → ignored, release pastes as before; (d) button click while mode == .error → new recording; (e) Cancel Dictation from the menu during a button recording → idle, origin cleared. Build + full suite. Then launch the Debug app built in dd-float (`open .../Build/Products/Debug/HDText.app`) only long enough to confirm in `/usr/bin/log show --predicate 'process == "HDText"' --last 1m` that it starts without errors, then quit it with `osascript -e 'tell application id "com.hdtext.app" to quit'` — note this also quits the user's installed copy if running; if `pgrep -x HDText` shows a process before you start, SKIP the launch step and say so.
- [ ] **Step 5: Commit** — "Wire floating record button: copy transcript, menu and settings toggles".

---

### Task 4: Docs, version, release build  (model: haiku)

**Files:** `README.md`, `project.yml`.
- [ ] `project.yml`: `MARKETING_VERSION: "1.2.0"`, `CURRENT_PROJECT_VERSION: "3"`.
- [ ] README: under "How It Works" add a short "Floating Record Button" section: "A small translucent mic button floats on screen. Click it to start recording, click again to stop — the cleaned transcript is copied to your clipboard. Drag it anywhere (position is remembered); right-click to hide it, or toggle it from the menu bar (**Show Floating Button**) or Settings › General." Add a Features bullet "On-screen floating record button that copies the transcript to the clipboard".
- [ ] Run `./scripts/build-dmg.sh` → must end with "==> Done! DMG at: …/build/HDText.dmg".
- [ ] Commit — "Docs and version 1.2.0".

## Final wave (controller)
Full suite once; whole-branch review (opus); one fix wave if needed; DMG rebuild.
