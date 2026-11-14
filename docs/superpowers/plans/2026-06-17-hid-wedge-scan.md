# HID Keyboard-Wedge Scan Support (Netum C750) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a Netum C750 in HID keyboard mode reach every existing scan-driven flow by funnelling assembled key bursts into `DataWedgeService.scannedCode`, with no changes to controllers, mixins, `BarcodeInputWidget`, the camera path, or the native layer.

**Architecture:** One sink, two sources. A pure-Dart `WedgeBurstAssembler` turns timed key events into a barcode string using timing + an Enter terminator. A thin `HidWedgeService` (GetxService) registers a global `HardwareKeyboard` handler that drives the assembler and, on a completed burst, calls a new `DataWedgeService.injectScan`. Downstream behaviour is identical to a Zebra scan because `injectScan` reuses the existing queue/debounce.

**Tech Stack:** Flutter (Dart `^3.8.1`), GetX (`get ^4.7.2`), `flutter_test`. `HardwareKeyboard` / `KeyEvent` are Flutter core — no new dependencies.

## Global Constraints

- No new package dependencies (`HardwareKeyboard` is Flutter core).
- No changes to `android/app/src/main/kotlin/com/ddmco/multimax/MainActivity.kt`, the Android manifest, or app permissions.
- No changes to any controller, mixin, `BarcodeInputWidget`, or the camera path.
- Global services are registered in `lib/main.dart` with `permanent: true` (project convention).
- Terminator is **Enter / CR only** (plus numpad Enter).
- Burst detection threshold: `maxGapMs = 50` (inter-key gap, milliseconds).
- Pure-logic tests live in `test/unit/` using `flutter_test` (`group`/`test`).
- Branch for this work: `feature/hid-wedge-scan` (already checked out).

---

### Task 1: `WedgeBurstAssembler` (pure-Dart timing state machine)

**Files:**
- Create: `lib/app/data/services/wedge_burst_assembler.dart`
- Test: `test/unit/wedge_burst_assembler_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class WedgeBurstAssembler`
  - `WedgeBurstAssembler({int maxGapMs = 50})`
  - `bool addChar(String char, int timestampMs)` — appends to the current burst and returns `true` when the char is in cadence (gap `< maxGapMs`); when the gap is `>= maxGapMs` (or it is the first char) it starts a fresh burst with this char and returns `false`.
  - `String? terminate(int timestampMs)` — returns the buffered code when the buffer is non-empty **and** the gap from the last char is `< maxGapMs`, else `null`; always clears state.
  - `void reset()` — clears the buffer and last-timestamp.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/wedge_burst_assembler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/wedge_burst_assembler.dart';

