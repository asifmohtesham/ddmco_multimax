// Unit Test #5.2 - Max qty <= min(batch balance, rack balance)
//
// Requirement (from -YourRequirement-CorrectTestType.csv):
//   The quantity a user may enter/submit must never exceed the minimum of:
//     - bsBatchBalance  - warehouse-scoped batch balance (from getBatchWiseBalance)
//     - bsMaxQty        - rack / warehouse stock balance  (from getStockBalance)
//
// The two code surfaces that enforce this invariant:
//   1. _isValidQty()      - gates isSheetValid (submit button enabled/disabled)
//   2. adjustSheetQty()   - gates the +/- stepper (cannot increment past ceiling)
//
// All tests are pure state-machine: no network calls, no Flutter widgets.
//
// Run: flutter test test/unit/stock_entry/max_qty_balance_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

// ---------------------------------------------------------------------------
// Minimal stub - skips onInit() so no provider / service calls are made.
// ---------------------------------------------------------------------------
class _Ctrl extends StockEntryFormController {
  @override
  void onInit() {}
}

// Convenience: set the qty text field and the two balance observables, then
// call validateSheet() so isSheetValid reflects the new state.
//
// We also set the minimum state required by the other _isValid* helpers so
// that only _isValidQty() is the deciding factor in each group:
//   - batch field non-empty + bsIsBatchValid = true  (_isValidBatch passes)
//   - entrySource = manual, so _isValidContext() returns true unconditionally
//   - SE type = 'Material Receipt' so _isValidRacks() needs only a valid
//     target rack - we set both rack fields + flags to valid.
void _prime(
  _Ctrl c, {
  required double qty,
  required double batchBalance,
  required double rackBalance,
}) {
  c.selectedStockEntryType.value = 'Material Receipt';
  c.bsTargetRackController.text = 'DDMCO-B2-01';
  c.isTargetRackValid.value = true;
  c.bsBatchController.text = 'BATCH-001';
  c.bsIsBatchValid.value = true;
  c.bsMaxQty.value = rackBalance;
  c.bsBatchBalance.value = batchBalance;
  c.bsQtyController.text = qty == 0 ? '' : qty.toStringAsFixed(0);
  c.validateSheet();
}

