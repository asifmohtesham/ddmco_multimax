// test/unit/dn_item_warehouse_field_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

void main() {
  group('DeliveryNoteItem.warehouse field', () {
    test('T-1: fromJson reads warehouse when present', () {
      final item = DeliveryNoteItem.fromJson({
        'item_code': 'ITEM-001',
        'qty': 1.0,
        'rate': 0.0,
        'warehouse': 'WH-DXB1 - KA',
      });
      expect(item.warehouse, equals('WH-DXB1 - KA'));
    });

    test('T-2: fromJson returns null warehouse when key is absent', () {
      final item = DeliveryNoteItem.fromJson({
        'item_code': 'ITEM-001',
        'qty': 1.0,
        'rate': 0.0,
      });
      expect(item.warehouse, isNull);
    });

    test('T-3: toJson includes warehouse key when non-null', () {
      final item = DeliveryNoteItem(
        itemCode: 'ITEM-001',
        qty: 1.0,
        rate: 0.0,
        warehouse: 'WH-DXB1 - KA',
      );
      expect(item.toJson()['warehouse'], equals('WH-DXB1 - KA'));
    });

    test('T-4: toJson omits warehouse key when null', () {
      final item = DeliveryNoteItem(
        itemCode: 'ITEM-001',
        qty: 1.0,
        rate: 0.0,
      );
      expect(item.toJson().containsKey('warehouse'), isFalse);
    });
  });
}
