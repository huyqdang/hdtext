# HD Text

A native macOS dictation app powered by Gemini AI. Hold a shortcut, speak naturally, release — your speech is transcribed, cleaned up, and typed into whatever app you're using.

## How It Works

1. **Hold** a global keyboard shortcut (default: `Ctrl+P`) to start dictating
2. **Speak** naturally — fillers, false starts, and broken sentences are fine
3. **Release** the shortcut when done
4. Gemini transcribes your speech, cleans up the text, and pastes it into the active app

## Refine Selected Text

Select text in any app, press the hotkey — if text is selected, a refine menu appears:

- **Elaborate** — expand with more detail
- **Polish** — improve grammar and flow
- **Shorten** — make more concise
- **Formalize** — rewrite in a professional tone

The refine window lets you switch actions, pick a model, edit both input and output, regenerate, then replace.

## Features

- Menu bar app — always available, never in the way
- Global hold-to-talk shortcut (suppresses underlying app shortcuts)
- Single-pass AI: transcription + cleanup in one API call
- Three cleanup levels: minimal, balanced, polished
- Smart Correction: predicts and fixes misrecognized words
- Aggressive filler word removal (um, uh, like, you know, etc.)
- Configurable Gemini model selection (Flash Lite through Pro)
- Hotkey-triggered text refinement with action/model switching
- Editable preview before replacing text
- Compact floating indicator dot (draggable, position saved)
- Selectable microphone input
- Microphone calibration screen
- Local transcription history with search, favorites, and export
- API key stored securely in macOS Keychain

## Requirements

- macOS 14.0+
- A [Gemini API key](https://aistudio.google.com/apikey)

## Install

Download the DMG, drag **HD Text** to Applications, and launch.

On first launch, the onboarding flow guides you through:
- Granting microphone permission
- Enabling Accessibility (System Settings > Privacy & Security > Accessibility)
- Entering your Gemini API key

## Building from Source

```bash
brew install xcodegen
cd willow-voice-macos
xcodegen generate
open HDText.xcodeproj
```

Build and run the `HDText` target.

## Building a DMG

```bash
./scripts/build-dmg.sh
```

## Project Structure

```
HDText/
├── App/                    # App entry, delegate, state, menu bar
├── Features/
│   ├── Onboarding/         # First-run setup flow
│   ├── Calibration/        # Mic test and level meter
│   ├── History/            # Transcription history
│   └── Refine/             # Text refinement actions and preview
├── Services/
│   ├── Audio/              # AVAudioEngine capture and device management
│   ├── Hotkey/             # Global hold-to-talk shortcut
│   ├── Gemini/             # Transcription, rewrite, model catalog
│   ├── Insertion/          # Text insertion via paste
│   ├── Persistence/        # Local history storage
│   └── Security/           # Keychain API key storage
├── Views/                  # Settings, overlay, shortcut recorder
└── Resources/              # Info.plist, entitlements, assets
```
