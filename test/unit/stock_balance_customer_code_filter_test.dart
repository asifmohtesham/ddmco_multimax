import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

void main() {
  final columns = <Map<String, dynamic>>[
    {'fieldname': 'item_code',     'label': 'Item'},
    {'fieldname': 'customer_code', 'label': 'Customer Code'},
    {'fieldname': 'balance_qty',   'label': 'Balance Qty'},
  ];

  final rows = <Map<String, dynamic>>[
    {'item_code': 'A', 'customer_code': '5067100', 'balance_qty': 1},
    {'item_code': 'B', 'customer_code': '5067101', 'balance_qty': 2},
    {'item_code': 'C', 'customer_code': '2002716', 'balance_qty': 3},
    {'item_code': 'D', 'customer_code': null,      'balance_qty': 4},
  ];

  group('StockBalanceController.customerCodeColumnKey', () {
    test('returns row key when a Customer Code column exists (by label)', () {
      expect(
        StockBalanceController.customerCodeColumnKey(columns),
        'customer_code',
      );
    });

    test('matches the column by fieldname when label differs', () {
      final cols = [
        {'fieldname': 'customer_code', 'label': 'Cust. Ref'},
      ];
      expect(StockBalanceController.customerCodeColumnKey(cols), 'customer_code');
    });

    test('returns null when no Customer Code column is present', () {
      final cols = [
        {'fieldname': 'item_code', 'label': 'Item'},
      ];
      expect(StockBalanceController.customerCodeColumnKey(cols), isNull);
    });
  });

  group('StockBalanceController.filterRowsByCustomerCode', () {
    test('returns all rows unchanged when the query is empty', () {
      expect(
        StockBalanceController.filterRowsByCustomerCode(rows, columns, ''),
        rows,
      );
    });

    test('returns all rows unchanged when the query is only whitespace', () {
      expect(
        StockBalanceController.filterRowsByCustomerCode(rows, columns, '   '),
        rows,
      );
    });

    test('keeps only rows whose customer code contains the query', () {
      final result =
          StockBalanceController.filterRowsByCustomerCode(rows, columns, '50671');
      expect(result.map((r) => r['item_code']), ['A', 'B']);
    });

    test('matching is case-insensitive', () {
      final cols = [
        {'fieldname': 'customer_code', 'label': 'Customer Code'},
      ];
      final caseRows = [
        {'item_code': 'A', 'customer_code': 'ABC123'},
        {'item_code': 'B', 'customer_code': 'xyz789'},
      ];
      final result =
          StockBalanceController.filterRowsByCustomerCode(caseRows, cols, 'abc');
      expect(result.map((r) => r['item_code']), ['A']);
    });

    test('drops rows whose customer code is null', () {
      final result =
          StockBalanceController.filterRowsByCustomerCode(rows, columns, '0');
      expect(result.any((r) => r['item_code'] == 'D'), isFalse);
    });

    test('returns all rows unchanged when no Customer Code column exists', () {
      final cols = [
        {'fieldname': 'item_code', 'label': 'Item'},
      ];
      final result =
          StockBalanceController.filterRowsByCustomerCode(rows, cols, '5067100');
      expect(result, rows);
    });
  });
}
