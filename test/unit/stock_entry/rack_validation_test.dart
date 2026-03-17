// Unit Test #3 — Rack Validation Logic
//
// Requirement:
//   The item form sheet must enforce rack presence and server-validation flags
//   before allowing an item to be added. isValidRacks() is the pure-logic
//   gate that isSheetValid depends on.
//
// Rules encoded in isValidRacks():
//   - Source rack (non-empty + isSourceRackValid) required for:
//       Material Issue, Material Transfer, Material Transfer for Manufacture
//   - Target rack (non-empty + isTargetRackValid) required for:
//       Material Receipt, Material Transfer, Material Transfer for Manufacture
//   - When BOTH racks are required, source != target
//
// Run: flutter test test/unit/stock_entry/rack_validation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

class _TestableFormController extends StockEntryFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Helpers to set rack state without going through async validateRack().
// ---------------------------------------------------------------------------
void _setSourceRack(_TestableFormController c, String rack,
    {bool valid = true}) {
  c.bsSourceRackController.text = rack;
  c.isSourceRackValid.value = valid;
}

void _setTargetRack(_TestableFormController c, String rack,
    {bool valid = true}) {
  c.bsTargetRackController.text = rack;
  c.isTargetRackValid.value = valid;
}

void main() {
  late _TestableFormController ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _TestableFormController();
    // Reset any stale rackError that may interfere.
    ctrl.rackError.value = null;
  });

  tearDown(() => Get.reset());

  // =========================================================================
  // Material Issue — source rack only
  // =========================================================================
  group('isValidRacks — Material Issue (source rack required only)', () {
    setUp(() => ctrl.selectedStockEntryType.value = 'Material Issue');

    test('INVALID when source rack is empty', () {
      _setSourceRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when source rack text present but not server-validated', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: false);
      expect(ctrl.isValidRacks(), isFalse,
          reason: 'Server validation flag must be true before rack is accepted.');
    });

    test('VALID when source rack is present and validated', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      expect(ctrl.isValidRacks(), isTrue);
    });

    test('Target rack is irrelevant for Material Issue — '
        'VALID even with no target rack set', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isTrue,
          reason: 'Material Issue has no target-rack requirement.');
    });
  });

  // =========================================================================
  // Material Receipt — target rack only
  // =========================================================================
  group('isValidRacks — Material Receipt (target rack required only)', () {
    setUp(() => ctrl.selectedStockEntryType.value = 'Material Receipt');

    test('INVALID when target rack is empty', () {
      _setTargetRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when target rack text present but not server-validated', () {
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('VALID when target rack is present and validated', () {
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: true);
      expect(ctrl.isValidRacks(), isTrue);
    });

    test('Source rack is irrelevant for Material Receipt — '
        'VALID even with no source rack set', () {
      _setSourceRack(ctrl, '', valid: false);
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: true);
      expect(ctrl.isValidRacks(), isTrue,
          reason: 'Material Receipt has no source-rack requirement.');
    });
  });

  // =========================================================================
  // Material Transfer — both racks required, must differ
  // =========================================================================
  group('isValidRacks — Material Transfer (both racks required, must differ)', () {
    setUp(() => ctrl.selectedStockEntryType.value = 'Material Transfer');

    test('INVALID when both racks are empty', () {
      _setSourceRack(ctrl, '', valid: false);
      _setTargetRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when source rack is empty (target set)', () {
      _setSourceRack(ctrl, '', valid: false);
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: true);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when target rack is empty (source set)', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when source rack present but not server-validated', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: false);
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: true);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when target rack present but not server-validated', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when source and target racks are the same (duplicate check)', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-A1-01', valid: true);
      expect(ctrl.isValidRacks(), isFalse,
          reason: 'Transferring from a rack to itself must be blocked.');
    });

    test('rackError is set to the canonical message when racks are the same', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-A1-01', valid: true);
      ctrl.isValidRacks();
      expect(ctrl.rackError.value,
          equals('Source and Target Racks cannot be the same'));
    });

    test('VALID when both racks are set, validated, and different', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: true);
      expect(ctrl.isValidRacks(), isTrue);
    });

    test('rackError is cleared after valid distinct racks are set', () {
      // First set same-rack to trigger the error ...
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-A1-01', valid: true);
      ctrl.isValidRacks();
      expect(ctrl.rackError.value, isNotNull);

      // ... then correct it — error must be cleared.
      _setTargetRack(ctrl, 'DDMCO-B2-03', valid: true);
      ctrl.isValidRacks();
      expect(ctrl.rackError.value, isNull,
          reason: 'rackError must be cleared once racks differ.');
    });
  });

  // =========================================================================
  // Material Transfer for Manufacture — same rules as Material Transfer
  // =========================================================================
  group('isValidRacks — Material Transfer for Manufacture '
      '(same rules as Material Transfer)', () {
    setUp(() =>
        ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture');

    test('INVALID when both racks empty', () {
      _setSourceRack(ctrl, '', valid: false);
      _setTargetRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('INVALID when racks are the same', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-A1-01', valid: true);
      expect(ctrl.isValidRacks(), isFalse);
    });

    test('VALID when both racks differ and are validated', () {
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, 'DDMCO-C3-07', valid: true);
      expect(ctrl.isValidRacks(), isTrue);
    });
  });

  // =========================================================================
  // Boundary: type with no rack requirement
  // =========================================================================
  group('isValidRacks — no-rack-requirement types', () {
    test('Unknown SE type: VALID even with no racks (no requirement defined)', () {
      ctrl.selectedStockEntryType.value = 'Some Unknown Type';
      _setSourceRack(ctrl, '', valid: false);
      _setTargetRack(ctrl, '', valid: false);
      expect(ctrl.isValidRacks(), isTrue,
          reason: 'Types with no rack rules must not gate submission.');
    });
  });

  // =========================================================================
  // rackError lifecycle contract
  // =========================================================================
  group('rackError lifecycle', () {
    test('rackError starts null for a fresh controller', () {
      expect(ctrl.rackError.value, isNull);
    });

    test('rackError is set ONLY when both racks are required and identical '
        '(not when just one rack is missing)', () {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      _setSourceRack(ctrl, 'DDMCO-A1-01', valid: true);
      _setTargetRack(ctrl, '', valid: false);  // different — target just missing
      ctrl.isValidRacks();
      expect(ctrl.rackError.value,
          isNot(equals('Source and Target Racks cannot be the same')),
          reason: 'The canonical duplicate-rack error must not appear '
              'when target is simply absent.');
    });
  });
}
