// Unit tests for StockEntryFormController — validateSheet composite gate.
// Covers:
//   Group 1 — batch guards
//   Group 2 — rack guards
//   Group 3 — MR serial / context guards
//   Group 4 — _hasChanges guard
//   Group 5 — stale (optimistic locking) block
//   Group 6 — auto-submit timer lifecycle
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'helpers/mock_providers.dart';

void main() {
  late StockEntryFormController controller;

  /// Helper: put the sheet into a fully-valid baseline state then let
  /// individual tests break exactly one constraint.
  void primeValidState() {
    controller.bsQtyController.text = '5';
    controller.bsBatchController.text = 'BATCH-001';
    controller.bsIsBatchValid.value = true;
    controller.bsMaxQty.value = 0.0;           // unconstrained
    controller.bsBatchBalance.value = 0.0;     // unconstrained
    controller.bsValidationMaxQty.value = 0.0; // unconstrained
    controller.isSourceRackValid.value = false;
    controller.isTargetRackValid.value = false;
    controller.bsSourceRackController.text = '';
    controller.bsTargetRackController.text = '';
    controller.currentItemNameKey.value = null; // new item → _hasChanges = true
    controller.selectedSerial.value = null;
    controller.entrySource = StockEntrySource.manual;
    controller.selectedStockEntryType.value = 'Material Transfer';
    controller.rackError.value = null;
    controller.batchError.value = null;
  }

  setUp(() {
    Get.testMode = true;
    registerFormFakes();
    controller = Get.put(StockEntryFormController());
    primeValidState();
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  // -------------------------------------------------------------------------
  // Group 1 — Batch guards
  // -------------------------------------------------------------------------
  group('validateSheet — batch guards', () {
    test('valid when batch is present and server-validated', () {
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('invalid when batch field is empty', () {
      controller.bsBatchController.text = '';
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });

    test('invalid when batch present but NOT server-validated', () {
      controller.bsIsBatchValid.value = false;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 2 — Rack guards (Material Transfer: both racks required)
  // -------------------------------------------------------------------------
  group('validateSheet — rack guards (Material Transfer)', () {
    setUp(() {
      controller.selectedStockEntryType.value = 'Material Transfer';
    });

    test('valid when both racks are filled and validated', () {
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = true;
      controller.bsTargetRackController.text = 'RACK-B2';
      controller.isTargetRackValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('invalid when source rack is filled but not server-validated', () {
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = false;
      controller.bsTargetRackController.text = 'RACK-B2';
      controller.isTargetRackValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });

    test('invalid when source == target rack', () {
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = true;
      controller.bsTargetRackController.text = 'RACK-A1'; // same!
      controller.isTargetRackValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
      expect(controller.rackError.value,
          contains('cannot be the same'));
    });

    test('source == target rack error is cleared when racks differ', () {
      // First set them equal to trigger the error.
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = true;
      controller.bsTargetRackController.text = 'RACK-A1';
      controller.isTargetRackValid.value = true;
      controller.validateSheet();
      expect(controller.rackError.value, isNotNull);

      // Now fix the target.
      controller.bsTargetRackController.text = 'RACK-B2';
      controller.validateSheet();
      expect(controller.rackError.value, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — Material Issue: only source rack required
  // -------------------------------------------------------------------------
  group('validateSheet — rack guards (Material Issue)', () {
    setUp(() {
      controller.selectedStockEntryType.value = 'Material Issue';
    });

    test('valid with source rack only', () {
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('invalid when source rack field is empty', () {
      controller.bsSourceRackController.text = '';
      controller.isSourceRackValid.value = false;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 4 — Material Receipt: only target rack required
  // -------------------------------------------------------------------------
  group('validateSheet — rack guards (Material Receipt)', () {
    setUp(() {
      controller.selectedStockEntryType.value = 'Material Receipt';
    });

    test('valid with target rack only', () {
      controller.bsTargetRackController.text = 'RACK-B2';
      controller.isTargetRackValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('invalid when target rack field is empty', () {
      controller.bsTargetRackController.text = '';
      controller.isTargetRackValid.value = false;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 5 — MR source context guards
  // -------------------------------------------------------------------------
  group('validateSheet — MR source context guards', () {
    setUp(() {
      controller.entrySource = StockEntrySource.materialRequest;
      controller.customReferenceNoController.text = 'MAT-MR-0001';
      // Provide a matching MR reference item
      controller.mrReferenceItems = [
        {
          'item_code': 'ITEM-001',
          'qty': 10.0,
          'material_request': 'MAT-MR-0001',
          'material_request_item': 'MAT-MR-0001-ITEM-1',
        }
      ];
      controller.currentItemCode = 'ITEM-001';
      controller.selectedStockEntryType.value = 'Material Transfer';
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = true;
      controller.bsTargetRackController.text = 'RACK-B2';
      controller.isTargetRackValid.value = true;
      controller.bsValidationMaxQty.value = 10.0;
    });

    test('invalid when no serial selected (MR source requires serial = "0")', () {
      controller.selectedSerial.value = null;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });

    test('valid when serial set to "0" (MR sentinel value)', () {
      controller.selectedSerial.value = '0';
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('invalid when item not in MR reference list', () {
      controller.currentItemCode = 'ITEM-NOT-IN-MR';
      controller.selectedSerial.value = '0';
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });

    test('invalid when qty exceeds MR requested qty', () {
      controller.selectedSerial.value = '0';
      controller.bsValidationMaxQty.value = 3.0;
      controller.bsQtyController.text = '4'; // exceeds MR limit of 3
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 6 — _hasChanges guard (edit mode)
  // -------------------------------------------------------------------------
  group('validateSheet — _hasChanges guard', () {
    setUp(() {
      // Simulate editing an existing item: set a nameKey and snapshots.
      controller.currentItemNameKey.value = 'existing-item-row-001';
      controller.setInitialSnapshot(
        qty: '5',
        batch: 'BATCH-001',
        sourceRack: 'RACK-A1',
        targetRack: 'RACK-B2',
      );
      controller.bsSourceRackController.text = 'RACK-A1';
      controller.isSourceRackValid.value = true;
      controller.bsTargetRackController.text = 'RACK-B2';
      controller.isTargetRackValid.value = true;
    });

    test('invalid when nothing has changed from the original snapshot', () {
      // All values match the snapshots
      controller.bsQtyController.text = '5';
      controller.bsBatchController.text = 'BATCH-001';
      controller.validateSheet();
      expect(controller.isSheetValid.value, isFalse);
    });

    test('valid when qty changes', () {
      controller.bsQtyController.text = '6';
      controller.bsBatchController.text = 'BATCH-001';
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('valid when batch changes', () {
      controller.bsQtyController.text = '5';
      controller.bsBatchController.text = 'BATCH-NEW';
      controller.bsIsBatchValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });

    test('valid when source rack changes', () {
      controller.bsQtyController.text = '5';
      controller.bsSourceRackController.text = 'RACK-C3';
      controller.isSourceRackValid.value = true;
      controller.validateSheet();
      expect(controller.isSheetValid.value, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 7 — Stale guard (optimistic locking)
  // -------------------------------------------------------------------------
  group('checkStaleAndBlock', () {
    test('returns true and blocks when document is stale', () {
      controller.isStale.value = true;
      expect(controller.checkStaleAndBlock(), isTrue);
    });

    test('returns false and allows action when document is fresh', () {
      controller.isStale.value = false;
      expect(controller.checkStaleAndBlock(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 8 — Double-save guard
  // -------------------------------------------------------------------------
  group('saveStockEntry — isSaving guard', () {
    test('second save call is no-op while first is in progress', () async {
      // Manually set isSaving to simulate an in-progress save.
      controller.isSaving.value = true;
      // saveStockEntry should return immediately without changing state.
      await controller.saveStockEntry();
      // isSaving is still true (we set it, save returned early without clearing)
      expect(controller.isSaving.value, isTrue);
    });
  });
}
