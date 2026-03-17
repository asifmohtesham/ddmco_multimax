// Unit tests for StockEntryFormController — Entry Source determination.
// Covers:
//   Group 1 — _determineSource (all five branches)
//   Group 2 — isMaterialRequestEntry getter
//   Group 3 — warehouse requirement getters
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'helpers/mock_providers.dart';

void main() {
  late StockEntryFormController controller;

  setUp(() {
    Get.testMode = true;
    registerFormFakes();
    // Instantiate in 'view' mode so onInit does not fire a network call.
    controller = Get.put(
      StockEntryFormController(),
      // Pass view mode via arguments simulation is not needed because we call
      // determineSource / requiresXxx directly.
    );
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  // -------------------------------------------------------------------------
  // Group 1 — Entry source determination
  // -------------------------------------------------------------------------
  group('determineSource', () {
    test('KX prefix + Material Issue → posUpload', () {
      controller.determineSource('Material Issue', 'KX-00123');
      expect(controller.entrySource, StockEntrySource.posUpload);
    });

    test('MX prefix + Material Issue → posUpload', () {
      controller.determineSource('Material Issue', 'MX-00456');
      expect(controller.entrySource, StockEntrySource.posUpload);
    });

    test('KX prefix + Material Transfer is NOT posUpload → materialRequest', () {
      // Only Material Issue + KX/MX is posUpload; any other type falls to
      // the non-empty ref branch → materialRequest.
      controller.determineSource('Material Transfer', 'KX-00789');
      expect(controller.entrySource, StockEntrySource.materialRequest);
    });

    test('MAT-MR ref + Material Transfer → materialRequest', () {
      controller.determineSource('Material Transfer', 'MAT-MR-0001');
      expect(controller.entrySource, StockEntrySource.materialRequest);
    });

    test('non-empty arbitrary ref → materialRequest', () {
      controller.determineSource('Material Issue', 'SOME-REF-001');
      // SOME-REF does not start with KX/MX so falls to non-empty ref branch.
      expect(controller.entrySource, StockEntrySource.materialRequest);
    });

    test('empty ref + any type → manual', () {
      controller.determineSource('Material Transfer', '');
      expect(controller.entrySource, StockEntrySource.manual);
    });

    test('empty ref + Material Issue → manual', () {
      controller.determineSource('Material Issue', '');
      expect(controller.entrySource, StockEntrySource.manual);
    });
  });

  // -------------------------------------------------------------------------
  // Group 2 — isMaterialRequestEntry
  // -------------------------------------------------------------------------
  group('isMaterialRequestEntry', () {
    test('returns true when customReferenceNo starts with MAT-MR-', () {
      controller.customReferenceNoController.text = 'MAT-MR-0001';
      expect(controller.isMaterialRequestEntry, isTrue);
    });

    test('returns false for KX prefix', () {
      controller.customReferenceNoController.text = 'KX-00123';
      expect(controller.isMaterialRequestEntry, isFalse);
    });

    test('returns false for empty string', () {
      controller.customReferenceNoController.text = '';
      expect(controller.isMaterialRequestEntry, isFalse);
    });

    test('returns false for arbitrary non-MR ref', () {
      controller.customReferenceNoController.text = 'PO-00001';
      expect(controller.isMaterialRequestEntry, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — Warehouse requirement getters
  // Requirement 2: Source mandatory for Material Issue / Transfer
  // Requirement 3: Target mandatory for Material Receipt / Transfer
  // -------------------------------------------------------------------------
  group('requiresSourceWarehouse', () {
    test('Material Issue requires source warehouse', () {
      controller.selectedStockEntryType.value = 'Material Issue';
      expect(controller.requiresSourceWarehouse, isTrue);
    });

    test('Material Transfer requires source warehouse', () {
      controller.selectedStockEntryType.value = 'Material Transfer';
      expect(controller.requiresSourceWarehouse, isTrue);
    });

    test('Material Transfer for Manufacture requires source warehouse', () {
      controller.selectedStockEntryType.value =
          'Material Transfer for Manufacture';
      expect(controller.requiresSourceWarehouse, isTrue);
    });

    test('Material Receipt does NOT require source warehouse', () {
      controller.selectedStockEntryType.value = 'Material Receipt';
      expect(controller.requiresSourceWarehouse, isFalse);
    });
  });

  group('requiresTargetWarehouse', () {
    test('Material Receipt requires target warehouse', () {
      controller.selectedStockEntryType.value = 'Material Receipt';
      expect(controller.requiresTargetWarehouse, isTrue);
    });

    test('Material Transfer requires target warehouse', () {
      controller.selectedStockEntryType.value = 'Material Transfer';
      expect(controller.requiresTargetWarehouse, isTrue);
    });

    test('Material Transfer for Manufacture requires target warehouse', () {
      controller.selectedStockEntryType.value =
          'Material Transfer for Manufacture';
      expect(controller.requiresTargetWarehouse, isTrue);
    });

    test('Material Issue does NOT require target warehouse', () {
      controller.selectedStockEntryType.value = 'Material Issue';
      expect(controller.requiresTargetWarehouse, isFalse);
    });
  });
}