void main() {
  late _Ctrl ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _Ctrl();
  });

  tearDown(() => Get.reset());

  // =========================================================================
  // 1. _isValidQty via isSheetValid
  //    The sheet must only be valid when qty <= min(batchBalance, rackBalance)
  // =========================================================================
  group('isSheetValid respects min(batchBalance, rackBalance) ceiling', () {

    group('batch balance is the lower ceiling', () {
      test('VALID: qty == batch balance', () {
        _prime(ctrl, qty: 5, batchBalance: 5, rackBalance: 10);
        expect(ctrl.isSheetValid.value, isTrue,
            reason: 'qty exactly at batch balance must be accepted.');
      });

      test('VALID: qty < batch balance', () {
        _prime(ctrl, qty: 3, batchBalance: 5, rackBalance: 10);
        expect(ctrl.isSheetValid.value, isTrue);
      });

      test('INVALID: qty > batch balance', () {
        _prime(ctrl, qty: 6, batchBalance: 5, rackBalance: 10);
        expect(ctrl.isSheetValid.value, isFalse,
            reason: 'qty exceeds batch balance - must be rejected.');
      });

      test('INVALID: qty == rack balance but exceeds batch balance', () {
        _prime(ctrl, qty: 10, batchBalance: 5, rackBalance: 10);
        expect(ctrl.isSheetValid.value, isFalse,
            reason: 'qty equal to rack balance but over batch balance '
                'must still be rejected.');
      });
    });

    group('rack balance is the lower ceiling', () {
      test('VALID: qty == rack balance', () {
        _prime(ctrl, qty: 4, batchBalance: 12, rackBalance: 4);
        expect(ctrl.isSheetValid.value, isTrue,
            reason: 'qty exactly at rack balance must be accepted.');
      });

      test('VALID: qty < rack balance', () {
        _prime(ctrl, qty: 2, batchBalance: 12, rackBalance: 4);
        expect(ctrl.isSheetValid.value, isTrue);
      });

      test('INVALID: qty > rack balance', () {
        _prime(ctrl, qty: 5, batchBalance: 12, rackBalance: 4);
        expect(ctrl.isSheetValid.value, isFalse,
            reason: 'qty exceeds rack balance - must be rejected.');
      });

      test('INVALID: qty == batch balance but exceeds rack balance', () {
        _prime(ctrl, qty: 12, batchBalance: 12, rackBalance: 4);
        expect(ctrl.isSheetValid.value, isFalse,
            reason: 'qty equal to batch balance but over rack balance '
                'must still be rejected.');
      });
    });

    group('batch balance == rack balance (tie)', () {
      test('VALID: qty == both balances', () {
        _prime(ctrl, qty: 7, batchBalance: 7, rackBalance: 7);
        expect(ctrl.isSheetValid.value, isTrue);
      });

      test('INVALID: qty > both balances', () {
        _prime(ctrl, qty: 8, batchBalance: 7, rackBalance: 7);
        expect(ctrl.isSheetValid.value, isFalse);
      });
    });

    group('zero balance == no ceiling (balance not yet fetched)', () {
      test('VALID: large qty when both balances are 0 (not yet loaded)', () {
        _prime(ctrl, qty: 999, batchBalance: 0, rackBalance: 0);
        expect(ctrl.isSheetValid.value, isTrue,
            reason: 'Zero balance means ceiling not fetched; '
                'controller must not block submission.');
      });

      test('VALID: qty when only rackBalance is loaded (batchBalance=0)', () {
        _prime(ctrl, qty: 3, batchBalance: 0, rackBalance: 10);
        expect(ctrl.isSheetValid.value, isTrue,
            reason: 'batchBalance=0 must not act as a ceiling of zero.');
      });

      test('INVALID: qty > rackBalance even when batchBalance is 0', () {
        _prime(ctrl, qty: 15, batchBalance: 0, rackBalance: 10);
        expect(ctrl.isSheetValid.value, isFalse,
            reason: 'rackBalance ceiling must still apply when batchBalance=0.');
      });

      test('VALID: qty when only batchBalance is loaded (rackBalance=0)', () {
        _prime(ctrl, qty: 3, batchBalance: 10, rackBalance: 0);
        expect(ctrl.isSheetValid.value, isTrue,
            reason: 'rackBalance=0 must not act as a ceiling of zero.');
      });

      test('INVALID: qty > batchBalance even when rackBalance is 0', () {
        _prime(ctrl, qty: 15, batchBalance: 10, rackBalance: 0);
        expect(ctrl.isSheetValid.value, isFalse,
            reason: 'batchBalance ceiling must still apply when rackBalance=0.');
      });
    });

    group('qty <= 0 is always invalid regardless of balances', () {
      test('INVALID: qty == 0', () {
        _prime(ctrl, qty: 0, batchBalance: 100, rackBalance: 100);
        expect(ctrl.isSheetValid.value, isFalse);
      });

      test('INVALID: qty field is empty (parses to 0)', () {
        ctrl.selectedStockEntryType.value = 'Material Receipt';
        ctrl.bsTargetRackController.text = 'DDMCO-B2-01';
        ctrl.isTargetRackValid.value = true;
        ctrl.bsBatchController.text = 'BATCH-001';
        ctrl.bsIsBatchValid.value = true;
        ctrl.bsMaxQty.value = 100;
        ctrl.bsBatchBalance.value = 100;
        ctrl.bsQtyController.text = '';
        ctrl.validateSheet();
        expect(ctrl.isSheetValid.value, isFalse);
      });
    });
  });

  // =========================================================================
  // 2. adjustSheetQty - stepper ceiling
  //    The +/- stepper must not let qty exceed min(batchBalance, rackBalance)
  // =========================================================================
  group('adjustSheetQty respects min(batchBalance, rackBalance) ceiling', () {
    // Helper: set balances, set starting qty, run stepper, return result text.
    String step(double startQty, double batchBalance, double rackBalance,
        double delta) {
      ctrl.bsMaxQty.value = rackBalance;
      ctrl.bsBatchBalance.value = batchBalance;
      ctrl.bsValidationMaxQty.value = 0.0;
      ctrl.bsQtyController.text =
          startQty == 0 ? '' : startQty.toStringAsFixed(0);
      ctrl.adjustSheetQty(delta);
      return ctrl.bsQtyController.text;
    }

    // batch is tighter
    test('stepper: +1 allowed when result == batch balance (batch < rack)', () {
      expect(step(4, 5, 10, 1), equals('5'));
    });

    test('stepper: +1 blocked when already at batch balance ceiling', () {
      expect(step(5, 5, 10, 1), equals('5'),
          reason: 'Cannot increment past batch balance ceiling.');
    });

    test('stepper: +2 blocked when it would overshoot batch balance', () {
      expect(step(4, 5, 10, 2), equals('4'),
          reason: 'Delta that overshoots batch ceiling must be rejected entirely.');
    });

    // rack is tighter
    test('stepper: +1 allowed when result == rack balance (rack < batch)', () {
      expect(step(3, 12, 4, 1), equals('4'));
    });

    test('stepper: +1 blocked when already at rack balance ceiling', () {
      expect(step(4, 12, 4, 1), equals('4'),
          reason: 'Cannot increment past rack balance ceiling.');
    });

    // decrement
    test('stepper: -1 below both ceilings is always allowed', () {
      expect(step(5, 5, 5, -1), equals('4'));
    });

    test('stepper: -1 from 1 clears the field (qty=0 shown as empty)', () {
      expect(step(1, 10, 10, -1), equals(''),
          reason: 'Qty of 0 is represented as an empty field.');
    });

    test('stepper: -1 from 0 is blocked (no negative qty)', () {
      expect(step(0, 10, 10, -1), equals(''),
          reason: 'Negative qty must be blocked; field stays empty.');
    });

    // zero balances = no ceiling
    test('stepper: increments freely when both balances are 0', () {
      expect(step(50, 0, 0, 100), equals('150'),
          reason: 'Zero balance = no ceiling; stepper must not block increment.');
    });

    // tie
    test('stepper: +1 to exactly min(batch, rack) is allowed', () {
      expect(step(6, 7, 7, 1), equals('7'));
    });

    test('stepper: +1 past min(batch, rack) is blocked', () {
      expect(step(7, 7, 7, 1), equals('7'));
    });
  });

  // =========================================================================
  // 3. Late-arriving balance updates must immediately flip isSheetValid
  //    Simulates the async race where balance data arrives after qty entry.
  // =========================================================================
  group('isSheetValid reacts to late-arriving balance updates', () {
    test('sheet flips INVALID when batchBalance arrives below current qty', () {
      _prime(ctrl, qty: 10, batchBalance: 0, rackBalance: 0);
      expect(ctrl.isSheetValid.value, isTrue,
          reason: 'Balances not yet loaded - sheet should be valid.');

      ctrl.bsBatchBalance.value = 5;
      ctrl.validateSheet();
      expect(ctrl.isSheetValid.value, isFalse,
          reason: 'Late batch balance must immediately invalidate sheet.');
    });

    test('sheet flips INVALID when rackBalance arrives below current qty', () {
      _prime(ctrl, qty: 10, batchBalance: 0, rackBalance: 0);
      expect(ctrl.isSheetValid.value, isTrue);

      ctrl.bsMaxQty.value = 3;
      ctrl.validateSheet();
      expect(ctrl.isSheetValid.value, isFalse,
          reason: 'Late rack balance must immediately invalidate sheet.');
    });

    test('sheet flips VALID when qty is reduced to fit within arrived balance', () {
      _prime(ctrl, qty: 10, batchBalance: 5, rackBalance: 5);
      expect(ctrl.isSheetValid.value, isFalse);

      ctrl.bsQtyController.text = '5';
      ctrl.validateSheet();
      expect(ctrl.isSheetValid.value, isTrue,
          reason: 'After reducing qty to fit balance, sheet must become valid.');
    });

    test('sheet stays VALID when both balances arrive above current qty', () {
      _prime(ctrl, qty: 4, batchBalance: 0, rackBalance: 0);
      expect(ctrl.isSheetValid.value, isTrue);

      ctrl.bsBatchBalance.value = 10;
      ctrl.bsMaxQty.value = 8;
      ctrl.validateSheet();
      expect(ctrl.isSheetValid.value, isTrue,
          reason: 'Balances that arrive above qty must not invalidate sheet.');
    });
  });
}
