import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

void main() {
  const message = {
    'columns': [
      {'fieldname': 'item_code', 'label': 'Item'},
    ],
    'result': [
      {'item_code': 'A', 'customer_code': '5067101', 'in_stock_qty': 10, 'required_qty': 5,  'running_total': 10},
      {'item_code': 'B', 'customer_code': '5067102', 'in_stock_qty': 2,  'required_qty': 8,  'running_total': 2},
      {'item_code': 'A', 'customer_code': '5067101', 'in_stock_qty': 10, 'required_qty': 5,  'running_total': 0},
      {'item_code': '',  'item_name': 'Total', 'in_stock_qty': 22, 'running_total': 12}, // total row
    ],
  };

  group('parseDataRows', () {
    test('returns empty for null / wrong-shape message', () {
      expect(BomStockCustomerCodeController.parseDataRows(null), isEmpty);
      expect(BomStockCustomerCodeController.parseDataRows({'result': 'x'}), isEmpty);
    });

    test('keeps only rows with a non-empty item_code (drops the total row)', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      expect(rows.length, 3);
      expect(rows.every((r) => (r['item_code'] as String).isNotEmpty), isTrue);
    });
  });

  group('extractTotalRow', () {
    test('returns the row whose item_code is empty', () {
      final total = BomStockCustomerCodeController.extractTotalRow(message);
      expect(total, isNotNull);
      expect(total!['in_stock_qty'], 22);
    });

    test('returns null when there is no total row', () {
      final t = BomStockCustomerCodeController.extractTotalRow({
        'result': [
          {'item_code': 'A'},
        ],
      });
      expect(t, isNull);
    });
  });

  group('isShortfall', () {
    test('true when required_qty is non-zero and running_total is below it', () {
      expect(
        BomStockCustomerCodeController.isShortfall(
          {'required_qty': 8, 'running_total': 2}),
        isTrue,
      );
    });

    test('false when running_total meets or exceeds required_qty', () {
      expect(
        BomStockCustomerCodeController.isShortfall(
          {'required_qty': 5, 'running_total': 10}),
        isFalse,
      );
    });

    test('false when required_qty is null or zero', () {
      expect(BomStockCustomerCodeController.isShortfall({'running_total': 0}), isFalse);
      expect(
        BomStockCustomerCodeController.isShortfall(
          {'required_qty': 0, 'running_total': 0}),
        isFalse,
      );
    });
  });

  group('distinctCustomerCodes', () {
    test('returns distinct non-empty codes in first-seen order', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      expect(
        BomStockCustomerCodeController.distinctCustomerCodes(rows),
        ['5067101', '5067102'],
      );
    });
  });

  group('splitPosCodes', () {
    test('splits upload codes into found (present in results) and missing', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      final (found, missing) = BomStockCustomerCodeController.splitPosCodes(
        ['5067101', '5067102', '9999999'],
        rows,
      );
      expect(found, ['5067101', '5067102']);
      expect(missing, ['9999999']);
    });
  });
}
