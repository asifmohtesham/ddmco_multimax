import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseStockBalanceResponse', () {
    test('T-1: returns empty record when message is null', () {
      final result = ApiProvider.parseStockBalanceResponse(null);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-2: returns empty record when result list is empty', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [{'fieldname': 'item_code', 'label': 'Item Code'}],
        'result': <dynamic>[],
      });
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-3: parses Map rows correctly', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'item_code',   'label': 'Item Code'},
          {'fieldname': 'warehouse',   'label': 'Warehouse'},
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          {'item_code': 'ITEM-001', 'warehouse': 'Stores - KA', 'balance_qty': 42},
        ],
      });
      expect(result.rows.length, 1);
      expect(result.rows[0]['item_code'],   'ITEM-001');
      expect(result.rows[0]['warehouse'],   'Stores - KA');
      expect(result.rows[0]['balance_qty'], 42);
    });

    test('T-4: parses List rows using column positions', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'item_code',   'label': 'Item Code'},
          {'fieldname': 'warehouse',   'label': 'Warehouse'},
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          ['ITEM-001', 'Stores - KA', 15],
        ],
      });
      expect(result.rows.length, 1);
      expect(result.rows[0]['item_code'],   'ITEM-001');
      expect(result.rows[0]['warehouse'],   'Stores - KA');
      expect(result.rows[0]['balance_qty'], 15);
    });

    test('T-5: extracts fieldname from string-format columns', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': ['bin.item_code', 'bin.balance_qty'],
        'result': [
          ['ITEM-001', 50],
        ],
      });
      expect(result.columns[0]['fieldname'], 'item_code');
      expect(result.columns[1]['fieldname'], 'balance_qty');
      expect(result.rows[0]['item_code'],    'ITEM-001');
      expect(result.rows[0]['balance_qty'],  50);
    });

    test('T-6: populates columns list with fieldname and label', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          {'balance_qty': 0},
        ],
      });
      expect(result.columns.first['fieldname'], 'balance_qty');
      expect(result.columns.first['label'],     'Balance Qty');
    });
  });
}
