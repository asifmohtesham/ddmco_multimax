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

// NOTE: `event.timeStamp` is intentionally fixed at zero in these helpers.
// Cadence is now derived from a monotonic wall clock read when the handler
// runs, NOT from the event timestamp — because Android's numeric soft keyboard
// delivers digit KeyEvents with unreliable / clustered timestamps. Tests drive
// the injected `clockMs` to model real inter-key timing.
KeyDownEvent _charDown(String ch, LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA, // physical key is irrelevant here
      logicalKey: key,
      character: ch,
      timeStamp: Duration.zero,
    );

KeyDownEvent _enterDown() => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );

KeyUpEvent _enterUp() => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );

KeyDownEvent _modDown(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.shiftLeft,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  group('HidWedgeService.handleKeyEvent', () {
    late _FakeDataWedge dw;
    late HidWedgeService svc;
    late int clock; // mutable wall-clock (ms) the service reads per key

    setUp(() {
      dw = _FakeDataWedge();
      clock = 0;
      svc = HidWedgeService(
        assembler: WedgeBurstAssembler(),
        dataWedge: dw,
        clockMs: () => clock,
      );
    });

    test('a tight char burst + Enter injects the assembled code once', () {
      clock = 0;
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6));
      clock = 10;
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9));
      clock = 20;
      svc.handleKeyEvent(_charDown('2', LogicalKeyboardKey.digit2));
      clock = 30;
      svc.handleKeyEvent(_charDown('8', LogicalKeyboardKey.digit8));
      clock = 40;
      svc.handleKeyEvent(_enterDown());
      expect(dw.injected, ['6928']);
    });

    test('first char passes through (false), mid-burst chars consume (true)',
        () {
      clock = 0;
      expect(
          svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6)),
          isFalse);
      clock = 10;
      expect(
          svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9)),
          isTrue);
    });

    // ── Regression (qty single-digit) ─────────────────────────────────────────
    // Android's numeric soft keyboard delivers digit KeyEvents whose
    // event.timeStamp is unreliable / identical. The user taps them >50 ms apart
    // in real wall-clock time, so each digit MUST pass through to the focused
    // field — otherwise a multi-digit quantity cannot be typed.
    test('slow human digits pass through despite identical event timestamps',
        () {
      clock = 1000;
      expect(
          svc.handleKeyEvent(_charDown('1', LogicalKeyboardKey.digit1)),
          isFalse);
      clock = 1200; // 200 ms later
      expect(
          svc.handleKeyEvent(_charDown('2', LogicalKeyboardKey.digit2)),
          isFalse);
      clock = 1400; // 200 ms later
      expect(
          svc.handleKeyEvent(_charDown('5', LogicalKeyboardKey.digit5)),
          isFalse);
      expect(dw.injected, isEmpty);
    });

    test('Enter that completes a burst is consumed', () {
      clock = 0;
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6));
      clock = 10;
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9));
      clock = 20;
      expect(svc.handleKeyEvent(_enterDown()), isTrue);
    });

    test('Enter with no burst is not consumed and injects nothing', () {
      expect(svc.handleKeyEvent(_enterDown()), isFalse);
      expect(dw.injected, isEmpty);
    });

    test('a slow Enter after a burst does not inject (terminator out of cadence)',
        () {
      clock = 0;
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6));
      clock = 10;
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9));
      clock = 500; // Enter pressed much later
      expect(svc.handleKeyEvent(_enterDown()), isFalse);
      expect(dw.injected, isEmpty);
    });

    test('key-up events are ignored', () {
      expect(svc.handleKeyEvent(_enterUp()), isFalse);
      expect(dw.injected, isEmpty);
    });

    test('a non-printable key resets the in-progress burst', () {
      clock = 0;
      svc.handleKeyEvent(_charDown('6', LogicalKeyboardKey.digit6));
      clock = 10;
      svc.handleKeyEvent(_charDown('9', LogicalKeyboardKey.digit9));
      clock = 20;
      // Arrow key: no character -> reset.
      svc.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowLeft,
        logicalKey: LogicalKeyboardKey.arrowLeft,
        timeStamp: Duration.zero,
      ));
      clock = 30;
      svc.handleKeyEvent(_enterDown());
      expect(dw.injected, isEmpty);
    });

    test('Shift key-downs between chars do not fragment an uppercase burst', () {
      // Scanning "AB12": Shift precedes each uppercase letter.
      clock = 0;
      svc.handleKeyEvent(_modDown(LogicalKeyboardKey.shiftLeft));
      clock = 5;
      svc.handleKeyEvent(_charDown('A', LogicalKeyboardKey.keyA));
      clock = 10;
      svc.handleKeyEvent(_modDown(LogicalKeyboardKey.shiftLeft));
      clock = 15;
      svc.handleKeyEvent(_charDown('B', LogicalKeyboardKey.keyB));
      clock = 20;
      svc.handleKeyEvent(_charDown('1', LogicalKeyboardKey.digit1));
      clock = 25;
      svc.handleKeyEvent(_charDown('2', LogicalKeyboardKey.digit2));
      clock = 30;
      svc.handleKeyEvent(_enterDown());
      expect(dw.injected, ['AB12']);
    });

    test('a modifier key alone is not consumed', () {
      expect(
          svc.handleKeyEvent(_modDown(LogicalKeyboardKey.shiftLeft)), isFalse);
    });
  });
}
