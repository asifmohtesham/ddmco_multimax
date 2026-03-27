// Unit tests for StockEntryItemFormController — Qty ceiling enforcement.
//
// Covers:
//   Group 1 — isValidQty against maxQty (stock balance ceiling)
//   Group 2 — isValidQty against batchBalance (batch-wise balance ceiling)
//   Group 3 — Effective ceiling = min(maxQty, batchBalance)
//   Group 4 — isValidQty against validationMaxQty (MR line limit)
//   Group 5 — adjustSheetQty stepper ceiling
//
// Uses makeItemCtrl() + primeValid() from helpers/item_form_helpers.dart so
// tests exercise the real controller logic with no network calls.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'helpers/item_form_helpers.dart';
import 'helpers/mock_providers.dart';

void main() {
  late StockEntryItemFormController ctrl;

  setUp(() {
    Get.testMode = true;
    registerFormFakes();
    ctrl = makeItemCtrl();
    // Prime a passing baseline (Material Issue — source rack only).
    // Individual groups override only the field they are testing.
    primeValid(ctrl, 'Material Issue');
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  // -------------------------------------------------------------------------
  // Group 1 — maxQty ceiling (Stock Balance)
  // -------------------------------------------------------------------------
  group('isValidQty — maxQty (stock balance) ceiling', () {
    setUp(() {
      // Isolate: disable batch-balance and MR ceiling so only maxQty is the gate.
      ctrl.batchBalance.value     = 0.0;
      ctrl.validationMaxQty.value = 0.0;
    });

    test('qty = 0 is always invalid', () {
      ctrl.maxQty.value        = 10.0;
      ctrl.qtyController.text  = '0';
      expect(ctrl.isValidQty(), isFalse);
    });

    test('qty < maxQty is valid', () {
      ctrl.maxQty.value        = 10.0;
      ctrl.qtyController.text  = '9';
      expect(ctrl.isValidQty(), isTrue);
    });

    test('qty = maxQty is valid (exact match)', () {
      ctrl.maxQty.value        = 10.0;
      ctrl.qtyController.text  = '10';
      expect(ctrl.isValidQty(), isTrue);
    });

    test('qty > maxQty is invalid', () {
      ctrl.maxQty.value        = 10.0;
      ctrl.qtyController.text  = '11';
      expect(ctrl.isValidQty(), isFalse);
    });

    test('maxQty = 0 disables the ceiling (no stock data fetched yet)', () {
      // When maxQty is 0 the controller treats the ceiling as unconstrained.
      ctrl.maxQty.value        = 0.0;
      ctrl.qtyController.text  = '999';
      expect(ctrl.isValidQty(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 2 — batchBalance ceiling (Batch-Wise Balance)
  // -------------------------------------------------------------------------
  group('isValidQty — batchBalance (batch-wise balance) ceiling', () {
    setUp(() {
      // Isolate: disable maxQty and MR ceiling so only batchBalance is the gate.
      ctrl.maxQty.value           = 0.0;
      ctrl.validationMaxQty.value = 0.0;
    });

    test('qty <= batchBalance is valid', () {
      ctrl.batchBalance.value  = 5.0;
      ctrl.qtyController.text  = '5';
      expect(ctrl.isValidQty(), isTrue);
    });

    test('qty > batchBalance is invalid', () {
      ctrl.batchBalance.value  = 5.0;
      ctrl.qtyController.text  = '6';
      expect(ctrl.isValidQty(), isFalse);
    });

    test('batchBalance = 0 disables the ceiling', () {
      ctrl.batchBalance.value  = 0.0;
      ctrl.qtyController.text  = '999';
      expect(ctrl.isValidQty(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — Effective ceiling = min(maxQty, batchBalance)
  // -------------------------------------------------------------------------
  group('isValidQty — effective ceiling is the tighter of both', () {
    setUp(() => ctrl.validationMaxQty.value = 0.0);

    test('qty within both ceilings is valid', () {
      ctrl.maxQty.value        = 10.0;
      ctrl.batchBalance.value  = 8.0;
      ctrl.qtyController.text  = '8';
      expect(ctrl.isValidQty(), isTrue);
    });

    test('qty within maxQty but exceeds batchBalance is invalid', () {
      ctrl.maxQty.value        = 10.0;
      ctrl.batchBalance.value  = 5.0;
      ctrl.qtyController.text  = '7'; // 7 <= 10 but 7 > 5
      expect(ctrl.isValidQty(), isFalse);
    });

    test('qty within batchBalance but exceeds maxQty is invalid', () {
      ctrl.maxQty.value        = 4.0;
      ctrl.batchBalance.value  = 10.0;
      ctrl.qtyController.text  = '5'; // 5 <= 10 but 5 > 4
      expect(ctrl.isValidQty(), isFalse);
    });

    test('effective ceiling equals min — qty at exact min is valid', () {
      ctrl.maxQty.value        = 8.0;
      ctrl.batchBalance.value  = 5.0;
      ctrl.qtyController.text  = '5'; // equals batchBalance (tighter)
      expect(ctrl.isValidQty(), isTrue);
    });

    test('qty one above min ceiling is invalid', () {
      ctrl.maxQty.value        = 8.0;
      ctrl.batchBalance.value  = 5.0;
      ctrl.qtyController.text  = '6';
      expect(ctrl.isValidQty(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 4 — validationMaxQty ceiling (MR line limit)
  // -------------------------------------------------------------------------
  group('isValidQty — validationMaxQty (MR line limit) ceiling', () {
    setUp(() {
      // Isolate: disable stock-balance and batch-balance ceilings.
      ctrl.maxQty.value       = 0.0;
      ctrl.batchBalance.value = 0.0;
    });

    test('qty <= validationMaxQty is valid', () {
      ctrl.validationMaxQty.value = 3.0;
      ctrl.qtyController.text     = '3';
      expect(ctrl.isValidQty(), isTrue);
    });

    test('qty > validationMaxQty is invalid', () {
      ctrl.validationMaxQty.value = 3.0;
      ctrl.qtyController.text     = '4';
      expect(ctrl.isValidQty(), isFalse);
    });

    test('validationMaxQty = 0 disables MR ceiling', () {
      ctrl.validationMaxQty.value = 0.0;
      ctrl.qtyController.text     = '50';
      expect(ctrl.isValidQty(), isTrue);
    });

    test('all three ceilings active — tightest wins', () {
      ctrl.maxQty.value           = 20.0;
      ctrl.batchBalance.value     = 10.0;
      ctrl.validationMaxQty.value = 4.0;
      ctrl.qtyController.text     = '5'; // 5 > 4 (MR ceiling)
      expect(ctrl.isValidQty(), isFalse);
      ctrl.qtyController.text     = '4';
      expect(ctrl.isValidQty(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 5 — adjustSheetQty stepper
  // -------------------------------------------------------------------------
  group('adjustSheetQty — stepper is capped at effective ceiling', () {
    test('increment is blocked at maxQty', () {
      ctrl.maxQty.value           = 3.0;
      ctrl.batchBalance.value     = 0.0;
      ctrl.validationMaxQty.value = 0.0;
      ctrl.qtyController.text     = '3';
      ctrl.adjustSheetQty(1);
      expect(ctrl.qtyController.text, equals('3'));
    });

    test('increment is blocked at batchBalance when tighter', () {
      ctrl.maxQty.value           = 10.0;
      ctrl.batchBalance.value     = 2.0;
      ctrl.validationMaxQty.value = 0.0;
      ctrl.qtyController.text     = '2';
      ctrl.adjustSheetQty(1);
      expect(ctrl.qtyController.text, equals('2'));
    });

    test('decrement is always allowed down to 1', () {
      ctrl.maxQty.value       = 10.0;
      ctrl.batchBalance.value = 10.0;
      ctrl.qtyController.text = '5';
      ctrl.adjustSheetQty(-1);
      expect(ctrl.qtyController.text, equals('4'));
    });

    test('decrement at 1 does not go below 1', () {
      ctrl.qtyController.text = '1';
      ctrl.adjustSheetQty(-1);
      expect(ctrl.qtyController.text, equals('1'));
    });
  });
}
