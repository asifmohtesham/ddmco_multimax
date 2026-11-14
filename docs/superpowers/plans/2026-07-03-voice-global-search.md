# Voice Search for Global Document Search — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a microphone button to the dashboard global document search overlay that dictates the query on-device, fills the search field, and shows the normal grouped results.

**Architecture:** A `VoiceSearchEngine` interface (concrete `SttVoiceSearchEngine` wraps the `speech_to_text` plugin; a pure `resolveLocaleId` picks the recognition locale) is driven by a `VoiceSearchSheet` bottom sheet that returns the final transcript. `GlobalDocumentSearchDelegate` gains one mic action that shows the sheet and, on a non-empty transcript, sets `query` + calls `showResults`. The existing fan-out search pipeline is unchanged — voice only produces the query string it already consumes.

**Tech Stack:** Flutter, GetX, `speech_to_text` ^7.4.0 (native Android `SpeechRecognizer`), `flutter_test`.

## Global Constraints

Copied verbatim from the spec; every task's requirements implicitly include these.

- **Dependency:** add `speech_to_text: ^7.4.0`. Do **not** add `permission_handler` — the plugin self-manages the runtime mic/Bluetooth permission, mirroring `mobile_scanner`/`image_picker`.
- **Android minSdk** must be ≥ 21 (`speech_to_text` floor). Project uses `flutter.minSdkVersion` (already ≥21) — verify, do not change unless below 21.
- **Placement:** global document search overlay (`GlobalDocumentSearchDelegate`) **only**. Do not touch `DocTypeSearchDelegate` or the 11 list screens.
- **On final transcript:** fill `query` + `showResults`. **Never auto-open** a document. On empty/null transcript, leave `query` untouched (fire no search).
- **Locale:** device locale if the recognizer supports it, else `en_GB`, else `en_US`, else engine default (`null`).
- **Bluetooth mic dictation** (AirPods/earbuds) is in scope: declare `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_CONNECT`.
- **Theming (CLAUDE.md):** never hardcode surface/ink colours. Use `context.scheme.*` (`bg`, `text`, `textMuted`, `textSubtle`, `subtle`, `primary`, `onPrimary`) / `colorScheme.*`. Must be legible in light **and** dark mode. A progress/mic indicator on a coloured surface uses an on-surface-appropriate colour, never bare `primary` on maroon.
- **Async feedback (CLAUDE.md):** the mic/stop control shows immediate feedback, is disabled + re-entrancy-guarded while a start/stop transition is in flight, and actually repaints.
- **Versioning:** new user-facing capability → **MINOR** semver bump, `versionCode +1`, at release time via `docs/versioning_conventions.md`. Not part of these tasks; do not bump here.
- **Every commit** ends with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- The full suite must stay green (baseline: **722 passing**). Run `flutter test` before each commit.

## File Structure

**New**

- `lib/app/data/services/voice_search_engine.dart` — `VoiceEngineState` enum, `VoiceSearchEngine` abstract interface, pure `resolveLocaleId`.
- `lib/app/data/services/stt_voice_search_engine.dart` — `SttVoiceSearchEngine` wrapping `speech_to_text`.
- `lib/app/modules/global_widgets/voice_search_sheet.dart` — `VoiceSearchSheet` listening UI + `show()`.
- `test/unit/voice_search_locale_test.dart` — `resolveLocaleId` tests.
- `test/unit/voice_search_delegate_query_test.dart` — `voiceQueryUpdate` tests.
- `test/widget/voice_search_sheet_test.dart` — sheet widget tests with a fake engine.

**Modified**

- `pubspec.yaml` — add dependency.
- `android/app/src/main/AndroidManifest.xml` — permissions + `RecognitionService` query.
- `ios/Runner/Info.plist` — two usage-description keys.
- `lib/app/modules/global_widgets/global_document_search_delegate.dart` — mic action + `voiceQueryUpdate` static + injectable voice prompt.

---

## Task 1: Dependency + platform configuration

Wires the package and OS permissions. No behaviour change yet; the deliverable is a project that builds with the plugin present and permissions declared.

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`

**Interfaces:**
- Consumes: nothing.
- Produces: `speech_to_text` importable; `RECORD_AUDIO`/Bluetooth permissions + `RecognitionService` query available at runtime.

- [ ] **Step 1: Add the dependency to `pubspec.yaml`**

In the `dependencies:` block, after the `cached_network_image: ^3.4.1` line, add:

```yaml
  speech_to_text: ^7.4.0
