# HID Keyboard-Wedge Scan Support (Netum C750)

**Date:** 2026-06-17
**Status:** Approved design — ready for implementation planning

## Problem

The app receives hardware barcode scans through one path only: a native
broadcast Intent → `EventChannel` → `DataWedgeService.scannedCode`
(`android/app/src/main/kotlin/com/ddmco/multimax/MainActivity.kt`,
`lib/app/data/services/data_wedge_service.dart`). That path serves Zebra
DataWedge devices and integrated Android-PDA scanners that emit
`com.android.server.scannerservice.broadcast`.

The **Netum C750 is a standalone Bluetooth scanner**. It does not emit those
broadcasts, and the app does not integrate the Netum BLE/SPP SDK (no Bluetooth
package in `pubspec.yaml`, no Bluetooth code in `MainActivity.kt`, only
`INTERNET` permission in the manifest). The only way a C750 works today is
**HID keyboard mode**, and even then it only reaches the focused
`BarcodeInputWidget` text field via `onFieldSubmitted` — it never populates
`scannedCode`, so all background `ever()`-worker flows (list screens, the
`BarcodeListenerMixin` sheets, the packing-slip multi-serial auto-advance) are
unreachable.

## Goal

Make a Netum C750 in HID keyboard mode behave like the Zebra path: every
existing scan-driven flow works unchanged, regardless of UI focus, with **no
changes to controllers, mixins, `BarcodeInputWidget`, the camera path, or the
native layer**.

## Core principle: one sink, two sources

`DataWedgeService.scannedCode` is the single sink all consumers already
subscribe to. We add a second source (HID key events) that funnels into the
same sink. Downstream behaviour is therefore identical to a Zebra scan.

## Decisions (locked during brainstorming)

1. **Global-always capture.** A root-level hardware-key listener captures
   scanner-cadence bursts everywhere and consumes the terminator so it does not
   land in a focused field. Slow human typing still flows to fields normally.
   (Chosen over focus-aware and hybrid-allowlist for parity with the
   focus-independent Zebra model.)
2. **Timing + terminator detection.** Input is treated as a scan when all
   inter-key gaps stay under a threshold (`maxGapMs`, ~50 ms) **and** the burst
   ends with the terminator. (Chosen over stricter multi-signal and a
   connected-scanner gate.)
3. **Enter / CR is the only terminator.** Matches the C750 default CR suffix
   and the existing `BarcodeInputWidget.onFieldSubmitted` behaviour. (Chosen
   over Enter-or-Tab and an in-app configurable terminator.)

## Components

Three units, each with a single responsibility. Dependencies flow one way:
`HidWedgeService` → (`WedgeBurstAssembler`, `DataWedgeService`). Nothing
depends back on `HidWedgeService`.

### 1. `WedgeBurstAssembler` — `lib/app/data/services/wedge_burst_assembler.dart`

Pure Dart, no Flutter imports. A timing state machine:

- Holds a character buffer and the last-key timestamp. It is the **single
  owner of all timing state** — the service never recomputes gaps itself.
- `addChar(String char, int timestampMs) → bool` → if the gap since the last
  key ≥ `maxGapMs`, resets the buffer first (this char starts a new burst) and
  returns `false` (not in cadence). Otherwise appends and returns `true` (in
  cadence). The returned flag is exactly what the service uses for its
  consume decision, so the consume rule and the buffer-reset rule can never
  diverge.
- `terminate(int timestampMs) → String?` → returns the assembled code if the
  buffer qualifies as a burst (non-empty and assembled in cadence), else
  `null`. Clears the buffer either way.
- `reset()` → clears state (called on non-printable, non-modifier keys).
- Single tuning constant `maxGapMs` (~50 ms).

Independently unit-testable: no GetX, no key codes, no OS.

### 2. `HidWedgeService extends GetxService` — `lib/app/data/services/hid_wedge_service.dart`

Thin bridge. Registered in `main.dart` with `permanent: true`, alongside
`DataWedgeService`.

- `onInit`: registers a handler via `HardwareKeyboard.instance.addHandler`.
- `onClose`: removes the handler.
- Per `KeyDownEvent` (ignore `KeyUpEvent` and `KeyRepeatEvent`):
  - **Enter** (`LogicalKeyboardKey.enter`): call `assembler.terminate(now)`. If
    it returns a code, call `DataWedgeService.injectScan(code)` and **consume**
    the event (`return true`). Else `return false`.
  - **Printable key** (`event.character` non-null/non-control): call
    `assembler.addChar(char, now)`. If it returns `true` (mid-burst):
    **consume** (`return true`). If it returns `false` (idle / first key of a
    burst): **pass through** (`return false`). The service never computes gaps
    itself — it trusts the assembler's cadence flag.
  - **Modifier key** (Shift, CapsLock, Ctrl, Alt, Meta): ignored — `return
    false` WITHOUT resetting. Modifiers carry no character and are part of
    producing the next character (e.g. Shift for an uppercase barcode digit),
    so resetting on them would fragment uppercase/mixed-case scans.
  - **Other non-printable key** (arrows, function keys, etc.):
    `assembler.reset()`, `return false`.

