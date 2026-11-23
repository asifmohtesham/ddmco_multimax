import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_item_form_controller.dart';

import '../support/delivery_note_fixture.dart';

void main() {
  setUp(registerDeliveryNoteTestServices);
  tearDown(Get.reset);

  Future<DeliveryNoteItemFormController> openSheet(WidgetTester tester) async {
    final parent = await openNewDeliveryNote(tester);
    parent.setWarehouse.value = 'POS-Pick';
    final controller = Get.put(DeliveryNoteItemFormController());
    controller.initialise(parent: parent, code: 'ITEM-1', name: 'Test item');
    controller.batchController.text = 'BATCH-1';
    await controller.validateBatch('BATCH-1');
    controller.qtyController.text = '1';
    return controller;
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await Get.delete<DeliveryNoteItemFormController>();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('DeliveryNoteItemFormController.itemWarehouse', () {
    testWidgets('a fresh physical scan uses authoritative Rack metadata', (
      tester,
    ) async {
      final controller = await openSheet(tester);

      controller.applyRackScan('KA-WH-DXB1-101A');
      expect(controller.isCheckingRackWarehouse.value, isTrue);
      expect(controller.resolvedWarehouse, 'POS-Pick');
      await tester.pump();

      expect(controller.itemWarehouse.value, 'POS-Other');
      expect(controller.isSheetValid.value, isTrue);
      await closeSheet(tester);
    });

    testWidgets('an unknown rack keeps the previous warehouse visible', (
      tester,
    ) async {
      final controller = await openSheet(tester);
      controller.applyRackScan('RACK-POS-OTHER');
      await tester.pump();
      expect(controller.itemWarehouse.value, 'POS-Other');

      controller.applyRackScan('BADRACK');
      await tester.pump();

      expect(controller.itemWarehouse.value, 'POS-Other');
      expect(
        controller.rackError.value,
        'Rack BADRACK was not found. Scan or choose a Rack.',
      );
      expect(controller.isSheetValid.value, isFalse);
      await closeSheet(tester);
    });

    testWidgets('clearAll resets itemWarehouse to the document default', (
      tester,
    ) async {
      final controller = await openSheet(tester);
      controller.applyRackScan('RACK-POS-OTHER');
      await tester.pump();

      controller.clearAll();

      expect(controller.itemWarehouse.value, isNull);
      expect(controller.resolvedWarehouse, 'POS-Pick');
      await closeSheet(tester);
    });
  });

  // Choosing an invoice serial recalculates the voucher line quantity ceiling.
  test('changing serial revalidates the sheet', () async {
    final ctrl = Get.put(_ValidateSpy());
    ctrl.selectedSerial.value = '2';
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.validations, 1);
    ctrl.selectedSerial.value = '1';
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.validations, 2);
  });

  group('DeliveryNoteItemFormController rack is required', () {
    testWidgets('blank rack refuses add or update with a reason', (
      tester,
    ) async {
      final controller = await openSheet(tester);
      controller.rackController.text = '  ';

      await expectLater(
        controller.submit(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Scan or choose a rack'),
          ),
        ),
      );
      expect(controller.parent.items, isEmpty);
      await closeSheet(tester);
    });

    testWidgets('the refusal reason reaches the sheet', (tester) async {
      final controller = await openSheet(tester);
      final submission = controller.submitWithFeedback();
      await tester.pump(const Duration(milliseconds: 1500));

      expect(await submission, isFalse);
      expect(controller.submitError.value, 'Scan or choose a rack');
      await closeSheet(tester);
    });

    testWidgets('a matching rack passes the rack check and commits the row', (
      tester,
    ) async {
      final controller = await openSheet(tester);
      controller.rackController.text = 'RACK-POS-PICK';
      await controller.validateRack('RACK-POS-PICK');

      await controller.submit();

      expect(controller.parent.items.single.rack, 'RACK-POS-PICK');
      expect(controller.parent.items.single.warehouse, 'POS-Pick');
      await tester.pump();
      await closeSheet(tester);
      await tester.pump(deliveryNoteAutoSaveDelay + const Duration(seconds: 3));
    });
  });
}

class _ValidateSpy extends DeliveryNoteItemFormController {
  int validations = 0;

  @override
  void validateSheet() => validations++;
}
