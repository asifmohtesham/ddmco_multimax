import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] to gain the full animated item-sheet
/// infrastructure (save-button state, auto-submit worker, dirty tracking, etc.).
///
/// Commit 8 fixes:
///   • import 'package:get/get.dart' added — resolves RxnString without
///     relying on transitive re-export through the base class file.
///   • adjustQty signature changed int → double to match base abstract and
///     the double passed by PackingSlipFormController.adjustQty(delta).
///   • qtyInfoTooltip remains RxnString (get.dart now explicitly imported).
class PackingSlipItemFormController extends ItemSheetControllerBase {
  // ── Parent reference ──────────────────────────────────────────────────────
  late PackingSlipFormController _parent;

  // ── ItemSheetControllerBase abstract overrides ────────────────────────────

  @override
  String? get resolvedWarehouse => null;

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  /// PS uses teal as its accent colour.
  @override
  Color get accentColor => Colors.teal;

  /// Computed getter — add mode when no editing item is set.
  @override
  bool get isAddMode => editingItemName.value == null;

  /// Remaining qty tooltip shown below the qty field.
  @override
  String? get qtyInfoText {
    final max = _parent.bsMaxQty.value;
    if (max > 0) return 'Remaining: ${max.toStringAsFixed(2)}';
    return null;
  }

  /// Commit 8: RxnString now resolves — get/get.dart imported explicitly above.
  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  /// PS sheet has no embedded scanner.
  @override
  MobileScannerController? get sheetScanController => null;

  /// Commit 8: signature is double (matches base abstract + parent call site).
  /// ±1.0 stepper clamped to [0, bsMaxQty] when a ceiling exists.
  @override
  void adjustQty(double delta) {
    final current = double.tryParse(qtyController.text) ?? 0.0;
    final ceiling = _parent.bsMaxQty.value > 0
        ? _parent.bsMaxQty.value
        : double.infinity;
    final next = (current + delta).clamp(0.0, ceiling);
    qtyController.text =
        next.truncateToDouble() == next
            ? next.toInt().toString()
            : next.toStringAsFixed(2);
    validateSheet();
  }

  @override
  Future<void> deleteCurrentItem() => _parent.deleteCurrentItem();

  @override
  void validateSheet() {
    final qty = double.tryParse(qtyController.text);

    if (qty == null || qty <= 0) {
      isSheetValid.value = false;
      return;
    }
    if (_parent.bsMaxQty.value > 0 && qty > _parent.bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }

    // Use the base isDirty getter (isFormDirty / isFieldsDirty do not exist).
    if (editingItemName.value != null && !isDirty) {
      isSheetValid.value = false;
      return;
    }

    isSheetValid.value = true;
  }

  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0) return;
    await _parent.addItemToSlipWithQty(qty);
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    PackingSlipItem? editingItem,
  }) {
    _parent = parent;

    // Commit 8: isAddingItemFlag is RxBool? on base; parent.isAddingItem is
    // RxBool (false.obs) — types match, assignment is safe.
    isAddingItemFlag = parent.isAddingItem;

    this.itemCode.value = itemCode;
    this.itemName.value = itemName;

    if (editingItem != null) {
      editingItemName.value = editingItem.name;
      itemOwner.value       = editingItem.owner;
      itemCreation.value    = editingItem.creation;
      itemModified.value    = editingItem.modified;
      itemModifiedBy.value  = editingItem.modifiedBy;

      final qty = editingItem.qty;
      qtyController.text =
          qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    } else {
      editingItemName.value = null;
      itemOwner.value       = null;
      itemCreation.value    = null;
      itemModified.value    = null;
      itemModifiedBy.value  = null;

      final remaining = parent.bsMaxQty.value;
      qtyController.text = remaining > 0
          ? (remaining % 1 == 0
              ? remaining.toInt().toString()
              : remaining.toString())
          : '0';
    }

    // isAddMode is a computed getter — no assignment needed.

    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
