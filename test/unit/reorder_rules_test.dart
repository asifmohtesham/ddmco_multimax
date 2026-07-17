import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/item/form/reorder_rules.dart';

ItemReorder _row({
  String warehouse = 'WH-A',
  String type = 'Purchase',
  double level = 0,
  double qty = 0,
}) =>
    ItemReorder(
      warehouse: warehouse,
      materialRequestType: type,
      warehouseReorderLevel: level,
      warehouseReorderQty: qty,
    );

void main() {
  group('defaultReorderTypeFor', () {
    test('passes Purchase through', () {
      expect(defaultReorderTypeFor('Purchase'), 'Purchase');
    });

    test('remaps Material Transfer to Transfer (item.js:292-298)', () {
      expect(defaultReorderTypeFor('Material Transfer'), 'Transfer');
    });

    test('passes Material Issue and Manufacture through', () {
      expect(defaultReorderTypeFor('Material Issue'), 'Material Issue');
      expect(defaultReorderTypeFor('Manufacture'), 'Manufacture');
    });

    test('returns empty for Customer Provided — not a valid Item Reorder option',
        () {
      // v15 Desk copies this verbatim, producing an invalid Select value.
      // We deliberately leave it unset instead.
      expect(defaultReorderTypeFor('Customer Provided'), '');
    });

    test('returns empty for null or empty input', () {
      expect(defaultReorderTypeFor(null), '');
      expect(defaultReorderTypeFor(''), '');
    });
  });

  group('validateReorderRows', () {
    test('accepts an empty list', () {
      expect(validateReorderRows([]), isNull);
    });

    test('accepts a valid row', () {
      expect(validateReorderRows([_row(level: 100, qty: 50)]), isNull);
    });

    test('rejects a blank warehouse', () {
      final err = validateReorderRows([_row(warehouse: '')]);
      expect(err, contains('Row #1'));
      expect(err, contains('Request for'));
    });

    test('rejects a blank material request type', () {
      final err = validateReorderRows([_row(type: '')]);
      expect(err, contains('Row #1'));
      expect(err, contains('material request type'));
    });

    test('rejects a duplicate (warehouse, type) pair', () {
      final err = validateReorderRows([
        _row(warehouse: 'WH-A', type: 'Purchase'),
        _row(warehouse: 'WH-A', type: 'Purchase'),
      ]);
      expect(err, contains('Row #2'));
      expect(err, contains('already exists'));
      expect(err, contains('WH-A'));
    });

    test('allows the same warehouse with a different type', () {
      // item.py:510-518 keys uniqueness on the TUPLE, not warehouse alone.
      expect(
        validateReorderRows([
          _row(warehouse: 'WH-A', type: 'Purchase'),
          _row(warehouse: 'WH-A', type: 'Transfer'),
        ]),
        isNull,
      );
    });

    test('rejects a level with no qty (item.py:520-521)', () {
      final err = validateReorderRows([_row(level: 100, qty: 0)]);
      expect(err, contains('Row #1'));
      expect(err, contains('Please set reorder quantity'));
    });

    test('allows a qty with no level — the check is one-directional', () {
      expect(validateReorderRows([_row(level: 0, qty: 50)]), isNull);
    });

    test('reports the row number of the offending row, 1-based', () {
      final err = validateReorderRows([
        _row(warehouse: 'WH-A'),
        _row(warehouse: 'WH-B'),
        _row(warehouse: 'WH-C', level: 5, qty: 0),
      ]);
      expect(err, contains('Row #3'));
    });
  });
}
