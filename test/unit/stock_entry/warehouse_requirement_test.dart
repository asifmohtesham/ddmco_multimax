// Unit Test #2 — Warehouse Requirement Gate
//
// Requirement:
//   Scanning must be blocked when the warehouse required for the current
//   Stock Entry type has not been selected. The gate is enforced by:
//     - requiresSourceWarehouse  (getter)
//     - requiresTargetWarehouse  (getter)
//     - enforceWarehouseBeforeScan()  (method → returns true = BLOCKED)
//
// Run: flutter test test/unit/stock_entry/warehouse_requirement_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

// ---------------------------------------------------------------------------
// Minimal stub — skips onInit() so no provider/service calls are made.
// All logic under test is pure state-machine logic with no I/O.
// ---------------------------------------------------------------------------
class _TestableFormController extends StockEntryFormController {
  @override
  void onInit() {}
}

void main() {
  late _TestableFormController ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _TestableFormController();
  });

  tearDown(() => Get.reset());

  // =========================================================================
  // requiresSourceWarehouse
  // =========================================================================
  group('requiresSourceWarehouse — which SE types demand a source warehouse', () {
    test('Material Issue requires a source warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      expect(ctrl.requiresSourceWarehouse, isTrue);
    });

    test('Material Transfer requires a source warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      expect(ctrl.requiresSourceWarehouse, isTrue);
    });

    test('Material Transfer for Manufacture requires a source warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      expect(ctrl.requiresSourceWarehouse, isTrue);
    });

    test('Material Receipt does NOT require a source warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      expect(ctrl.requiresSourceWarehouse, isFalse);
    });

    test('Unknown type does NOT require a source warehouse', () {
      ctrl.selectedStockEntryType.value = 'Some Unknown Type';
      expect(ctrl.requiresSourceWarehouse, isFalse);
    });
  });

  // =========================================================================
  // requiresTargetWarehouse
  // =========================================================================
  group('requiresTargetWarehouse — which SE types demand a target warehouse', () {
    test('Material Receipt requires a target warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      expect(ctrl.requiresTargetWarehouse, isTrue);
    });

    test('Material Transfer requires a target warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      expect(ctrl.requiresTargetWarehouse, isTrue);
    });

    test('Material Transfer for Manufacture requires a target warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      expect(ctrl.requiresTargetWarehouse, isTrue);
    });

    test('Material Issue does NOT require a target warehouse', () {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      expect(ctrl.requiresTargetWarehouse, isFalse);
    });

    test('Unknown type does NOT require a target warehouse', () {
      ctrl.selectedStockEntryType.value = 'Some Unknown Type';
      expect(ctrl.requiresTargetWarehouse, isFalse);
    });
  });

  // =========================================================================
  // enforceWarehouseBeforeScan — returns true (BLOCKED) / false (ALLOWED)
  // =========================================================================
  group('enforceWarehouseBeforeScan — source warehouse gate', () {
    setUp(() {
      // Use a type that needs ONLY a source warehouse.
      ctrl.selectedStockEntryType.value = 'Material Issue';
    });

    test('BLOCKS scan when source warehouse is null', () {
      ctrl.selectedFromWarehouse.value = null;
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue,
          reason: 'null source warehouse must block scanning.');
    });

    test('BLOCKS scan when source warehouse is empty string', () {
      ctrl.selectedFromWarehouse.value = '';
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue,
          reason: 'Empty-string source warehouse must block scanning.');
    });

    test('ALLOWS scan when source warehouse is set', () {
      ctrl.selectedFromWarehouse.value = 'Main Warehouse - DDMCO';
      expect(ctrl.enforceWarehouseBeforeScan(), isFalse,
          reason: 'Populated source warehouse must NOT block scanning.');
    });
  });

  group('enforceWarehouseBeforeScan — target warehouse gate', () {
    setUp(() {
      // Material Receipt needs ONLY a target warehouse.
      ctrl.selectedStockEntryType.value = 'Material Receipt';
    });

    test('BLOCKS scan when target warehouse is null', () {
      ctrl.selectedToWarehouse.value = null;
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue,
          reason: 'null target warehouse must block scanning.');
    });

    test('BLOCKS scan when target warehouse is empty string', () {
      ctrl.selectedToWarehouse.value = '';
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue,
          reason: 'Empty-string target warehouse must block scanning.');
    });

    test('ALLOWS scan when target warehouse is set', () {
      ctrl.selectedToWarehouse.value = 'Main Warehouse - DDMCO';
      expect(ctrl.enforceWarehouseBeforeScan(), isFalse,
          reason: 'Populated target warehouse must NOT block scanning.');
    });
  });

  group('enforceWarehouseBeforeScan — both warehouses required (Material Transfer)', () {
    setUp(() {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
    });

    test('BLOCKS when both warehouses are null', () {
      ctrl.selectedFromWarehouse.value = null;
      ctrl.selectedToWarehouse.value = null;
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue);
    });

    test('BLOCKS when only source warehouse is set (target still null)', () {
      ctrl.selectedFromWarehouse.value = 'Warehouse A - DDMCO';
      ctrl.selectedToWarehouse.value = null;
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue,
          reason: 'Source set but target missing must still block.');
    });

    test('BLOCKS when only target warehouse is set (source still null)', () {
      ctrl.selectedFromWarehouse.value = null;
      ctrl.selectedToWarehouse.value = 'Warehouse B - DDMCO';
      expect(ctrl.enforceWarehouseBeforeScan(), isTrue,
          reason: 'Target set but source missing must still block.');
    });

    test('ALLOWS scan when BOTH warehouses are set', () {
      ctrl.selectedFromWarehouse.value = 'Warehouse A - DDMCO';
      ctrl.selectedToWarehouse.value = 'Warehouse B - DDMCO';
      expect(ctrl.enforceWarehouseBeforeScan(), isFalse,
          reason: 'Both warehouses populated must allow scanning.');
    });

    test('ALLOWS scan when source and target warehouses are the same value '
        '(same-warehouse transfer is a Frappe server concern, not a client guard)', () {
      ctrl.selectedFromWarehouse.value = 'Warehouse A - DDMCO';
      ctrl.selectedToWarehouse.value = 'Warehouse A - DDMCO';
      expect(ctrl.enforceWarehouseBeforeScan(), isFalse,
          reason: 'Client should not block same-warehouse transfers; '
              'that validation belongs on the server.');
    });
  });

  group('enforceWarehouseBeforeScan — types that need no warehouses', () {
    test('ALLOWS scan for unknown type with no warehouses set '
        '(no requirement, no block)', () {
      ctrl.selectedStockEntryType.value = 'Some Unknown Type';
      ctrl.selectedFromWarehouse.value = null;
      ctrl.selectedToWarehouse.value = null;
      expect(ctrl.enforceWarehouseBeforeScan(), isFalse,
          reason: 'Types with no warehouse requirement must not block scanning.');
    });
  });

  // =========================================================================
  // Contract: requiresSourceWarehouse XOR requiresTargetWarehouse for
  //           Issue and Receipt types
  // =========================================================================
  group('Warehouse requirement symmetry contracts', () {
    test('Material Issue: source required, target NOT required', () {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      expect(ctrl.requiresSourceWarehouse, isTrue);
      expect(ctrl.requiresTargetWarehouse, isFalse);
    });

    test('Material Receipt: target required, source NOT required', () {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      expect(ctrl.requiresTargetWarehouse, isTrue);
      expect(ctrl.requiresSourceWarehouse, isFalse);
    });

    test('Material Transfer: BOTH source and target required', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      expect(ctrl.requiresSourceWarehouse, isTrue);
      expect(ctrl.requiresTargetWarehouse, isTrue);
    });

    test('Material Transfer for Manufacture: BOTH source and target required', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      expect(ctrl.requiresSourceWarehouse, isTrue);
      expect(ctrl.requiresTargetWarehouse, isTrue);
    });
  });
}
