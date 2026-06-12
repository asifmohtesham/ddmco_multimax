import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_options.dart';

void main() {
  group('buildPsSerialOptions', () {
    DeliveryNoteItem dnItem({
      required String name,
      required String itemCode,
      String? serial = '1',
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

    test('returns one option per matching serial sorted numerically', () {
      final items = [
        dnItem(name: 'r10', itemCode: 'ITEM-A', serial: '10'),
        dnItem(name: 'r2', itemCode: 'ITEM-A', serial: '2'),
        dnItem(name: 'rB', itemCode: 'ITEM-B', serial: '1'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => 12.0,
      );

      expect(options.map((o) => o.serial).toList(), equals(['2', '10']));
      expect(options.first.dnRow.name, equals('r2'));
    });

    test('excludes rows with null, empty, or sentinel "0" serials', () {
      final items = [
        dnItem(name: 'r1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'r0', itemCode: 'ITEM-A', serial: '0'),
        dnItem(name: 'rEmpty', itemCode: 'ITEM-A', serial: ''),
        dnItem(name: 'rNull', itemCode: 'ITEM-A', serial: null),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => 12.0,
      );

      expect(options.map((o) => o.serial).toList(), equals(['1']));
    });

    test('filters by batch when a batch is scanned', () {
      final items = [
        dnItem(name: 'rX', itemCode: 'ITEM-A', serial: '1', batchNo: 'BATCH-X'),
        dnItem(name: 'rY', itemCode: 'ITEM-A', serial: '2', batchNo: 'BATCH-Y'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: 'BATCH-Y',
        remainingQty: (i) => 12.0,
      );

      expect(options.map((o) => o.serial).toList(), equals(['2']));
    });

    test('carries DN row qty and remaining per option', () {
      final items = [
        dnItem(name: 'r1', itemCode: 'ITEM-A', serial: '1', qty: 12.0),
        dnItem(name: 'r2', itemCode: 'ITEM-A', serial: '2', qty: 5.0),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => i.name == 'r1' ? 0.0 : 5.0,
      );

      expect(options[0].qty, equals(12.0));
      expect(options[0].remaining, equals(0.0));
      expect(options[1].qty, equals(5.0));
      expect(options[1].remaining, equals(5.0));
    });

    test('dedupes same-serial rows preferring the one with remaining', () {
      final items = [
        dnItem(name: 'full', itemCode: 'ITEM-A', serial: '1', batchNo: 'X'),
        dnItem(name: 'open', itemCode: 'ITEM-A', serial: '1', batchNo: 'Y'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => i.name == 'open' ? 3.0 : 0.0,
      );

      expect(options, hasLength(1));
      expect(options.single.dnRow.name, equals('open'));
    });

    test('dedupe falls back to first row when all exhausted', () {
      final items = [
        dnItem(name: 'a', itemCode: 'ITEM-A', serial: '1', batchNo: 'X'),
        dnItem(name: 'b', itemCode: 'ITEM-A', serial: '1', batchNo: 'Y'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => 0.0,
      );

      expect(options.single.dnRow.name, equals('a'));
    });

    test('returns empty list when nothing matches', () {
      final options = buildPsSerialOptions(
        items: [dnItem(name: 'r1', itemCode: 'ITEM-A')],
        code: 'ITEM-Z',
        batch: null,
        remainingQty: (i) => 12.0,
      );

      expect(options, isEmpty);
    });
  });
}
