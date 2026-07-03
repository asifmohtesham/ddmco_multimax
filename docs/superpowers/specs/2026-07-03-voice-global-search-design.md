# Voice search for global document search — design

**Date:** 2026-07-03
**Branch:** `feature/voice-global-search` (worktree, based on `release/play-store`)
**Status:** Approved design, pending implementation plan

## Goal

Let a user dictate their query in the dashboard's global document search overlay
(`GlobalDocumentSearchDelegate`) instead of typing it. Tapping a microphone
button captures speech on-device, transcribes it to text, fills the search
field with the transcript, and shows the normal grouped results. The user still
taps a result to open it — voice never auto-navigates.

## Scope

**In scope**

- A mic action in `GlobalDocumentSearchDelegate.buildActions` (the dashboard
  "Search any document" overlay only).
- On-device speech-to-text via the `speech_to_text` package.
- A listening UI (bottom sheet) with live partial transcript and a clear
  "listening / stopped" state.
- Runtime `RECORD_AUDIO` permission handling (self-managed by the package,
  mirroring how `mobile_scanner`/`image_picker` already work — no
  `permission_handler` dependency added).
- Android platform config (manifest permission + `RecognitionService` query).
  iOS Info.plist keys added for parity so an iOS build does not crash, but
  Android is the tested target.

**Explicitly out of scope (YAGNI)**

- The 11 per-list search bars (`DocTypeSearchDelegate`). Easy follow-up; not now.
- Server-side / cloud transcription. On-device only.
- Auto-opening a document from a voice result.
- Custom vocabulary / grammar tuning for item or customer codes.
- Continuous / wake-word listening. One tap = one dictation.

## Decisions (locked with user)

| Question | Decision |
|---|---|
| Placement | Global document search overlay only |
| Engine | On-device `speech_to_text` (native Android `SpeechRecognizer`) |
| On final transcript | Fill the query field + show results; **no** auto-open |
| Locale | Device locale, **fallback `en_GB`** |

## Architecture

Three units, each independently testable.

### 1. `VoiceSearchService` — thin wrapper around `speech_to_text`

A GetX service (`Get.lazyPut`, not permanent — only needed while searching)
that owns the `SpeechToText` plugin instance and exposes a small, mockable
surface. This isolates the third-party package from the widget layer so the
delegate and the sheet stay unit-testable without a live recognizer.

Responsibilities:

- `Future<bool> ensureInitialized()` — calls `SpeechToText.initialize` once
  (idempotent), returns availability. Surfaces permission/no-recognizer
  failures as a `false` return plus a typed reason, never throws.
- `Future<void> startListening({required ValueChanged<String> onPartial,
  required ValueChanged<String> onFinal, required VoidCallback onDone})` —
  resolves the locale (see below) and calls `listen`, routing
  `SpeechRecognitionResult` callbacks to `onPartial`/`onFinal`.
- `Future<void> stop()` / `Future<void> cancel()`.
- `bool get isListening`.
- **Locale resolution** (pure, unit-tested): given the list of available
  `LocaleName`s and the device locale, pick the device locale if the recognizer
  supports it, else the first `en_GB` match, else `en_US`, else `null` (let the
  engine default). Extracted as a pure static `resolveLocaleId(available,
  deviceLocale)` so it is tested without a recognizer.

### 2. `VoiceSearchSheet` — the listening UI