```

- [ ] **Step 2: Install and verify it resolves**

Run: `flutter pub get`
Expected: `Got dependencies!` with no version-solve error mentioning `speech_to_text`.

- [ ] **Step 3: Declare Android permissions + recognizer query**

In `android/app/src/main/AndroidManifest.xml`:

Replace this line:

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
```

with:

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

Then, inside the existing `<queries>` block (which already contains the `PROCESS_TEXT` intent), add a second `<intent>` so the block reads:

```xml
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>
```

- [ ] **Step 4: Declare iOS usage descriptions**

In `ios/Runner/Info.plist`, add these two keys inside the top-level `<dict>` (anywhere among the existing keys):

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Microphone access is used for voice search.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Speech recognition is used to turn your voice into a search query.</string>
```

- [ ] **Step 5: Verify analyze + full suite still green**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!` (722 passing — no behaviour changed).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "chore(voice-search): add speech_to_text dep + audio/bluetooth permissions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Engine seam + locale resolution

Defines the abstraction the sheet depends on and the pure locale-picking logic. TDD covers `resolveLocaleId`; the enum + interface are consumed by Tasks 3–4.

**Files:**
- Create: `lib/app/data/services/voice_search_engine.dart`
- Test: `test/unit/voice_search_locale_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum VoiceEngineState { listening, done, notAvailable, permissionDenied, error }`
  - `abstract class VoiceSearchEngine` with:
    - `Future<void> start({required void Function(String text, bool isFinal) onResult, required void Function(VoiceEngineState state) onState})`
    - `Future<void> stop()`
    - `Future<void> cancel()`
  - `String? resolveLocaleId(List<String> availableIds, String deviceLocaleId)` — top-level pure function. Returns the matching available id (original casing), or `null` for the engine default.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/voice_search_locale_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/voice_search_engine.dart';

