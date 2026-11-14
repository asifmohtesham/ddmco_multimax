import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

void main() {
  group('StockEntryFormController.isDuplicateLine', () {
    StockEntryItem existingItem({
      double qty = 1,
      String itemCode = 'ITEM-1',
      String? batchNo = 'BATCH-1',
      String? rack = 'RACK-SRC',
      String? toRack = 'RACK-TGT',
      String? serial,
    }) =>
        StockEntryItem(
          itemCode: itemCode,
          qty: qty,
          basicRate: 0.0,
          batchNo: batchNo,
          rack: rack,
          toRack: toRack,
          customInvoiceSerialNumber: serial,
        );

    bool call(
      StockEntryItem existing, {
      String itemCode = 'ITEM-1',
      String? batch = 'BATCH-1',
      String? sourceRack = 'RACK-SRC',
      String? targetRack = 'RACK-TGT',
      String? serial,
    }) =>
        StockEntryFormController.isDuplicateLine(
          existing,
          itemCode: itemCode,
          batch: batch,
          sourceRack: sourceRack,
          targetRack: targetRack,
          serial: serial,
        );

    test('T-1: same item/batch/source-rack/target-rack → duplicate', () {
      expect(call(existingItem()), isTrue);
    });

    test('T-2: item code differs by case only → still duplicate', () {
      expect(
        call(existingItem(itemCode: 'item-1'), itemCode: 'ITEM-1'),
        isTrue,
      );
    });

    test('T-3: different item code → not duplicate', () {
      expect(
        call(existingItem(itemCode: 'ITEM-1'), itemCode: 'ITEM-2'),
        isFalse,
      );
    });

    test('T-4: different batch → not duplicate', () {
      expect(
        call(existingItem(batchNo: 'BATCH-1'), batch: 'BATCH-2'),
        isFalse,
      );
    });

    test('T-5: different source rack → not duplicate', () {
      expect(
        call(existingItem(rack: 'RACK-SRC-A'), sourceRack: 'RACK-SRC-B'),
        isFalse,
      );
    });

    test('T-6: same source rack but different target rack → not duplicate '
        '(dual-rack model requires both to match)', () {
      expect(
        call(existingItem(toRack: 'RACK-TGT-A'), targetRack: 'RACK-TGT-B'),
        isFalse,
      );
    });

    test('T-7: both racks null → duplicate (no rack tracking on this item)',
        () {
      expect(
        call(existingItem(rack: null, toRack: null),
            sourceRack: null, targetRack: null),
        isTrue,
      );
    });

    test('T-8: same item/batch/rack but different POS invoice serial → '
        'not duplicate (distinct POS invoice lines must stay separate)', () {
      expect(
        call(existingItem(serial: '1'), serial: '2'),
        isFalse,
      );
    });

    test('T-9: both null serial (non-POS entry) → duplicate', () {
      expect(
        call(existingItem(serial: null), serial: null),
        isTrue,
      );
    });

    test('T-10: null serial treated same as "0" (no POS context)', () {
      expect(
        call(existingItem(serial: '0'), serial: null),
        isTrue,
      );
    });
  });
}