A `showModalBottomSheet` widget driven by a small local controller (or the
service's observable state). Shows:

- A large mic glyph with a pulsing / amplitude indicator while listening.
- The live partial transcript as it grows.
- A "Tap to stop" affordance; auto-stops on the engine's end-of-speech.
- Error / permission-denied / no-speech states with a retry affordance.
- Returns the **final transcript string** (or `null` if cancelled) to the
  caller via `Navigator.pop`.

Follows the async-feedback and contrast conventions in `CLAUDE.md`:

- Busy state is a reactive flag; the mic control is disabled + re-entrancy
  guarded while a start/stop transition is in flight.
- All surfaces use `context.scheme.*` / `colorScheme.*` — no hardcoded
  `Colors.white` / `grey.shadeX`; visible in both light and dark mode.
- The spinner/indicator uses an on-surface-appropriate colour (not bare
  `primary` on a maroon surface).

### 3. `GlobalDocumentSearchDelegate` — the integration point

Add one `IconButton(Icons.mic)` to `buildActions`, placed before the existing
clear (×) button. On tap:

1. `await VoiceSearchSheet.show(context)` (which internally ensures init +
   permission and runs the listen loop).
2. If it returns a non-empty transcript `t`:
   - Set `query = t` (this is a gesture handler, outside the build phase, so
     the assignment is synchronous — consistent with the existing clear button).
   - `showResults(context)` so the grouped results render for the dictated text.
3. If it returns `null` / empty, leave the field untouched.

The mic button is always shown (unlike the query-dependent clear button). No
change to the fan-out search, scope chips, permission gating, or result
rendering — voice only produces the query string that the existing pipeline
already consumes.

## Data flow

```
mic tap (buildActions)
  └─ VoiceSearchSheet.show(context)
       ├─ VoiceSearchService.ensureInitialized()   → permission + availability
       ├─ startListening(onPartial→live text, onFinal→result, onDone→pop)
       └─ returns final transcript (or null)
  └─ query = transcript ; showResults(context)
       └─ existing _search(query, scope) fan-out → grouped results (unchanged)
```

## Platform configuration

**Android** (`android/app/src/main/AndroidManifest.xml`)

- Add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`.
  (`INTERNET` already present. Bluetooth-headset permissions from the package
  README are omitted — the target is a handheld scanner using the built-in mic;
  they can be added later if BT-mic dictation is ever required.)
- Extend the existing `<queries>` block with the `RecognitionService` intent
  (required on Android SDK 30+ to see the on-device recognizer):
  ```xml
  <intent>
      <action android:name="android.speech.RecognitionService" />
  </intent>
  ```
- `minSdk` is `flutter.minSdkVersion`; the package needs ≥21. Verify the
  resolved Flutter minSdk is ≥21 during implementation (it is on current
  Flutter). No change expected.

**iOS** (`ios/Runner/Info.plist`) — for parity so an iOS build does not crash:

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

**pubspec.yaml**

- Add `speech_to_text: ^7.4.0`.

## Error handling

`VoiceSearchService` never throws to the UI. Each failure maps to a sheet state:

| Condition | Behaviour |
|---|---|
| Permission denied | Sheet shows "Microphone permission needed" + a settings/retry hint; returns `null`; query untouched. |
| No recognizer available (`initialize` false) | Sheet shows "Voice input isn't available on this device"; returns `null`. |
| Engine error mid-listen (`onError`) | Sheet shows "Didn't catch that — try again" + retry; keeps any partial captured, but only commits on an explicit stop/final. |
| No speech / empty final | Returns `null`; query untouched (no empty search fired). |
| User cancels (back / tap outside) | `cancel()` the recognizer; returns `null`. |

The delegate only mutates `query` on a non-empty transcript, so every failure
path is a no-op for the search field.

## Testing

Unit (no live recognizer, no platform channels):

- `resolveLocaleId` — device locale supported → picks it; unsupported →
  `en_GB`; no en_GB → `en_US`; none → `null`.
- `VoiceSearchService` with a mock `SpeechToText`: `ensureInitialized` returns
  the plugin's availability; a `false` init does not throw; partial/final
  callbacks are routed; `stop`/`cancel` delegate through.

Widget:

- `VoiceSearchSheet` renders listening state, shows partial text as it updates,
  surfaces the permission-denied and no-recognizer states, and pops the final
  transcript. Driven with an injected fake service (the sheet takes the service
  as a constructor arg, defaulting to `Get.find`, like the existing delegate's
  `_providedService` pattern).
- `GlobalDocumentSearchDelegate`: tapping the mic action invokes the sheet; a
  returned transcript sets `query` and triggers results; a `null` return leaves
  `query` empty. Uses a fake sheet/service seam so no recognizer is needed.

Manual on-device smoke (Android handheld): permission prompt first run;
dictation fills the field and shows results; cancel is a no-op; denied
permission shows the message; result tap still opens the document.

## Files

**New**

- `lib/app/data/services/voice_search_service.dart` — service + `resolveLocaleId`.
- `lib/app/modules/global_widgets/voice_search_sheet.dart` — listening UI.
- `test/unit/voice_search_service_test.dart`
- `test/widget/voice_search_sheet_test.dart`
- (delegate mic behaviour added to a delegate widget test — new or existing file)

**Modified**

- `lib/app/modules/global_widgets/global_document_search_delegate.dart` — mic action.
- `pubspec.yaml` — `speech_to_text` dependency.
- `android/app/src/main/AndroidManifest.xml` — permission + query.
- `ios/Runner/Info.plist` — two usage-description keys.

## Versioning

New user-facing capability (voice input in global search) → **MINOR** semver
bump per `docs/versioning_conventions.md`, `versionCode +1`. Confirm with the
diff-driven classifier at release time; do not default to PATCH.
