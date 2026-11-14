import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/dn_scan_item_matcher.dart';

void main() {
  group('findScannedDnItem', () {
    DeliveryNoteItem dnItem({
      required String name,
      required String itemCode,
      String serial = '1',
      String? batchNo,
      double qty = 12.0,
    }) =>
        DeliveryNoteItem(
          name: name,
          itemCode: itemCode,
          qty: qty,
          rate: 10.0,
          customInvoiceSerialNumber: serial,
          docstatus: 1,
          batchNo: batchNo,
        );

    test('returns first matching row when it still has remaining qty', () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => 12.0,
      );

      expect(match?.name, equals('row-1'));
    });

    test('advances to next matching row when first row is fully packed', () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
        dnItem(name: 'row-3', itemCode: 'ITEM-A', serial: '3'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => item.name == 'row-1' ? 0.0 : 12.0,
      );

      expect(match?.name, equals('row-2'));
    });

    test('skips all exhausted rows and returns the last one with remaining',
        () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
        dnItem(name: 'row-3', itemCode: 'ITEM-A', serial: '3'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => item.name == 'row-3' ? 5.0 : 0.0,
      );

      expect(match?.name, equals('row-3'));
    });

    test('falls back to first matching row when every row is fully packed',
        () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => 0.0,
      );

      expect(match?.name, equals('row-1'));
    });

    test('returns null when no row matches the item code', () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-B',
        batch: null,
        remainingQty: (item) => 12.0,
      );

      expect(match, isNull);
    });

    test('ignores rows whose batch does not match the scanned batch', () {
      final items = [
        dnItem(name: 'row-x', itemCode: 'ITEM-A', batchNo: 'BATCH-X'),
        dnItem(name: 'row-y', itemCode: 'ITEM-A', batchNo: 'BATCH-Y'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: 'BATCH-Y',
        remainingQty: (item) => 12.0,
      );

      expect(match?.name, equals('row-y'));
    });

    test('prefers unexhausted row among same-batch matches', () {
      final items = [
        dnItem(name: 'row-x1', itemCode: 'ITEM-A', batchNo: 'BATCH-X'),
        dnItem(name: 'row-x2', itemCode: 'ITEM-A', batchNo: 'BATCH-X'),
        dnItem(name: 'row-y', itemCode: 'ITEM-A', batchNo: 'BATCH-Y'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: 'BATCH-X',
        remainingQty: (item) => item.name == 'row-x1' ? 0.0 : 12.0,
      );

      expect(match?.name, equals('row-x2'));
    });

    test('skips rows flagged by skipRow and advances to the next packable row',
        () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => 12.0,
        skipRow: (item) => item.name == 'row-1',
      );

      expect(match?.name, equals('row-2'));
    });

    test('returns null when every matching row is skipped', () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => 12.0,
        skipRow: (item) => true,
      );

      expect(match, isNull);
    });
  });
}
