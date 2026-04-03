import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] to gain the full animated item-sheet
/// infrastructure (save-button state, auto-submit worker, dirty tracking, etc.).
///
/// Commit 8: implemented all abstract members inherited from
/// [ItemSheetControllerBase] that were previously missing:
///   • accentColor         → Colors.teal (PS brand colour)
///   • isAddMode           → @override bool getter (was a mutable field)
///   • qtyInfoTooltip      → RxnString(null)  (no extra tooltip for PS)
///   • sheetScanController → null  (PS sheet has no in-sheet scanner)
///   • adjustQty(delta)    → ±1 stepper clamped to 0..bsMaxQty
///
/// PS-specific notes:
///   • resolvedWarehouse → null  (PS has no warehouse concept)
///   • requiresBatch     → false (batch is a read-only display field)
///   • requiresRack      → false
///   • validateSheet() dirty-check uses base [isDirty] getter
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

  /// Commit 8: PS uses teal as its accent colour.
  @override
  Color get accentColor => Colors.teal;

  /// Commit 8: proper @override getter — editingItemName.value == null = add.
  @override
  bool get isAddMode => editingItemName.value == null;

  @override
  String? get qtyInfoText {
    final max = _parent.bsMaxQty.value;
    if (max > 0) return 'Remaining: ${max.toStringAsFixed(2)}';
    return null;
  }

  /// Commit 8: no extra tooltip for PS.
  @override
  RxnString get qtyInfoTooltip => RxnString(null);

  /// Commit 8: PS sheet has no embedded scanner.
  @override
  MobileScannerController? get sheetScanController => null;

  /// Commit 8: ±1 stepper clamped to [0, bsMaxQty] when a ceiling exists.
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

    // Commit 8: use the base isDirty getter (replaces isFormDirty/isFieldsDirty
    // which do not exist on the base class).
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

    // isAddMode is now a computed getter — no assignment.

    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
