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
