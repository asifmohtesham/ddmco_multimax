import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';

// The Stock Balance tile derives a health state per row from its on-hand balance
// and how much of that balance is already reserved, then renders a colour-coded
// hero, a faint-tinted balance cell, and either an availability bar or a status
// note from it. These are the pure rules behind that presentation.
void main() {
  group('stockBalanceStateFor', () {
    test('negative balance → negative regardless of reservation', () {
      expect(stockBalanceStateFor(-6, 0), StockBalanceState.negative);
      expect(stockBalanceStateFor(-1, 10), StockBalanceState.negative);
    });

    test('zero balance → empty', () {
      expect(stockBalanceStateFor(0, 0), StockBalanceState.empty);
    });

    test('healthy free stock → ok', () {
      expect(stockBalanceStateFor(12, 0), StockBalanceState.ok);
      expect(stockBalanceStateFor(84, 12), StockBalanceState.ok); // ~14% reserved
    });

    test('≥80% reserved → watch', () {
      expect(stockBalanceStateFor(220, 200), StockBalanceState.watch); // ~91%
      expect(stockBalanceStateFor(10, 8), StockBalanceState.watch);    // exactly 80%
    });

    test('just under 80% reserved → ok', () {
      expect(stockBalanceStateFor(100, 79), StockBalanceState.ok);
    });
  });

  group('availabilitySplit', () {
    test('splits balance into available + reserved', () {
      final s = availabilitySplit(220, 200);
      expect(s.available, 20);
      expect(s.reserved, 200);
    });

    test('no reservation → all available', () {
      final s = availabilitySplit(12, 0);
      expect(s.available, 12);
      expect(s.reserved, 0);
    });

    test('over-reservation is clamped to the balance (no negative width)', () {
      final s = availabilitySplit(10, 25);
      expect(s.reserved, 10);
      expect(s.available, 0);
    });

    test('negative balance never yields a reserved segment', () {
      final s = availabilitySplit(-6, 4);
      expect(s.reserved, 0);
      expect(s.available, -6);
    });
  });
}
