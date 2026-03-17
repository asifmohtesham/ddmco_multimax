// Unit tests for StockEntryFormController — Qty ceiling enforcement.
// Covers:
//   Group 1 — isValidQty against bsMaxQty (stock balance)
//   Group 2 — isValidQty against bsBatchBalance (batch-wise balance)
//   Group 3 — Effective ceiling = min(bsMaxQty, bsBatchBalance)
//   Group 4 — adjustSheetQty stepper ceiling
//   Group 5 — bsValidationMaxQty (MR ceiling)
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'helpers/mock_providers.dart';

void main() {
  late StockEntryFormController controller;

  setUp(() {
    Get.testMode = true;
    registerFormFakes();
    controller = Get.put(StockEntryFormController());
    // Prime a valid batch so batch-related guards are not the failure point
    // in stock-balance focused tests.
    controller.bsBatchController.text = 'BATCH-001';
    controller.bsIsBatchValid.value = true;
    // Set item name key to null so _hasChanges always returns true
    // (new item path — no initial snapshot to compare against).
    controller.currentItemNameKey.value = null;
  });

  tearDown(() async {
    await Get.deleteAll(force: true);
  });

  // -------------------------------------------------------------------------
  // Group 1 — bsMaxQty ceiling (Stock Balance)
  // -------------------------------------------------------------------------
  group('isValidQty — bsMaxQty (stock balance) ceiling', () {
    setUp(() {
      controller.bsBatchBalance.value = 0.0; // disabled — not the gate here
      controller.bsValidationMaxQty.value = 0.0;
    });

    test('qty = 0 is always invalid', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsQtyController.text = '0';
      expect(controller.isValidQty(), isFalse);
    });

    test('qty < bsMaxQty is valid', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsQtyController.text = '9';
      expect(controller.isValidQty(), isTrue);
    });

    test('qty = bsMaxQty is valid (exact match)', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsQtyController.text = '10';
      expect(controller.isValidQty(), isTrue);
    });

    test('qty > bsMaxQty is invalid', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsQtyController.text = '11';
      expect(controller.isValidQty(), isFalse);
    });

    test('bsMaxQty = 0 disables the ceiling (no stock data fetched yet)', () {
      // When bsMaxQty is 0 the controller treats the ceiling as unconstrained.
      controller.bsMaxQty.value = 0.0;
      controller.bsQtyController.text = '999';
      expect(controller.isValidQty(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 2 — bsBatchBalance ceiling (Batch-Wise Balance)
  // -------------------------------------------------------------------------
  group('isValidQty — bsBatchBalance (batch-wise balance) ceiling', () {
    setUp(() {
      controller.bsMaxQty.value = 0.0; // disabled
      controller.bsValidationMaxQty.value = 0.0;
    });

    test('qty <= bsBatchBalance is valid', () {
      controller.bsBatchBalance.value = 5.0;
      controller.bsQtyController.text = '5';
      expect(controller.isValidQty(), isTrue);
    });

    test('qty > bsBatchBalance is invalid', () {
      controller.bsBatchBalance.value = 5.0;
      controller.bsQtyController.text = '6';
      expect(controller.isValidQty(), isFalse);
    });

    test('bsBatchBalance = 0 disables the ceiling', () {
      controller.bsBatchBalance.value = 0.0;
      controller.bsQtyController.text = '999';
      expect(controller.isValidQty(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — Effective ceiling = min(bsMaxQty, bsBatchBalance)
  // -------------------------------------------------------------------------
  group('isValidQty — effective ceiling is the tighter of both', () {
    setUp(() => controller.bsValidationMaxQty.value = 0.0);

    test('qty within both ceilings is valid', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsBatchBalance.value = 8.0;
      controller.bsQtyController.text = '8';
      expect(controller.isValidQty(), isTrue);
    });

    test('qty within bsMaxQty but exceeds bsBatchBalance is invalid', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsBatchBalance.value = 5.0;
      controller.bsQtyController.text = '7'; // 7 <= 10 but 7 > 5
      expect(controller.isValidQty(), isFalse);
    });

    test('qty within bsBatchBalance but exceeds bsMaxQty is invalid', () {
      controller.bsMaxQty.value = 4.0;
      controller.bsBatchBalance.value = 10.0;
      controller.bsQtyController.text = '5'; // 5 <= 10 but 5 > 4
      expect(controller.isValidQty(), isFalse);
    });

    test('effective ceiling equals min — qty at exact min is valid', () {
      controller.bsMaxQty.value = 8.0;
      controller.bsBatchBalance.value = 5.0;
      controller.bsQtyController.text = '5'; // equals bsBatchBalance (tighter)
      expect(controller.isValidQty(), isTrue);
    });

    test('qty one above min ceiling is invalid', () {
      controller.bsMaxQty.value = 8.0;
      controller.bsBatchBalance.value = 5.0;
      controller.bsQtyController.text = '6';
      expect(controller.isValidQty(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 4 — bsValidationMaxQty ceiling (MR limit)
  // -------------------------------------------------------------------------
  group('isValidQty — bsValidationMaxQty (MR line limit) ceiling', () {
    setUp(() {
      controller.bsMaxQty.value = 0.0;
      controller.bsBatchBalance.value = 0.0;
    });

    test('qty <= bsValidationMaxQty is valid', () {
      controller.bsValidationMaxQty.value = 3.0;
      controller.bsQtyController.text = '3';
      expect(controller.isValidQty(), isTrue);
    });

    test('qty > bsValidationMaxQty is invalid', () {
      controller.bsValidationMaxQty.value = 3.0;
      controller.bsQtyController.text = '4';
      expect(controller.isValidQty(), isFalse);
    });

    test('bsValidationMaxQty = 0 disables MR ceiling', () {
      controller.bsValidationMaxQty.value = 0.0;
      controller.bsQtyController.text = '50';
      expect(controller.isValidQty(), isTrue);
    });

    test('all three ceilings active — tightest wins', () {
      controller.bsMaxQty.value = 20.0;
      controller.bsBatchBalance.value = 10.0;
      controller.bsValidationMaxQty.value = 4.0;
      controller.bsQtyController.text = '5'; // 5 > 4 (MR ceiling)
      expect(controller.isValidQty(), isFalse);
      controller.bsQtyController.text = '4';
      expect(controller.isValidQty(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Group 5 — adjustSheetQty stepper
  // -------------------------------------------------------------------------
  group('adjustSheetQty — stepper is capped at effective ceiling', () {
    test('increment is blocked at bsMaxQty', () {
      controller.bsMaxQty.value = 3.0;
      controller.bsBatchBalance.value = 0.0;
      controller.bsValidationMaxQty.value = 0.0;
      controller.bsQtyController.text = '3';
      controller.adjustSheetQty(1);
      // Should stay at 3, not go to 4
      expect(controller.bsQtyController.text, equals('3'));
    });

    test('increment is blocked at bsBatchBalance when tighter', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsBatchBalance.value = 2.0;
      controller.bsValidationMaxQty.value = 0.0;
      controller.bsQtyController.text = '2';
      controller.adjustSheetQty(1);
      expect(controller.bsQtyController.text, equals('2'));
    });

    test('decrement is always allowed down to 1', () {
      controller.bsMaxQty.value = 10.0;
      controller.bsBatchBalance.value = 10.0;
      controller.bsQtyController.text = '5';
      controller.adjustSheetQty(-1);
      expect(controller.bsQtyController.text, equals('4'));
    });

    test('decrement at 1 does not go below 1', () {
      controller.bsQtyController.text = '1';
      controller.adjustSheetQty(-1);
      expect(controller.bsQtyController.text, equals('1'));
    });
  });
}
