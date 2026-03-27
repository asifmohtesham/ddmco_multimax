// Shared helpers for StockEntryItemFormController unit tests.
//
// Pattern: Fake (no Mockito codegen required).
//
// Usage:
//   setUp(() {
//     Get.testMode = true;
//     registerFormFakes();          // registers FakeApiProvider etc.
//     ctrl = makeItemCtrl();        // stub parent + item controller
//     primeType(ctrl, 'Material Receipt'); // valid baseline for that SE type
//   });
//
//   tearDown(() => Get.reset());

import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'mock_providers.dart';

// ---------------------------------------------------------------------------
// Stub parent — skips onInit() so no provider / service calls are made.
// ---------------------------------------------------------------------------
class _StubParent extends StockEntryFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// Creates a [StockEntryItemFormController] with a stub parent wired in.
///
/// The controller is returned in a post-construction state without going
/// through [initialise()].  All fields are at their declaration defaults
/// (zeros, empty strings, false flags).
///
/// Callers must call [Get.reset()] (or `Get.deleteAll`) in tearDown.
///
/// [registerFormFakes] must have been called before this (e.g. in setUp).
StockEntryItemFormController makeItemCtrl() {
  // Register the stub parent so Get.find<StockEntryFormController>() works
  // inside any lazy code paths that may call it.
  final parent = Get.put<StockEntryFormController>(
    _StubParent(),
    permanent: false,
  );

  final ctrl = StockEntryItemFormController();

  // Wire the parent directly — mirrors what initialise() does but without
  // touching any async / WidgetsBinding / listener setup.
  // ignore: invalid_use_of_protected_member
  ctrl.testInjectParent(parent);

  return ctrl;
}

// ---------------------------------------------------------------------------
// Baseline primer
// ---------------------------------------------------------------------------

/// Sets every field that is NOT the thing-under-test to a passing value.
///
/// After this call the controller will pass [validateSheet] for the given
/// [type], so individual tests only need to mutate one constraint to observe
/// failure.
///
/// Rack fields are set according to the SE type:
///   Material Issue          — source rack only
///   Material Receipt        — target rack only
///   Material Transfer /
///   Material Transfer for   — both racks (distinct)
///   Manufacture
void primeValid(
  StockEntryItemFormController ctrl,
  String type, {
  String sourceRack = 'DDMCO-A1-01',
  String targetRack = 'DDMCO-B2-03',
  String batch      = 'BATCH-001',
  String qty        = '5',
}) {
  ctrl.parent.selectedStockEntryType.value = type;

  // Qty
  ctrl.qtyController.text = qty;

  // Batch
  ctrl.batchController.text  = batch;
  ctrl.isBatchValid.value    = true;

  // Balance ceilings — 0 means "not yet fetched", so no ceiling applied.
  ctrl.maxQty.value          = 0.0;
  ctrl.batchBalance.value    = 0.0;
  ctrl.validationMaxQty.value = 0.0;

  // Rack state
  ctrl.sourceRackController.text = '';
  ctrl.targetRackController.text = '';
  ctrl.isSourceRackValid.value   = false;
  ctrl.isTargetRackValid.value   = false;
  ctrl.rackError.value           = null;

  final needsSource = [
    'Material Issue',
    'Material Transfer',
    'Material Transfer for Manufacture',
  ].contains(type);
  final needsTarget = [
    'Material Receipt',
    'Material Transfer',
    'Material Transfer for Manufacture',
  ].contains(type);

  if (needsSource) {
    ctrl.sourceRackController.text = sourceRack;
    ctrl.isSourceRackValid.value   = true;
  }
  if (needsTarget) {
    ctrl.targetRackController.text = targetRack;
    ctrl.isTargetRackValid.value   = true;
  }

  // Entry source — manual avoids MR / POS extra gates.
  ctrl.parent.entrySource = StockEntrySource.manual;

  // Edit-mode — new item so dirty check is always satisfied.
  ctrl.editingItemName.value = null;
  ctrl.isAddMode             = true;

  ctrl.validateSheet();
}
