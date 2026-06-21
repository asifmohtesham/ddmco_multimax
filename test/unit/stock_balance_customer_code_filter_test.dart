import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

// Customer Code on the Stock Balance report has no server-side report filter
// and the query_report.run API does NOT return the (web-only) Customer Code
// column — so it is resolved server-side: ref_code → parent item codes, then
// fed to the report's native item_code filter. resolveItemCodeFilter computes
// the final item-code restriction, intersecting any typed Item filter with the
// items resolved from the Customer Code lookup.
void main() {
  group('StockBalanceController.resolveItemCodeFilter', () {
    test('no customer items and no typed item → null (unrestricted)', () {
      expect(StockBalanceController.resolveItemCodeFilter('', null), isNull);
    });

    test('no customer items, typed item → just the typed item', () {
      expect(
        StockBalanceController.resolveItemCodeFilter('ITEM-1', null),
        ['ITEM-1'],
      );
    });

    test('typed item is trimmed', () {
      expect(
        StockBalanceController.resolveItemCodeFilter('  ITEM-1  ', null),
        ['ITEM-1'],
      );
    });

    test('customer items, no typed item → all customer items', () {
      expect(
        StockBalanceController.resolveItemCodeFilter('', ['A', 'B']),
        ['A', 'B'],
      );
    });

    test('customer items + matching typed item → intersection (the item)', () {
      expect(
        StockBalanceController.resolveItemCodeFilter('A', ['A', 'B']),
        ['A'],
      );
    });

    test('customer items + non-matching typed item → empty (no results)', () {
      expect(
        StockBalanceController.resolveItemCodeFilter('Z', ['A', 'B']),
        isEmpty,
      );
    });

    test('empty customer item list → empty (no results)', () {
      expect(
        StockBalanceController.resolveItemCodeFilter('', <String>[]),
        isEmpty,
      );
    });
  });

  group('StockBalanceController.filterRowsByItemCodes', () {
    final rows = <Map<String, dynamic>>[
      {'item_code': '2002843', 'balance_qty': 70},
      {'item_code': '2002844', 'balance_qty': 5},
      {'item_code': '1000030', 'balance_qty': 1},
      {'balance_qty': 9}, // row with no item_code
    ];

    test('keeps only rows whose item_code is in the allowed set', () {
      final result =
          StockBalanceController.filterRowsByItemCodes(rows, ['2002843', '2002844']);
      expect(result.map((r) => r['item_code']), ['2002843', '2002844']);
    });

    test('returns empty when the allowed set matches no rows', () {
      final result = StockBalanceController.filterRowsByItemCodes(rows, ['ZZZ']);
      expect(result, isEmpty);
    });

    test('drops rows that have no item_code', () {
      final result =
          StockBalanceController.filterRowsByItemCodes(rows, ['2002843']);
      expect(result.length, 1);
      expect(result.first['item_code'], '2002843');
    });
  });
}
