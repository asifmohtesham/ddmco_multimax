import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] for the full animated item-sheet
/// infrastructure (save-button state, auto-submit worker, dirty tracking, etc.).
class PackingSlipItemFormController extends ItemSheetControllerBase {
  // ── Parent reference ──────────────────────────────────────────
  late PackingSlipFormController _parent;

  // ── ItemSheetControllerBase abstract overrides ──────────────────────

  @override
  String? get resolvedWarehouse => null;

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  Color get accentColor => Colors.teal;

  @override
  bool get isAddMode => editingItemName.value == null;

  /// Fix 1: base abstract declares `String get qtyInfoText` (non-nullable).
  /// Return '' instead of null when there is no ceiling.
  @override
  String get qtyInfoText {
    final max = _parent.bsMaxQty.value;
    if (max > 0) return 'Remaining: ${max.toStringAsFixed(2)}';
    return '';
  }

  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  @override
  MobileScannerController? get sheetScanController => null;

  /// Fix 2: base abstract declares `void adjustQty(int delta)`.
  /// The stepper always passes +1 / -1, so int is correct.
  @override
  void adjustQty(int delta) {
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

  // ── Initialisation ────────────────────────────────────────────

  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    PackingSlipItem? editingItem,
  }) {
    _parent = parent;

    // Fix 3: isAddingItemFlag is a plain bool field on the base;
    // parent.isAddingItem is RxBool — unwrap with .value.
    isAddingItemFlag = parent.isAddingItem.value;

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

    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