void main() {
  group('resolveLocaleId', () {
    const available = ['en_US', 'en_GB', 'fr_FR', 'ur_PK'];

    test('picks the device locale when the recognizer supports it', () {
      expect(resolveLocaleId(available, 'fr_FR'), 'fr_FR');
    });

    test('normalizes separator/casing when matching the device locale', () {
      // Device tags often arrive hyphenated (en-GB) and differently cased.
      expect(resolveLocaleId(available, 'en-gb'), 'en_GB');
    });

    test('falls back to en_GB when the device locale is unsupported', () {
      expect(resolveLocaleId(available, 'de_DE'), 'en_GB');
    });

    test('falls back to en_US when en_GB is absent', () {
      expect(resolveLocaleId(const ['en_US', 'fr_FR'], 'de_DE'), 'en_US');
    });

    test('returns null (engine default) when no English is available', () {
      expect(resolveLocaleId(const ['fr_FR', 'ur_PK'], 'de_DE'), isNull);
    });

    test('returns null when the available list is empty', () {
      expect(resolveLocaleId(const [], 'en_GB'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/voice_search_locale_test.dart`
Expected: FAIL — `voice_search_engine.dart` / `resolveLocaleId` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/app/data/services/voice_search_engine.dart`:

```dart
/// The listening lifecycle the [VoiceSearchSheet] reacts to.
enum VoiceEngineState {
  /// Actively capturing audio.
  listening,

  /// The recognizer finished a session (final result delivered or timed out).
  done,

  /// No speech recognizer is available on this device.
  notAvailable,

  /// The user denied (or has not granted) the microphone permission.
  permissionDenied,

  /// A recoverable engine error occurred mid-session.
  error,
}

/// Small, mockable surface over a speech-to-text backend.
///
/// Kept free of any `speech_to_text` types so the sheet and its widget tests
/// depend only on this interface (see [SttVoiceSearchEngine] for the concrete
/// plugin-backed implementation).
abstract class VoiceSearchEngine {
  /// Initializes (idempotent), resolves the locale, and begins listening.
  ///
  /// [onResult] receives the recognized text and whether it is the final
  /// result. [onState] receives lifecycle transitions. Implementations must
  /// never throw — failures are reported through [onState].
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VoiceEngineState state) onState,
  });

  /// Gracefully finishes the session, allowing a final result to arrive.
  Future<void> stop();

  /// Discards the session without producing a final result.
  Future<void> cancel();
}

/// Picks the recognition locale id from the recognizer's [availableIds].
///
/// Preference order: the device locale (matched case-insensitively and
/// tolerant of `-`/`_` separators), then `en_GB`, then `en_US`, then `null`
/// (let the engine use its own default).
String? resolveLocaleId(List<String> availableIds, String deviceLocaleId) {
  String norm(String s) => s.toLowerCase().replaceAll('-', '_');

  final wanted = norm(deviceLocaleId);
  for (final id in availableIds) {
    if (norm(id) == wanted) return id;
  }
  for (final id in availableIds) {
    if (norm(id) == 'en_gb') return id;
  }
  for (final id in availableIds) {
    if (norm(id) == 'en_us') return id;
  }
  return null;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/voice_search_locale_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/voice_search_engine.dart test/unit/voice_search_locale_test.dart
git commit -m "feat(voice-search): engine interface + locale resolution

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `SttVoiceSearchEngine` (plugin-backed)

Concrete engine that wraps `speech_to_text`. It touches platform channels, so it is verified by `flutter analyze` + on-device smoke (Task 6), not a unit test — the testable logic (`resolveLocaleId`) already lives in Task 2 and the state machine is exercised via the fake in Task 4.

**Files:**
- Create: `lib/app/data/services/stt_voice_search_engine.dart`

**Interfaces:**
- Consumes: `VoiceSearchEngine`, `VoiceEngineState`, `resolveLocaleId` (Task 2); `SpeechToText`, `SpeechRecognitionResult`, `SpeechRecognitionError`, `SpeechListenOptions`, `LocaleName` from `speech_to_text`.
- Produces: `class SttVoiceSearchEngine implements VoiceSearchEngine` with a default const-free constructor `SttVoiceSearchEngine({SpeechToText? speech, String? deviceLocaleId})`.

- [ ] **Step 1: Write the implementation**

Create `lib/app/data/services/stt_voice_search_engine.dart`:

```dart
import 'dart:ui' as ui;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:multimax/app/data/services/voice_search_engine.dart';

/// [VoiceSearchEngine] backed by the on-device `speech_to_text` plugin.
class SttVoiceSearchEngine implements VoiceSearchEngine {
  SttVoiceSearchEngine({SpeechToText? speech, String? deviceLocaleId})
      : _speech = speech ?? SpeechToText(),
        _deviceLocaleId = deviceLocaleId ?? _platformLocaleId();

  final SpeechToText _speech;
  final String _deviceLocaleId;

  bool _permissionDenied = false;

  static String _platformLocaleId() {
    final l = ui.PlatformDispatcher.instance.locale;
    return l.countryCode == null || l.countryCode!.isEmpty
        ? l.languageCode
        : '${l.languageCode}_${l.countryCode}';
  }

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VoiceEngineState state) onState,
  }) async {
    _permissionDenied = false;

    final available = await _speech.initialize(
      onError: (SpeechRecognitionError e) {
        // 'error_permission' / 'error_speech_timeout' etc. Permission errors
        // get their own state so the sheet can show the right message.
        if (e.errorMsg.toLowerCase().contains('permission')) {
          _permissionDenied = true;
          onState(VoiceEngineState.permissionDenied);
        } else {
          onState(VoiceEngineState.error);
        }
      },
      onStatus: (String status) {
        // Plugin emits 'listening', 'notListening', 'done'.
        if (status == 'done' || status == 'notListening') {
          onState(VoiceEngineState.done);
        }
      },
    );

    if (!available) {
      onState(_permissionDenied
          ? VoiceEngineState.permissionDenied
          : VoiceEngineState.notAvailable);
      return;
    }

    final locales = await _speech.locales();
    final localeId =
        resolveLocaleId(locales.map((l) => l.localeId).toList(), _deviceLocaleId);

    onState(VoiceEngineState.listening);
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: localeId,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/app/data/services/stt_voice_search_engine.dart`
Expected: `No issues found!`

- [ ] **Step 3: Verify the full suite is still green**

Run: `flutter test`
Expected: `All tests passed!` (still 728: 722 baseline + 6 from Task 2).

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/services/stt_voice_search_engine.dart
git commit -m "feat(voice-search): speech_to_text-backed engine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `VoiceSearchSheet` listening UI

The bottom sheet that drives an engine, shows live partial text + state, and returns the final transcript. Widget-tested with a fake engine (no plugin, no platform channels).

**Files:**
- Create: `lib/app/modules/global_widgets/voice_search_sheet.dart`
- Test: `test/widget/voice_search_sheet_test.dart`

**Interfaces:**
- Consumes: `VoiceSearchEngine`, `VoiceEngineState` (Task 2); `context.scheme` from `app_theme.dart`.
- Produces:
  - `class VoiceSearchSheet extends StatefulWidget` with `final VoiceSearchEngine engine;` (required).
  - `static Future<String?> show(BuildContext context, {VoiceSearchEngine? engine})` — opens the modal sheet, defaulting the engine to `SttVoiceSearchEngine()`; resolves to the final transcript or `null`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/widget/voice_search_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/voice_search_engine.dart';
import 'package:multimax/app/modules/global_widgets/voice_search_sheet.dart';

/// Test double: records callbacks so the test can drive engine events, and
/// exposes them for assertions on stop/cancel.
class FakeVoiceSearchEngine implements VoiceSearchEngine {
  void Function(String text, bool isFinal)? onResult;
  void Function(VoiceEngineState state)? onState;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    required void Function(VoiceEngineState state) onState,
  }) async {
    this.onResult = onResult;
    this.onState = onState;
    onState(VoiceEngineState.listening);
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;
}

Future<String?> _showSheet(WidgetTester tester, FakeVoiceSearchEngine fake) async {
  String? returned;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              returned = await VoiceSearchSheet.show(context, engine: fake);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return null; // caller reads `returned` after driving events; see tests
}

void main() {
  testWidgets('shows the live partial transcript while listening',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    await _showSheet(tester, fake);

    fake.onResult!('blue str', false);
    await tester.pump();

    expect(find.text('blue str'), findsOneWidget);
  });

  testWidgets('a final result pops the sheet with the transcript',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    String? returned;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                returned = await VoiceSearchSheet.show(context, engine: fake);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    fake.onResult!('blue strap', true);
    await tester.pumpAndSettle();

    expect(returned, 'blue strap');
  });

  testWidgets('permission-denied state shows a message and does not crash',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    await _showSheet(tester, fake);

    fake.onState!(VoiceEngineState.permissionDenied);
    await tester.pump();

    expect(find.textContaining('permission'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notAvailable state shows the unavailable message',
      (tester) async {
    final fake = FakeVoiceSearchEngine();
    await _showSheet(tester, fake);

    fake.onState!(VoiceEngineState.notAvailable);
    await tester.pump();

    expect(find.textContaining("isn't available"), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/voice_search_sheet_test.dart`
Expected: FAIL — `voice_search_sheet.dart` / `VoiceSearchSheet` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/app/modules/global_widgets/voice_search_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/stt_voice_search_engine.dart';
import 'package:multimax/app/data/services/voice_search_engine.dart';

/// Modal bottom sheet that captures one voice dictation and returns the final
/// transcript (or `null` if cancelled / unavailable).
class VoiceSearchSheet extends StatefulWidget {
  const VoiceSearchSheet({super.key, required this.engine});

  final VoiceSearchEngine engine;

  /// Opens the sheet and resolves to the recognized transcript, or `null`.
  static Future<String?> show(BuildContext context, {VoiceSearchEngine? engine}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceSearchSheet(engine: engine ?? SttVoiceSearchEngine()),
    );
  }

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet> {
  VoiceEngineState _state = VoiceEngineState.listening;
  String _text = '';
  bool _busy = false; // re-entrancy guard for stop().
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    await widget.engine.start(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _text = text);
        if (isFinal) _finish(text);
      },
      onState: (state) {
        if (!mounted) return;
        setState(() => _state = state);
        if (state == VoiceEngineState.done) {
          _finish(_text); // engine ended; commit whatever we have
        }
      },
    );
  }

  void _finish(String text) {
    if (_closed) return;
    _closed = true;
    final trimmed = text.trim();
    Navigator.of(context).pop(trimmed.isEmpty ? null : trimmed);
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.engine.stop();
    // A final result / done state will pop; nothing else to do here.
  }

  Future<void> _cancel() async {
    await widget.engine.cancel();
    if (!_closed && mounted) {
      _closed = true;
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          24, 20, 24, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusIcon(scheme),
            const SizedBox(height: 16),
            Text(
              _headline(),
              style: TextStyle(color: scheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_isListening)
              Text(
                _text.isEmpty ? '…' : _text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                _detail(),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.text, fontSize: 15),
              ),
            const SizedBox(height: 20),
            _actionRow(scheme),
          ],
        ),
      ),
    );
  }

  bool get _isListening => _state == VoiceEngineState.listening;

  Widget _statusIcon(AppScheme scheme) {
    final bad = _state == VoiceEngineState.permissionDenied ||
        _state == VoiceEngineState.notAvailable ||
        _state == VoiceEngineState.error;
    final color = bad ? Theme.of(context).colorScheme.error : scheme.primary;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        shape: BoxShape.circle,
      ),
      child: Icon(bad ? Icons.mic_off : Icons.mic, color: color, size: 34),
    );
  }

  String _headline() {
    switch (_state) {
      case VoiceEngineState.listening:
        return 'Listening…';
      case VoiceEngineState.done:
        return 'Done';
      case VoiceEngineState.permissionDenied:
        return 'Microphone blocked';
      case VoiceEngineState.notAvailable:
        return 'Voice unavailable';
      case VoiceEngineState.error:
        return 'Try again';
    }
  }

  String _detail() {
    switch (_state) {
      case VoiceEngineState.permissionDenied:
        return 'Microphone permission is needed. Enable it in Settings and try again.';
      case VoiceEngineState.notAvailable:
        return "Voice input isn't available on this device.";
      case VoiceEngineState.error:
        return "Didn't catch that. Tap the mic to try again.";
      default:
        return '';
    }
  }

  Widget _actionRow(AppScheme scheme) {
    if (_isListening) {
      return FilledButton.icon(
        onPressed: _busy ? null : _stop,
        icon: _busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                ),
              )
            : const Icon(Icons.stop, size: 18),
        label: const Text('Done'),
      );
    }
    return TextButton(
      onPressed: _cancel,
      child: const Text('Close'),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widget/voice_search_sheet_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: `All tests passed!` (732: 728 + 4).

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/voice_search_sheet.dart test/widget/voice_search_sheet_test.dart
git commit -m "feat(voice-search): listening bottom sheet

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wire the mic into `GlobalDocumentSearchDelegate`

Adds the mic action and the pure `voiceQueryUpdate` helper. The decision logic is unit-tested; the `query =` / `showResults` glue and the sheet call are verified by the sheet tests + on-device smoke.

**Files:**
- Modify: `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- Test: `test/unit/voice_search_delegate_query_test.dart`

**Interfaces:**
- Consumes: `VoiceSearchSheet.show` (Task 4).
- Produces:
  - `static String? voiceQueryUpdate(String? transcript)` on `GlobalDocumentSearchDelegate` — returns the trimmed transcript when it is non-empty, else `null`.
  - Constructor gains `Future<String?> Function(BuildContext context)? voicePrompt` (defaults to `VoiceSearchSheet.show`) so the wiring is injectable.

- [ ] **Step 1: Write the failing unit test**

Create `test/unit/voice_search_delegate_query_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';

void main() {
  group('GlobalDocumentSearchDelegate.voiceQueryUpdate', () {
    test('returns the trimmed transcript when non-empty', () {
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate('  blue strap '),
          'blue strap');
    });

    test('returns null for null', () {
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate(null), isNull);
    });

    test('returns null for empty / whitespace-only', () {
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate(''), isNull);
      expect(GlobalDocumentSearchDelegate.voiceQueryUpdate('   '), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/voice_search_delegate_query_test.dart`
Expected: FAIL — `voiceQueryUpdate` not defined.

- [ ] **Step 3: Add the import, constructor param, static helper, and mic action**

In `lib/app/modules/global_widgets/global_document_search_delegate.dart`:

Add to the imports (after the `selectable_filter_chip.dart` import):

```dart
import 'package:multimax/app/modules/global_widgets/voice_search_sheet.dart';
```

Replace the constructor:

```dart
  GlobalDocumentSearchDelegate({GlobalSearchService? service})
      : _providedService = service;
```

with:

```dart
  GlobalDocumentSearchDelegate({
    GlobalSearchService? service,
    Future<String?> Function(BuildContext context)? voicePrompt,
  })  : _providedService = service,
        _voicePrompt = voicePrompt ?? VoiceSearchSheet.show;

  /// Opens the voice dictation UI and yields the transcript. Injectable so
  /// tests can drive the wiring without a live recognizer.
  final Future<String?> Function(BuildContext context) _voicePrompt;

  /// The query update implied by a raw voice [transcript]: the trimmed text
  /// when it carries content, otherwise `null` (leave the field untouched).
  static String? voiceQueryUpdate(String? transcript) {
    final t = transcript?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
```

Replace `buildActions`:

```dart
  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear search',
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];
```

with:

```dart
  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.mic),
          tooltip: 'Search by voice',
          onPressed: () => _startVoiceSearch(context),
        ),
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear search',
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];

  Future<void> _startVoiceSearch(BuildContext context) async {
    final transcript = await _voicePrompt(context);
    if (!context.mounted) return;
    final update = voiceQueryUpdate(transcript);
    if (update == null) return; // no speech → leave the field untouched
    query = update;
    showResults(context);
  }
```

- [ ] **Step 4: Run the unit test to verify it passes**

Run: `flutter test test/unit/voice_search_delegate_query_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze + the existing delegate tests still pass**

Run: `flutter analyze lib/app/modules/global_widgets/global_document_search_delegate.dart`
Expected: `No issues found!`

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: PASS (the 4 existing delegate tests — unchanged behaviour).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: `All tests passed!` (735: 732 + 3).

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/global_widgets/global_document_search_delegate.dart test/unit/voice_search_delegate_query_test.dart
git commit -m "feat(voice-search): mic action in global document search

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: On-device smoke verification

Manual verification on an Android handheld — the plugin/permission/BT paths cannot be exercised by the widget tests. Fold any fixes discovered here back into the relevant task's files.

**Files:** none (verification only).

- [ ] **Step 1: Build + install a debug build on the device**

Run: `flutter run -d <device_id>` (see `.vscode/launch.json` for the configured device).
Expected: app launches with no manifest/merger errors.

- [ ] **Step 2: First-run permission**

Open Dashboard → tap the search icon → tap the mic. Expected: the OS microphone permission prompt appears the first time. Grant it.

- [ ] **Step 3: Dictation fills the field + shows results**

Say an item/customer name. Expected: live partial text appears in the sheet; on finish the sheet closes, the search field is filled with the transcript, and the grouped results render. Tapping a result opens that document (unchanged navigation).

- [ ] **Step 4: Cancel is a no-op**

Open the mic, then Close / tap outside before speaking. Expected: the search field is unchanged and no search fires.

- [ ] **Step 5: Denied permission path**

Revoke the mic permission in system settings, reopen the mic. Expected: the "Microphone blocked" message shows; the field is untouched.

- [ ] **Step 6: Bluetooth headset mic**

Pair a Bluetooth headset (AirPods / earbuds), make it the active audio route, reopen the mic, and dictate. Expected: the `BLUETOOTH_CONNECT` prompt is handled (Android 12+) and dictation captures from the BT mic.

- [ ] **Step 7: Dark mode contrast**

Switch the app to dark mode (drawer → Theme) and repeat Step 3. Expected: the sheet surface, headline, and transcript text are all legible; the mic indicator is visible (not invisible maroon-on-maroon).

- [ ] **Step 8: Final full-suite gate**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!` (735).

---

## Self-Review

**Spec coverage**

- Placement (global overlay only) → Task 5 (mic added to `GlobalDocumentSearchDelegate` only; `DocTypeSearchDelegate` untouched). ✓
- On-device `speech_to_text` → Task 1 (dep) + Task 3 (engine). ✓
- Fill + show results, no auto-open → Task 5 `_startVoiceSearch` sets `query` + `showResults`, never navigates. ✓
- Locale device→en_GB→en_US→null → Task 2 `resolveLocaleId` (+ tests). ✓
- BT mic dictation → Task 1 Bluetooth permissions; Task 6 Step 6 smoke. ✓
- Self-managed permission, no `permission_handler` → Global Constraints + Task 1 (only manifest perms added). ✓
- Listening UI with live partial + states → Task 4. ✓
- Error/permission/no-speech states → Task 4 (`_headline`/`_detail`, states) + Task 3 (state mapping). ✓
- Theming + async feedback conventions → Task 4 (`context.scheme`, `onPrimary` spinner, `_busy` guard). ✓
- Android manifest + query + iOS Info.plist → Task 1. ✓
- Tests (unit locale, unit query, widget sheet) → Tasks 2, 4, 5. ✓
- MINOR version bump → Global Constraints (deferred to release, correctly not a task). ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result. ✓

**Type consistency:** `VoiceSearchEngine.start({onResult(String,bool), onState(VoiceEngineState)})`, `stop()`, `cancel()` are identical across Task 2 (definition), Task 3 (`SttVoiceSearchEngine`), Task 4 (`FakeVoiceSearchEngine` + sheet). `VoiceEngineState` enum members (`listening/done/notAvailable/permissionDenied/error`) match across Tasks 2–4. `resolveLocaleId(List<String>, String)` signature matches Task 2 test + Task 3 call. `voiceQueryUpdate(String?)→String?` matches Task 5 test + delegate call. `VoiceSearchSheet.show(context, {engine})→Future<String?>` matches Task 4 test, its impl, and the Task 5 default `_voicePrompt`. ✓
