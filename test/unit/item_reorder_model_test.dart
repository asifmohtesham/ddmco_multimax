import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_model.dart';

void main() {
  group('ItemReorder.fromJson', () {
    test('parses a full row', () {
      final r = ItemReorder.fromJson({
        'name': 'abc123',
        'warehouse_group': 'Finished Goods - KA',
        'warehouse': 'WH-DXB1 - KA',
        'warehouse_reorder_level': 2400,
        'warehouse_reorder_qty': 2400.5,
        'material_request_type': 'Purchase',
      });

      expect(r.name, 'abc123');
      expect(r.warehouseGroup, 'Finished Goods - KA');
      expect(r.warehouse, 'WH-DXB1 - KA');
      expect(r.warehouseReorderLevel, 2400.0);
      expect(r.warehouseReorderQty, 2400.5);
      expect(r.materialRequestType, 'Purchase');
    });

    test('normalises a blank warehouse_group to null', () {
      final r = ItemReorder.fromJson({'warehouse': 'WH-A', 'warehouse_group': ''});
      expect(r.warehouseGroup, isNull);
    });

    test('defaults missing numerics to zero', () {
      final r = ItemReorder.fromJson({'warehouse': 'WH-A'});
      expect(r.warehouseReorderLevel, 0.0);
      expect(r.warehouseReorderQty, 0.0);
      expect(r.materialRequestType, '');
    });
  });

  group('ItemReorder.toJson', () {
    test('mirrors item.py:508-509 — blank group defaults to the warehouse', () {
      final r = ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase');
      expect(r.toJson()['warehouse_group'], 'WH-A');
    });

    test('keeps an explicit group untouched', () {
      final r = ItemReorder(
        warehouseGroup: 'Stores - KA',
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
      );
      expect(r.toJson()['warehouse_group'], 'Stores - KA');
    });

    test('omits name for a new row and includes it for an existing one', () {
      final fresh = ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase');
      expect(fresh.toJson().containsKey('name'), isFalse);

      final existing = ItemReorder(
        name: 'abc123',
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
      );
      expect(existing.toJson()['name'], 'abc123');
    });

    test('round-trips through fromJson', () {
      final original = ItemReorder(
        name: 'abc123',
        warehouseGroup: 'Stores - KA',
        warehouse: 'WH-A',
        warehouseReorderLevel: 10,
        warehouseReorderQty: 20,
        materialRequestType: 'Transfer',
      );
      final again = ItemReorder.fromJson(original.toJson());

      expect(again.name, original.name);
      expect(again.warehouseGroup, original.warehouseGroup);
      expect(again.warehouse, original.warehouse);
      expect(again.warehouseReorderLevel, original.warehouseReorderLevel);
      expect(again.warehouseReorderQty, original.warehouseReorderQty);
      expect(again.materialRequestType, original.materialRequestType);
    });
  });

  group('Item.fromJson reorder fields', () {
    test('parses reorder_levels', () {
      final item = Item.fromJson({
        'name': 'ITEM-1',
        'reorder_levels': [
          {'warehouse': 'WH-A', 'material_request_type': 'Purchase'},
          {'warehouse': 'WH-B', 'material_request_type': 'Transfer'},
        ],
      });
      expect(item.reorderLevels.length, 2);
      expect(item.reorderLevels.first.warehouse, 'WH-A');
    });

    test('absent reorder_levels yields an empty list', () {
      final item = Item.fromJson({'name': 'ITEM-1'});
      expect(item.reorderLevels, isEmpty);
    });

    test('parses is_stock_item as an int check', () {
      expect(Item.fromJson({'is_stock_item': 1}).isStockItem, isTrue);
      expect(Item.fromJson({'is_stock_item': 0}).isStockItem, isFalse);
      expect(Item.fromJson({}).isStockItem, isFalse);
    });

    test('parses default_material_request_type and modified', () {
      final item = Item.fromJson({
        'default_material_request_type': 'Purchase',
        'modified': '2026-07-17 09:00:00',
      });
      expect(item.defaultMaterialRequestType, 'Purchase');
      expect(item.modified, '2026-07-17 09:00:00');
    });
  });
}
