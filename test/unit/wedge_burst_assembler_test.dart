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
