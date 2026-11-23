import 'dart:async';

// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_item_form_controller.dart';

import '../support/delivery_note_fixture.dart';

void main() {
  late FakeDeliveryNoteApi api;

  setUp(() => api = registerDeliveryNoteTestServices());
  tearDown(Get.reset);

  testWidgets('choosing a warehouse on a new empty note creates nothing', (
    tester,
  ) async {
    final controller = await openNewDeliveryNote(tester);
    controller.setWarehouse.value = controller.warehouses.single;
    await tester.pump();
    await tester.pump(deliveryNoteAutoSaveDelay);

    expect(api.creates, isEmpty);
    expect(controller.setWarehouse.value, 'WH-Pick');
    expect(controller.bannerVisible.value, isFalse);
  });

  testWidgets('manual Save on a new empty note shows the validation banner', (
    tester,
  ) async {
    final controller = await openNewDeliveryNote(tester, renderForm: true);
    await tester.tap(find.byTooltip('Save'));
    await tester.pump();

    expect(api.creates, isEmpty);
    expect(controller.bannerVisible.value, isTrue);
    expect(find.text('Add an item before saving.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('adding the first item auto-saves exactly once', (tester) async {
    final controller = await openNewDeliveryNote(tester);
    controller.setWarehouse.value = controller.warehouses.single;
    await tester.pump();
    await tester.pump(deliveryNoteAutoSaveDelay);
    expect(api.creates, isEmpty);

    await controller.addItem(
      DeliveryNoteItem(itemCode: 'ITEM-1', qty: 1, rate: 0, rack: 'RACK-PICK'),
    );
    await tester.pump(deliveryNoteAutoSaveDelay);
    expect(controller.mode, 'edit', reason: controller.bannerMessage.value);
    await tester.pump(const Duration(seconds: 3));

    expect(api.creates, hasLength(1));
    expect(api.creates.single['set_warehouse'], 'WH-Pick');
    final rows = api.creates.single['items'] as List;
    expect(rows, hasLength(1));
    expect(rows.single['warehouse'], 'WH-Pick');
    expect(rows.single['rack'], 'RACK-PICK');
  });

  testWidgets('autosave and direct save refuse a mismatched source pair', (
    tester,
  ) async {
    final controller = await openNewDeliveryNote(tester);
    controller.setWarehouse.value = 'WH-Pick';
    await controller.addItem(
      DeliveryNoteItem(
        itemCode: 'ITEM-1',
        qty: 1,
        rate: 0,
        warehouse: 'WH-Pick',
        rack: 'RACK-TARGET',
      ),
    );
    await tester.pump(deliveryNoteAutoSaveDelay);
    await tester.pump();
    expect(api.creates, isEmpty);
    expect(
      controller.bannerMessage.value,
      'Row 1: Rack RACK-TARGET belongs to WH-Target. This row’s warehouse is WH-Pick.',
    );

    await controller.saveDocument();
    expect(api.creates, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('direct save checks the internal target side independently', (
    tester,
  ) async {
    final controller = await openNewDeliveryNote(tester);
    controller.setWarehouse.value = 'WH-Pick';
    await controller.addItem(
      DeliveryNoteItem(
        itemCode: 'ITEM-1',
        qty: 1,
        rate: 0,
        warehouse: 'WH-Pick',
        rack: 'RACK-PICK',
        targetWarehouse: 'WH-Target',
        toRack: 'RACK-PICK',
      ),
    );
    await controller.saveDocument();
    expect(api.creates, isEmpty);
    expect(
      controller.bannerMessage.value,
      'Row 1: Rack RACK-PICK belongs to WH-Pick. This row’s target warehouse is WH-Target.',
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('saved sheet checks source and internal target fields', (
    tester,
  ) async {
    final controller = await openNewDeliveryNote(tester);
    controller.setWarehouse.value = 'POS-Pick';
    final row = DeliveryNoteItem(
      name: 'DN-ROW-1',
      itemCode: 'ITEM-1',
      qty: 1,
      rate: 0,
      batchNo: 'BATCH-1',
      warehouse: 'POS-Pick',
      rack: 'RACK-POS-PICK',
      targetWarehouse: 'POS-Other',
      toRack: 'RACK-POS-OTHER',
    );
    controller.items.add(row);
    unawaited(controller.editItem(row));
    await tester.pumpAndSettle();
    final child = Get.find<DeliveryNoteItemFormController>();
    expect(child.isSheetValid.value, isTrue);
    expect(child.targetRackValid, isTrue);

    child.rackController.text = 'RACK-POS-OTHER';
    await child.validateRack('RACK-POS-OTHER');
    await tester.pump();
    expect(child.isSheetValid.value, isFalse);
    const mismatch =
        'Rack RACK-POS-OTHER belongs to POS-Other. This row’s warehouse is POS-Pick.';
    expect(child.rackError.value, mismatch);
    await tester.scrollUntilVisible(
      find.text(mismatch),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(mismatch), findsOneWidget);
    expect(controller.items.single.rack, 'RACK-POS-PICK');
    expect(api.creates, isEmpty);

    Get.back<void>();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'a stale fresh scan cannot replace the newer warehouse and rack',
    (tester) async {
      final controller = await openNewDeliveryNote(tester);
      controller.setWarehouse.value = 'POS-Pick';
      final child = Get.put(DeliveryNoteItemFormController());
      child.initialise(parent: controller, code: 'ITEM-1', name: 'Test item');
      final slow = Completer<RackWarehouseLookup>();
      api.pendingRacks['RACK-POS-PICK'] = slow;

      child.applyRackScan('RACK-POS-PICK');
      expect(child.isCheckingRackWarehouse.value, isTrue);
      child.applyRackScan('RACK-POS-OTHER');
      await tester.pump();
      expect(child.resolvedWarehouse, 'POS-Other');
      expect(child.isRackValid.value, isTrue);

      slow.complete(
        const RackWarehouseLookup.found('POS-Pick', name: 'RACK-POS-PICK'),
      );
      await tester.pump();
      expect(child.rackController.text, 'RACK-POS-OTHER');
      expect(child.resolvedWarehouse, 'POS-Other');
      expect(child.isRackValid.value, isTrue);

      await Get.delete<DeliveryNoteItemFormController>();
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets('batch input preserves a pending fresh rack initialization', (
    tester,
  ) async {
    final controller = await openNewDeliveryNote(tester);
    controller.setWarehouse.value = 'POS-Pick';
    final child = Get.put(DeliveryNoteItemFormController());
    child.initialise(parent: controller, code: 'ITEM-1', name: 'Test item');
    final slow = Completer<RackWarehouseLookup>();
    api.pendingRacks['RACK-POS-OTHER'] = slow;

    child.applyRackScan('RACK-POS-OTHER');
    child.batchController.text = 'BATCH-1';
    await child.validateBatch('BATCH-1');
    child.qtyController.text = '1';
    expect(child.resolvedWarehouse, 'POS-Other');
    expect(child.isSheetValid.value, isTrue);

    slow.complete(
      const RackWarehouseLookup.found('POS-Other', name: 'RACK-POS-OTHER'),
    );
    await tester.pump();
    expect(child.resolvedWarehouse, 'POS-Other');
    expect(child.isSheetValid.value, isTrue);

    await Get.delete<DeliveryNoteItemFormController>();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
