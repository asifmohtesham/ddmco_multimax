import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_item_form_controller.dart';

void main() {
  group('DeliveryNoteItemFormController.isDuplicateLine', () {
    DeliveryNoteItem item({
      double qty = 1,
      String itemCode = 'ITEM-1',
      String? batchNo = 'BATCH-1',
      String? rack = 'RACK-1',
      String? serial,
    }) =>
        DeliveryNoteItem(
          itemCode: itemCode,
          qty: qty,
          rate: 0.0,
          batchNo: batchNo,
          rack: rack,
          customInvoiceSerialNumber: serial,
        );

    test('T-1: same item/batch/rack → duplicate', () {
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(item(), item()),
        isTrue,
      );
    });

    test('T-2: item code differs by case only → still duplicate', () {
      final existing = item(itemCode: 'item-1');
      final incoming = item(itemCode: 'ITEM-1');
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isTrue,
      );
    });

    test('T-3: different item code → not duplicate', () {
      final existing = item(itemCode: 'ITEM-1');
      final incoming = item(itemCode: 'ITEM-2');
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isFalse,
      );
    });

    test('T-4: different batch → not duplicate', () {
      final existing = item(batchNo: 'BATCH-1');
      final incoming = item(batchNo: 'BATCH-2');
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isFalse,
      );
    });

    test('T-5: different rack → not duplicate', () {
      final existing = item(rack: 'RACK-1');
      final incoming = item(rack: 'RACK-2');
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isFalse,
      );
    });

    test('T-6: both racks null → duplicate (no rack tracking on this item)',
        () {
      final existing = item(rack: null);
      final incoming = item(rack: null);
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isTrue,
      );
    });

    test('T-7: same item/batch/rack but different POS invoice serial → '
        'not duplicate (distinct POS invoice lines must stay separate)', () {
      final existing = item(serial: '1');
      final incoming = item(serial: '2');
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isFalse,
      );
    });

    test('T-8: both null serial (non-POS entry) → duplicate', () {
      final existing = item(serial: null);
      final incoming = item(serial: null);
      expect(
        DeliveryNoteItemFormController.isDuplicateLine(existing, incoming),
        isTrue,
      );
    });
  });
}
