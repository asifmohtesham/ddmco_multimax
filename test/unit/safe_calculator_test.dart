import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/utils/safe_calculator.dart';

void main() {
  group('looksLikeCalculation', () {
    test('digit, ( or = starts a calculation', () {
      expect(looksLikeCalculation('12'), isTrue);
      expect(looksLikeCalculation('(1+2)'), isTrue);
      expect(looksLikeCalculation('=2^10'), isTrue);
    });
    test('anything else does not', () {
      expect(looksLikeCalculation('abc'), isFalse);
      expect(looksLikeCalculation(''), isFalse);
      expect(looksLikeCalculation('-1'), isFalse);
    });
  });

  group('evaluateExpression', () {
    test('(55 + 434) / 4 = 122.25', () {
      expect(evaluateExpression('(55 + 434) / 4'), 122.25);
    });

    test('=2^10 = 1024', () {
      expect(evaluateExpression('=2^10'), 1024);
    });

    test('^ is right-associative', () {
      expect(evaluateExpression('2^3^2'), 512);
    });

    test('precedence: 1 + 2 * 3 = 7', () {
      expect(evaluateExpression('1 + 2 * 3'), 7);
    });

    test('unary minus and modulo', () {
      expect(evaluateExpression('3 - -2'), 5);
      expect(evaluateExpression('10 % 3'), 1);
    });

    test('1/0 yields no result', () {
      expect(evaluateExpression('1/0'), isNull);
    });

    test('12abc yields no result', () {
      expect(evaluateExpression('12abc'), isNull);
    });

    test('a dangling operator yields no result', () {
      expect(evaluateExpression('1 + '), isNull);
      expect(evaluateExpression('(1'), isNull);
    });

    test('identifiers are never evaluated', () {
      expect(evaluateExpression('Math.sin(1)'), isNull);
      expect(evaluateExpression('=alert(1)'), isNull);
    });
  });

  group('formatCalculatorResult', () {
    test('integers have no decimal point', () {
      expect(formatCalculatorResult(1024), '1024');
      expect(formatCalculatorResult(-3), '-3');
    });
    test('decimals drop trailing zeros', () {
      expect(formatCalculatorResult(122.25), '122.25');
      expect(formatCalculatorResult(1 / 3), '0.3333333333');
    });
  });
}