void main() {
  group('WedgeBurstAssembler', () {
    test('tight burst then Enter returns the full code', () {
      final a = WedgeBurstAssembler();
      expect(a.addChar('6', 0), isFalse); // first char of a burst
      expect(a.addChar('9', 10), isTrue);
      expect(a.addChar('2', 20), isTrue);
      expect(a.addChar('8', 30), isTrue);
      expect(a.terminate(40), '6928');
    });

    test('an out-of-cadence gap resets the buffer', () {
      final a = WedgeBurstAssembler();
      a.addChar('1', 0);
      a.addChar('2', 10);
      expect(a.addChar('X', 200), isFalse); // gap 190 >= 50 -> new burst
      expect(a.addChar('Y', 210), isTrue);
      expect(a.terminate(220), 'XY');
    });

    test('slow human typing then Enter returns null', () {
      final a = WedgeBurstAssembler();
      a.addChar('a', 0);
      a.addChar('b', 100); // resets to "b"
      a.addChar('c', 200); // resets to "c"
      expect(a.terminate(300), isNull); // terminator gap 100 >= 50
    });

    test('terminate with empty buffer returns null', () {
      final a = WedgeBurstAssembler();
      expect(a.terminate(0), isNull);
    });

    test('gap exactly at threshold resets (boundary is inclusive)', () {
      final a = WedgeBurstAssembler();
      a.addChar('1', 0);
      expect(a.addChar('2', 50), isFalse); // gap == maxGapMs -> reset
      expect(a.terminate(60), '2');
    });

    test('hyphenated and EAN-8 payloads pass through verbatim', () {
      final a = WedgeBurstAssembler();
      const code = 'SHIPMENT-24-AB12-001';
      var ts = 0;
      for (final ch in code.split('')) {
        a.addChar(ch, ts);
        ts += 5;
      }
      expect(a.terminate(ts), code);
    });

    test('reset discards an in-progress buffer', () {
      final a = WedgeBurstAssembler();
      a.addChar('1', 0);
      a.addChar('2', 10);
      a.reset();
      expect(a.terminate(20), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/wedge_burst_assembler_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'multimax' ... wedge_burst_assembler.dart` / target of URI doesn't exist (file not created yet).

- [ ] **Step 3: Write the implementation**

Create `lib/app/data/services/wedge_burst_assembler.dart`:

```dart
/// Pure-Dart timing state machine that assembles HID keyboard-wedge bursts
/// into a single barcode string.
///
/// Feed printable characters via [addChar] and the terminator (Enter) via
/// [terminate]. The machine owns ALL timing state — callers never recompute
/// gaps themselves; they use the bool returned by [addChar] for their
/// consume decision so the consume rule and the buffer-reset rule cannot
/// diverge.
///
/// A burst is "in cadence" while consecutive keystrokes arrive within
/// [maxGapMs] of each other. A gap >= [maxGapMs] starts a fresh burst.
class WedgeBurstAssembler {
  WedgeBurstAssembler({this.maxGapMs = 50});

  /// Maximum inter-key gap (ms) for two keystrokes to count as one burst.
  final int maxGapMs;

  final StringBuffer _buffer = StringBuffer();
  int? _lastTs;

  /// Appends [char] to the current burst.
  ///
  /// Returns `true` when [char] is in cadence (a continuation of the current
  /// burst). Returns `false` when the gap since the last key is `>= maxGapMs`
  /// or this is the first key — in that case a fresh burst is started holding
  /// only [char].
  bool addChar(String char, int timestampMs) {
    final last = _lastTs;
    _lastTs = timestampMs;

    if (last == null || (timestampMs - last) >= maxGapMs) {
      _buffer
        ..clear()
        ..write(char);
      return false;
    }

    _buffer.write(char);
    return true;
  }

  /// Finalises the current burst.
  ///
  /// Returns the assembled code when the buffer is non-empty AND the gap from
  /// the last char to this terminator is `< maxGapMs`; otherwise `null`.
  /// Always clears state.
  String? terminate(int timestampMs) {
    final last = _lastTs;
    final inCadence =
        _buffer.isNotEmpty && last != null && (timestampMs - last) < maxGapMs;
    final code = inCadence ? _buffer.toString() : null;
    reset();
    return code;
  }

  /// Clears the buffer and last-timestamp.
  void reset() {
    _buffer.clear();
    _lastTs = null;
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/wedge_burst_assembler_test.dart`
Expected: PASS — all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/wedge_burst_assembler.dart test/unit/wedge_burst_assembler_test.dart
git commit -m "feat(scan): add WedgeBurstAssembler timing state machine"
```

---

### Task 2: `DataWedgeService.injectScan` (second source into the existing sink)

**Files:**
- Modify: `lib/app/data/services/data_wedge_service.dart` (add one public method near `_enqueueScan`, around line 89)
- Test: `test/unit/data_wedge_inject_scan_test.dart`

**Interfaces:**
- Consumes: existing private `void _enqueueScan(String code)` and `final scannedCode = ''.obs` in `DataWedgeService`.
- Produces: `void DataWedgeService.injectScan(String code)` — forwards to `_enqueueScan`, inheriting the queue, the 800 ms hold/clear cycle, and the existing empty-code guard.

- [ ] **Step 1: Write the failing test**

Create `test/unit/data_wedge_inject_scan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

void main() {
  // Construct the service directly (no Get lifecycle) so onInit / the native
  // EventChannel listener never runs.
  group('DataWedgeService.injectScan', () {
    test('sets scannedCode synchronously then clears after the hold', () async {
      final dw = DataWedgeService();

      dw.injectScan('6928804014662');
      // _processQueue runs synchronously up to its first await, so the value
      // is visible immediately.
      expect(dw.scannedCode.value, '6928804014662');

      // Drain the 800ms hold + 100ms gap so no timer is left pending.
      await Future.delayed(const Duration(milliseconds: 950));
      expect(dw.scannedCode.value, '');
    });

    test('ignores an empty code', () {
      final dw = DataWedgeService();
      dw.injectScan('');
      expect(dw.scannedCode.value, '');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/data_wedge_inject_scan_test.dart`
Expected: FAIL — `The method 'injectScan' isn't defined for the type 'DataWedgeService'`.

- [ ] **Step 3: Add the method**

In `lib/app/data/services/data_wedge_service.dart`, add the public method directly above the existing `void _enqueueScan(String code) {` (line 89):

```dart
  /// Public entry point for non-EventChannel scan sources (e.g. the HID
  /// keyboard-wedge bridge). Funnels into the same queue as native scans so
  /// downstream consumers behave identically to a Zebra/DataWedge scan.
  void injectScan(String code) => _enqueueScan(code);

```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/data_wedge_inject_scan_test.dart`
Expected: PASS — both tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/data_wedge_service.dart test/unit/data_wedge_inject_scan_test.dart
git commit -m "feat(scan): add DataWedgeService.injectScan public entry point"
```

---

### Task 3: `HidWedgeService` (global HardwareKeyboard bridge)

**Files:**
- Create: `lib/app/data/services/hid_wedge_service.dart`
- Test: `test/unit/hid_wedge_service_test.dart`

**Interfaces:**
- Consumes: `WedgeBurstAssembler` (Task 1: `addChar`, `terminate`); `DataWedgeService.injectScan` (Task 2).
- Produces:
  - `class HidWedgeService extends GetxService`
  - `HidWedgeService({WedgeBurstAssembler? assembler, DataWedgeService? dataWedge})` — both optional for testing; in production they default to a fresh assembler and a lazily `Get.find`-ed `DataWedgeService`.
  - `bool handleKeyEvent(KeyEvent event)` — the handler registered with `HardwareKeyboard.instance`. Returns `true` to consume the event.
  - Registers the handler in `onInit`, removes it in `onClose`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/hid_wedge_service_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/hid_wedge_service.dart';
import 'package:multimax/app/data/services/wedge_burst_assembler.dart';

/// Records injected codes without starting DataWedgeService's queue timers.
class _FakeDataWedge extends DataWedgeService {
  final List<String> injected = [];
  @override
  void injectScan(String code) => injected.add(code);
}

KeyDownEvent _charDown(String ch, LogicalKeyboardKey key, int ms) =>
    KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA, // physical key is irrelevant here
      logicalKey: key,
      character: ch,
      timeStamp: Duration(milliseconds: ms),
    );

KeyDownEvent _enterDown(int ms) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration(milliseconds: ms),
    );

KeyUpEvent _enterUp(int ms) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration(milliseconds: ms),
    );

void main() {
  group('HidWedgeService.handleKeyEvent', () {
    late _FakeDataWedge dw;
    late HidWedgeService svc;

    setUp(() {
      dw = _FakeDataWedge();
      svc = HidWedgeService(
        assembler: WedgeBurstAssembler(),
        dataWedge: dw,
      );
    });

    test('a tight char burst + Enter injects the assembled code once', () {
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6, 0));
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9, 10));
      svc.handleKeyEvent(_charDown('2', LogicalKeyboardKey.digit2, 20));
      svc.handleKeyEvent(_charDown('8', LogicalKeyboardKey.digit8, 30));
      svc.handleKeyEvent(_enterDown(40));
      expect(dw.injected, ['6928']);
    });

    test('first char passes through (false), mid-burst chars consume (true)',
        () {
      expect(
          svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6, 0)),
          isFalse);
      expect(
          svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9, 10)),
          isTrue);
    });

    test('Enter that completes a burst is consumed', () {
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6, 0));
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9, 10));
      expect(svc.handleKeyEvent(_enterDown(20)), isTrue);
    });

    test('Enter with no burst is not consumed and injects nothing', () {
      expect(svc.handleKeyEvent(_enterDown(0)), isFalse);
      expect(dw.injected, isEmpty);
    });

    test('key-up events are ignored', () {
      expect(svc.handleKeyEvent(_enterUp(0)), isFalse);
      expect(dw.injected, isEmpty);
    });

    test('a non-printable key resets the in-progress burst', () {
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6, 0));
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9, 10));
      // Arrow key: no character -> reset.
      svc.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: LogicalKeyboardKey.arrowLeft,
        timeStamp: const Duration(milliseconds: 20),
      ));
      svc.handleKeyEvent(_enterDown(30));
      expect(dw.injected, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/hid_wedge_service_test.dart`
Expected: FAIL — target of URI doesn't exist: `hid_wedge_service.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/app/data/services/hid_wedge_service.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/wedge_burst_assembler.dart';

/// Bridges Bluetooth HID keyboard-wedge scanners (e.g. Netum C750) into the
/// app's single scan sink.
///
/// Registers a global [HardwareKeyboard] handler, assembles key bursts via
/// [WedgeBurstAssembler], and on a completed Enter-terminated burst calls
/// [DataWedgeService.injectScan] — giving HID scans full parity with the
/// native Zebra/DataWedge path across every existing `ever()`-worker flow.
///
/// Consume policy (decided synchronously per key, since the inter-key gap is
/// only known from the second key onward):
///   - mid-burst chars (gap < maxGapMs)  -> consumed (kept out of focused fields)
///   - first char of a burst (idle gap)  -> passed through
///   - an Enter that completes a burst   -> consumed (no stray submit / focus move)
class HidWedgeService extends GetxService {
  HidWedgeService({WedgeBurstAssembler? assembler, DataWedgeService? dataWedge})
      : _assembler = assembler ?? WedgeBurstAssembler(),
        _dataWedgeOverride = dataWedge;

  final WedgeBurstAssembler _assembler;
  final DataWedgeService? _dataWedgeOverride;

  DataWedgeService get _dataWedge =>
      _dataWedgeOverride ?? Get.find<DataWedgeService>();

  @override
  void onInit() {
    super.onInit();
    HardwareKeyboard.instance.addHandler(handleKeyEvent);
  }

  @override
  void onClose() {
    HardwareKeyboard.instance.removeHandler(handleKeyEvent);
    super.onClose();
  }

  /// Handler registered with [HardwareKeyboard]. Returns `true` to consume.
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final ts = event.timeStamp.inMilliseconds;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _assembler.terminate(ts);
      if (code != null) {
        _dataWedge.injectScan(code);
        return true;
      }
      return false;
    }

    final ch = event.character;
    if (ch != null && _isPrintable(ch)) {
      return _assembler.addChar(ch, ts);
    }

    _assembler.reset();
    return false;
  }

  bool _isPrintable(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return c >= 0x20 && c != 0x7f; // exclude control chars and DEL
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/hid_wedge_service_test.dart`
Expected: PASS — all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/hid_wedge_service.dart test/unit/hid_wedge_service_test.dart
git commit -m "feat(scan): add HidWedgeService HardwareKeyboard bridge"
```

---

### Task 4: Register `HidWedgeService` and document scanner setup

**Files:**
- Modify: `lib/main.dart` (add import; register service after `DataWedgeService` at line 36)
- Create: `docs/hid_wedge_scanning.md`

**Interfaces:**
- Consumes: `HidWedgeService` (Task 3); `DataWedgeService` already registered in `main.dart:36`.
- Produces: a live `HidWedgeService` for the app session. No public API.

- [ ] **Step 1: Add the import**

In `lib/main.dart`, directly below the existing line 10
`import 'package:multimax/app/data/services/data_wedge_service.dart';`, add:

```dart
import 'package:multimax/app/data/services/hid_wedge_service.dart';
```

- [ ] **Step 2: Register the service**

In `lib/main.dart`, the current block reads:

```dart
  Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
  Get.put<ScanService>(ScanService(), permanent: true);
```

Change it to (insert the `HidWedgeService` line between them so `DataWedgeService` is registered first):

```dart
  Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
  // HID keyboard-wedge bridge (Netum C750 etc.) feeds DataWedgeService.scannedCode.
  Get.put<HidWedgeService>(HidWedgeService(), permanent: true);
  Get.put<ScanService>(ScanService(), permanent: true);
```

- [ ] **Step 3: Write the operational doc**

Create `docs/hid_wedge_scanning.md`:

```markdown
# HID Keyboard-Wedge Scanning (Netum C750)

The app accepts Bluetooth HID keyboard-wedge scanners (e.g. the Netum C750)
in addition to Zebra DataWedge / integrated PDA scanners. HID scans are
assembled by `HidWedgeService` and routed into `DataWedgeService.scannedCode`,
so every scan-driven screen behaves exactly as it does with a Zebra device.

## Scanner setup (one-time)

Scan the C750 configuration barcodes to set:

1. **HID / Bluetooth keyboard mode** (not BLE/SPP serial mode).
2. **CR (Enter) suffix enabled** — the app uses Enter to delimit a scan. With
   no suffix, scans cannot be detected.
3. **US-English keyboard locale** — match the phone's layout so symbols such
   as `-` map correctly.

Then pair the scanner with the phone in Android Bluetooth settings.

## How it works

- `WedgeBurstAssembler` treats keystrokes arriving within 50 ms of each other
  as one burst; an Enter finalises the burst into a barcode string.
- Slow human typing (gaps >= 50 ms) is never treated as a scan, so manual
  entry into search / quantity / login fields still works.
- Known limitation: if a text field is focused when you scan, the single
  leading character may also land in that field. The full code still routes
  correctly. On the scan-driven screens (lists, sheets) no field is focused,
  so this does not occur there.

## Not supported (by design)

- Netum BLE/SPP SDK mode and scanner back-channel commands (beep / trigger /
  sleep). HID is one-way (scanner -> phone).
```

- [ ] **Step 4: Verify the app analyses cleanly**

Run: `flutter analyze`
Expected: `No issues found!` (or no new issues introduced by the changed/added files).

- [ ] **Step 5: Run the full unit suite**

Run: `flutter test test/unit/`
Expected: PASS — including the three new test files from Tasks 1–3. (Pre-existing unrelated failures noted in project memory for `status_pill` / `doctype_form_header` may remain; do not fix them here.)

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart docs/hid_wedge_scanning.md
git commit -m "feat(scan): register HidWedgeService and document HID setup"
```

- [ ] **Step 7: Manual device smoke test (not automatable)**

On an Android phone with a paired C750 in HID mode + CR suffix:
1. Open a list screen (no focused field) and scan a known barcode — the
   existing scan reaction fires (same as Zebra).
2. Open a form sheet that uses `BarcodeListenerMixin` and scan — the sheet
   reacts.
3. Confirm slow manual typing into a search field still works normally.

---

## Self-Review notes

- **Spec coverage:** Assembler (Task 1), `injectScan` single-sink (Task 2),
  `HidWedgeService` global handler + consume policy (Task 3), `main.dart`
  registration + operational doc (Task 4). Trade-off and "not supported" scope
  documented in `docs/hid_wedge_scanning.md`. All spec sections mapped.
- **Type consistency:** `addChar(String,int)->bool`, `terminate(int)->String?`,
  `reset()`, `injectScan(String)->void`, `handleKeyEvent(KeyEvent)->bool` are
  used identically across tasks and tests.
- **No native / permission changes**, no new dependencies — matches Global
  Constraints.
