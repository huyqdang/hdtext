# Floating record button — design (2026-10-26)

## Goal
An on-screen, movable, semi-transparent button: click to start recording, click again to stop; the cleaned transcript is copied to the clipboard (not pasted).

## Behaviour
| State (`AppState.mode` + origin) | Button look | Click does |
|---|---|---|
| idle | 44 pt circle, mic glyph, 45 % opacity (100 % on hover) | start a **button** recording |
| listening, origin = button | red fill, pulsing ring | stop → transcribe → copy |
| listening, origin = hotkey | dimmed mic | nothing |
| processing | blue fill, spinner | nothing |
| just copied (1.5 s) | green fill, ✓ | — |
| error | red fill, ✕, tooltip = `appState.errorMessage` | start a new recording (clears error) |

- Output: `NSPasteboard.general` gets the transcript and keeps it (no restore, no transient marker); sound "Glass"; history record with `targetApp = "Clipboard"`.
- Hotkey and button sessions are independent: a hotkey release never finalizes a button recording; a button click during a hotkey recording is ignored. Same capture/transcription pipeline, mic, model, cleanup settings, errors (too short, silence, no key, API errors) as the hotkey.
- Drag: press + move > 4 pt moves the panel (no click). Origin saved on drag end in `AppState.overlayX/overlayY` (existing, unused keys). On show and on `NSApplication.didChangeScreenParametersNotification`, the origin is clamped so the button is fully inside some screen's `visibleFrame`; default (no saved position) = bottom-right of main screen, 24 pt inset.
- Window: borderless non-activating `NSPanel`, `.floating` level, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, clear background, no shadow on the window (the view draws its own soft shadow), never becomes key/main — clicking it doesn't take focus from the frontmost app.
- Right-click: context menu "Hide Button" and "Settings…".
- Visibility: `AppState.showFloatingButton` (UserDefaults `showFloatingButton`, default **true**). Toggles: menu bar item "Show Floating Button" (checkmark), Settings › General › "Floating Record Button" toggle, context-menu Hide.

## Components
- `HDText/Views/FloatingButtonPlacement.swift` — pure helpers: `clampedOrigin(_:size:screens:)`, `defaultOrigin(size:screen:)`, `isDrag(from:to:)` (threshold 4 pt).
- `HDText/Views/FloatingRecordButton.swift` — `FloatingRecordButtonController` (owns the panel, mouse handling, observes `AppState`), `FloatingRecordButtonView` (SwiftUI look), `FloatingButtonPanel` (NSPanel subclass: `canBecomeKey/Main = false`).
- `AppState` — `showFloatingButton`; `recordingOrigin: RecordingOrigin?` (`.hotkey` / `.button`, published, nil when not listening); `lastCopiedAt: Date?` (published, drives the ✓).
- `TextInsertionService.copyToClipboard(_:)` — clearContents + setString on its pasteboard.
- `AppDelegate` — `toggleButtonRecording()`; `beginCapture(origin:)`; `finalizeDictation()` delivers by origin (paste vs copy); hotkey end handler ignores sessions whose origin is `.button`.
- `MenuBarController`, `SettingsView` — the visibility toggles.

## Testing (core only)
- Placement: off-screen origin is clamped into a visible frame; no saved position → bottom-right default; 3 pt move is a click, 5 pt is a drag.
- Copy: `copyToClipboard` leaves the text on a private pasteboard.
- Manual (Debug build): click/drag/right-click, hotkey isolation, focus stays in the frontmost app.

## Out of scope
Auto-stop timer, waveform/level meter in the button, multiple buttons, per-button model choice.