### 3. `DataWedgeService.injectScan(String code)` — modify `data_wedge_service.dart`

One new public method that calls the existing private `_enqueueScan(code)`. The
HID path thereby inherits the existing queue, the 800 ms hold/clear cycle, and
the 300 ms mixin debounce — no divergence from the Zebra path downstream.
Empty/whitespace codes are dropped by the existing `_enqueueScan` guard.

## Data flow

**Happy path (no editable field focused — the worker-driven flows):**

1. C750 fires a burst `6 9 2 8 … Enter`, keys a few ms apart.
2. The handler feeds each printable key to the assembler; gaps are all
   < `maxGapMs`.
3. On Enter, `terminate` returns `"6928804014662"`.
4. Handler calls `injectScan` → `_enqueueScan` → `scannedCode` cycles.
5. Existing `ever()` workers fire exactly as for a Zebra scan. Full parity.

**Consume decision (synchronous, per key):** `addHandler` must decide
immediately whether to swallow each key. The gap only exists from the second
key onward, so the first key of any burst is passed through; mid-burst keys are
consumed; a qualifying Enter is consumed.

## Known trade-off

`addHandler` requires a synchronous consume decision per key, but burst
detection needs the inter-key gap, which is unknown for the first key. Result:
the **first character** of a scan is passed through.

- On screens with **no focused editable field** (all worker-driven flows): the
  stray first char goes nowhere → clean, full parity.
- On the rare screen where a **real editable field is focused**: the full code
  still routes correctly to `scannedCode`, but a single leading char also lands
  in the field.

This is accepted for v1. Perfect global-always parity while an arbitrary
third-party text field is focused is not cleanly achievable with HID, because
the OS delivers scanner keys to the focused editable indistinguishably from a
keyboard. Slow human typing (gaps ≥ `maxGapMs` throughout) never triggers
injection, so manual entry into search/quantity/login fields still works.

A future narrow carve-out (suppress injection while `BarcodeInputWidget`'s
field is focused, letting its `onFieldSubmitted` handle the scan) can remove the
wart but is out of scope for v1.

## Error / edge handling

- `KeyUpEvent` and `KeyRepeatEvent` ignored.
- Modifier keys (Shift/CapsLock/Ctrl/Alt/Meta) are ignored without resetting,
  so they don't fragment uppercase/mixed-case scans; other non-printable keys
  (arrows, function keys) reset the assembler buffer.
- A buffer that goes idle without a terminator is discarded on the next
  out-of-cadence key.
- Empty/whitespace codes dropped by the existing `_enqueueScan` guard.
- Codes are passed through verbatim — hyphens in rack / `SHIPMENT-…` codes and
  EAN-8 digits are never mangled.

## Testing

- **`WedgeBurstAssembler` unit tests** (bulk of coverage, pure Dart):
  tight burst + Enter → code; mid-stream gap ≥ `maxGapMs` → reset, no code;
  slow human cadence + Enter → `null`; terminator with empty buffer → `null`;
  boundary timing at `maxGapMs`; hyphenated/EAN-8 payloads verbatim.
- **`HidWedgeService` tests** (lightweight): synthetic `KeyEvent`s →
  `injectScan` called once with the assembled code; key-up/repeat ignored;
  handler removed on `onClose`.
- **No Zebra regression:** `injectScan` reuses `_enqueueScan`, so existing
  `DataWedgeService` queue/debounce tests stay green.

## Operational setup (documented, not coded)

A short `docs/hid_wedge_scanning.md`: put the C750 in HID / Bluetooth keyboard
mode, enable the **CR (Enter) suffix**, and set **US-English locale** to match
the phone layout. Without the CR suffix the app cannot delimit a scan.

## Files

- **New:** `lib/app/data/services/wedge_burst_assembler.dart`,
  `lib/app/data/services/hid_wedge_service.dart`,
  `test/unit/wedge_burst_assembler_test.dart`,
  `test/unit/hid_wedge_service_test.dart` (or `test/widget/`),
  `docs/hid_wedge_scanning.md`.
- **Changed:** `lib/app/data/services/data_wedge_service.dart` (+`injectScan`),
  `lib/main.dart` (register `HidWedgeService`, `permanent: true`).
- **Untouched:** `MainActivity.kt`, all controllers/mixins,
  `BarcodeInputWidget`, the camera path.
- **No new dependencies** (`HardwareKeyboard` is Flutter core); no manifest or
  permission changes (HID needs none).

## Scope guard (YAGNI — not in v1)

- The Netum BLE/SPP SDK integration.
- Scanner back-channel commands (beep / soft-trigger / sleep).
- Configurable terminator.
- Connected-scanner detection.
- The `BarcodeInputWidget` focus carve-out.
