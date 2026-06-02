import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/models/material_request_model.dart';

void main() {
  group('PurchaseReceiptItem.fromJson itemGroup', () {
    test('parses item_group when present', () {
      final item = PurchaseReceiptItem.fromJson({
        'item_code': 'ITEM-001',
        'warehouse': 'WH-001',
        'qty': 1,
        'owner': 'test',
        'creation': '2024-01-01',
        'item_group': 'BELTS',
      });
      expect(item.itemGroup, 'BELTS');
    });

    test('defaults to empty string when item_group absent', () {
      final item = PurchaseReceiptItem.fromJson({
        'item_code': 'ITEM-001',
        'warehouse': 'WH-001',
        'qty': 1,
        'owner': 'test',
        'creation': '2024-01-01',
      });
      expect(item.itemGroup, '');
    });
  });

  group('PackingSlipItem.fromJson itemGroup', () {
    test('parses item_group when present', () {
      final item = PackingSlipItem.fromJson({
        'name': 'row-1',
        'dn_detail': 'dn-1',
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'qty': 1,
        'uom': 'Nos',
        'batch_no': '',
        'net_weight': 0,
        'weight_uom': 0,
        'item_group': 'BELTS',
      });
      expect(item.itemGroup, 'BELTS');
    });

    test('defaults to empty string when item_group absent', () {
      final item = PackingSlipItem.fromJson({
        'name': 'row-1',
        'dn_detail': 'dn-1',
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'qty': 1,
        'uom': 'Nos',
        'batch_no': '',
        'net_weight': 0,
        'weight_uom': 0,
      });
      expect(item.itemGroup, '');
    });
  });

  group('PurchaseOrderItem.fromJson itemGroup', () {
    test('parses item_group when present', () {
      final item = PurchaseOrderItem.fromJson({
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'qty': 1,
        'received_qty': 0,
        'rate': 10,
        'amount': 10,
        'item_group': 'BELTS',
      });
      expect(item.itemGroup, 'BELTS');
    });

    test('defaults to empty string when item_group absent', () {
      final item = PurchaseOrderItem.fromJson({
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'qty': 1,
        'received_qty': 0,
        'rate': 10,
        'amount': 10,
      });
      expect(item.itemGroup, '');
    });
  });

  group('MaterialRequestItem.fromJson itemGroup', () {
    test('parses item_group when present', () {
      final item = MaterialRequestItem.fromJson({
        'item_code': 'ITEM-001',
        'variant_of': '',
        'qty': 1,
        'item_group': 'BELTS',
      });
      expect(item.itemGroup, 'BELTS');
    });

    test('defaults to empty string when item_group absent', () {
      final item = MaterialRequestItem.fromJson({
        'item_code': 'ITEM-001',
        'variant_of': '',
        'qty': 1,
      });
      expect(item.itemGroup, '');
    });
  });
}
