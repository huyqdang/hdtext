# HDText revival — design (2026-10-21)

## Goal
Make HDText work again on today's Gemini API and fix the reliability bugs in the last build. No new features beyond what is needed to make existing ones dependable.

## Why it is broken today
- The saved transcription model `gemini-3.1-flash-lite-preview` was shut down 2026-05-25 → every dictation fails.
- `google-gemini/generative-ai-swift` is archived ("Obsolete – DO NOT USE"); it cannot send `thinkingConfig`, so newer models run with default thinking (slow, costly).
- AI Studio issues **auth keys** since 2026-05-28 (reported prefix `AQ.`, older keys `AIza…`). Unrestricted standard keys are rejected. The app must accept any key string and validate it with a live call.
- 2.5 models are gated to past users; new keys may not reach them.

## 1. Gemini layer

### GeminiClient (new, `HDText/Services/Gemini/GeminiClient.swift`)
- `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, header `x-goog-api-key: <key>`, `Content-Type: application/json`. Never `?key=`, never Bearer.
- Body: `systemInstruction.parts[].text`, `contents[0]` role `user` with parts (`text` and/or `inlineData{mimeType,data(base64)}`), `generationConfig{temperature, maxOutputTokens?, thinkingConfig?}`.
- Response: join `candidates[0].content.parts[].text` where `thought != true`. Empty → `GeminiAPIError.emptyResponse`. `finishReason` `SAFETY`/`PROHIBITED_CONTENT` → `.blocked`.
- Error mapping from HTTP status + `error.status`/`error.message` body:
  - 400 with `API_KEY_INVALID` / "API key" in message, 401, 403 → `.invalidKey`
  - 404 → `.modelUnavailable(model)`
  - 429 → `.rateLimited`
  - 5xx → `.server(status)`
  - other 400 → `.badRequest(message)`
  - URLError → `.network(description)`
- Thinking fallback: if a request that carried `thinkingConfig` gets a 400 whose message mentions "thinking", resend once without `thinkingConfig`.
- `listModels(apiKey:)` → `GET /v1beta/models?pageSize=1000` → `[String]` model IDs (without `models/` prefix) that support `generateContent`. Used by **Test key**.
- Injectable `URLSession` for tests (URLProtocol stub). Timeout 30 s.

### Model catalog
| id | API name | thinking | role |
|---|---|---|---|
| `3.5-flash-lite` | `gemini-3.5-flash-lite` | level `minimal` | default transcription |
| `3.1-flash-lite` | `gemini-3.1-flash-lite` | level `minimal` | |
| `3.8-flash` | `gemini-3.8-flash` | level `low` | default refine |
| `3.6-flash` | `gemini-3.6-flash` | level `low` | |
| `4-argon` | `gemini-4-argon` | level `low` | highest quality |

- `GeminiModel` gains `thinkingLevel: String?` and drops `supportsLive`.
- `GeminiModelCatalog.migrate(id:fallback:)` returns the id if known, else the fallback. `AppState.init` runs it on both saved ids (and persists the result).
- Settings › Models info text updated (Flash-Lite fastest, Flash balanced, 4 Argon best).

### Services
- `GeminiTranscriptionService` and `RefineService` call `GeminiClient`. Prompts unchanged. Transcription temperature 0.2; refine 0.7.
- `TranscriptionError`/`RefineError` keep their cases; API errors surface `GeminiAPIError.errorDescription` with plain messages, e.g. "Gemini rejected the API key. Check it in Settings › API Key." / "Model gemini-x is no longer available. Pick another in Settings › Models."
- Delete `GeminiLiveTranscriptionService`, `GeminiRewriteService`, their tests, `TranscriptionOverlayView.swift`, and the `GoogleGenerativeAI` package from `project.yml`.

### API key UX
- No format checks. Trim whitespace/newlines on save (Settings and Onboarding).
- **Test key** button (Settings › API Key, Onboarding key step): calls `listModels`; shows "Key works" + whether the selected transcription and refine models are available, or the mapped error.
- Link text: "Get a Gemini API key (AI Studio)".

## 2. Reliability fixes
1. **Key cache** — `AppState` holds `apiKey: String?` loaded once at init; `saveAPIKey/removeAPIKey` on AppState update Keychain + cache; `hasAPIKey` reads the cache. All `keychainStore.retrieveAPIKey()` call sites switch to `appState.apiKey`.
2. **Keychain test isolation** — `KeychainStore(service:)` with default `"com.hdtext.app"`; tests use `"com.hdtext.app.tests"`. `AppStateTests` must not delete the real key.
3. **Hotkey callbacks off the tap** — `onHoldStarted/onHoldEnded` posted via `DispatchQueue.main.async` so mic start never runs inside the CGEvent tap callback.
4. **One paste path** — `TextInsertionService.paste(_ text:, into app: NSRunningApplication?)`:
   - snapshot all pasteboard items (all types), write text, activate app, wait 0.25 s, post ⌘V, restore snapshot after 0.8 s **only if** `changeCount` is still the one we set.
   - Used by dictation, Refine › Replace, History › Re-insert. Remove AX `kAXValue` write (it replaced whole fields).
   - Selection-copy fallback in AppDelegate restores the clipboard with the same snapshot helper (incl. originally-empty clipboard), only if changeCount is ours.
5. **Lock-mode tap** — the release of the tap that activated lock mode is ignored (does not arm `lockExitTapTime`); the 0.5 s clear only clears its own timestamp.
6. **Onboarding** — `switch currentStep` instead of `TabView`; "Get Started" sets complete, closes the window (AppDelegate closure), and calls `onOnboardingComplete()`.
7. **Refine window** — close existing window before showing a new one; regenerate on action/model change (skip while loading); one `RefineService` owned by the view model.
8. **Audio resampling** — `AVAudioConverter` from tap format → 16 kHz mono Float32 (then Int16), converter created once per capture; replaces manual linear interpolation.
9. **Stale Accessibility grant** — if `AXIsProcessTrusted()` is false: menu + Settings show "Reset & re-grant Accessibility" which runs `/usr/bin/tccutil reset Accessibility com.hdtext.app` then prompts. Copy explains a rebuilt app needs re-granting.
10. **Menu** — rebuild in `menuNeedsUpdate(_:)` (NSMenuDelegate) + on mode change; drop the 3 s timer.
11. **Tests** — remove `testInsertTextReturnsBoolResult` (pastes into the focused app).
12. **Docs/version** — README build steps (`cd hdtext`, xcodegen, `DEVELOPER_DIR`), models + key notes; `MARKETING_VERSION` 1.1.0; `project.yml` keeps the audio-input entitlement.

## Testing (core only)
- GeminiClient: request shape (URL, header, body incl. inlineData + thinkingConfig), response parsing skips thought parts, error mapping (401/404/429), thinking-retry fallback.
- Model catalog migration.
- Paste snapshot/restore (restore skipped when changeCount changed).
- Keychain store isolation (separate service).
Full suite once per task and at the end. Real-API smoke test only if the user supplies a key.

## Out of scope
Live streaming, `gemini-3.5-transcribe` (Interactions + Files API only), dynamic model lists in the picker, Developer ID signing / notarization.
