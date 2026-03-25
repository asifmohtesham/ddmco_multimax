import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] to gain:
///   • formKey, qtyController (base TEC — single source of truth for qty)
///   • isSheetValid, saveButtonState, isSheetLoading
///   • metadata observables (itemOwner/Creation/Modified/ModifiedBy)
///   • deferred TEC/FocusNode disposal via onClose()
///   • setupAutoSubmit() worker
///   • submitWithFeedback() animated save-button flow
///   • adjustQty(delta) with maxQty capping (base implementation)
///
/// Step-1: Full implementation of all ItemSheetControllerBase abstract members.
///   submit() delegates to parent.addItemToSlip() via a bsQtyController sync
///   shim; the shim and addItemToSlip() are replaced in step-3 and removed
///   in step-6 once qty ownership fully migrates to the child controller.
///
/// PS-specific notes:
///   • resolvedWarehouse → null  (PS has no warehouse concept)
///   • requiresBatch     → false (batch is a read-only display field)
///   • requiresRack      → false
class PackingSlipItemFormController extends ItemSheetControllerBase {
  // ── Parent reference ────────────────────────────────────────────────────
  late PackingSlipFormController _parent;

  // ── ItemSheetControllerBase contract ────────────────────────────────────

  @override
  String? get resolvedWarehouse => null;

  @override
  bool get requiresBatch => false;

  @override
  bool get requiresRack => false;

  @override
  String? get qtyInfoText {
    final max = _parent.bsMaxQty.value;
    if (max > 0) return 'Remaining: \${max.toStringAsFixed(2)}';
    return null;
  }

  @override
  Future<void> deleteCurrentItem() => _parent.deleteCurrentItem();

  @override
  void validateSheet() {
    // Read from base qtyController — single source of truth for qty.
    final qty = double.tryParse(qtyController.text);

    if (qty == null || qty <= 0) {
      isSheetValid.value = false;
      return;
    }
    if (_parent.bsMaxQty.value > 0 && qty > _parent.bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }

    isFormDirty.value = isFieldsDirty;

    // In edit mode the Save button stays disabled until qty actually changes.
    if (editingItemName.value != null && !isFormDirty.value) {
      isSheetValid.value = false;
      return;
    }

    isSheetValid.value = true;
  }

  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0) return;
    // Sync parent alias so addItemToSlip() still compiles until step-6 cleanup.
    _parent.bsQtyController.text = qtyController.text;
    await _parent.addItemToSlip();
  }

  // ── Initialisation ───────────────────────────────────────────────────────

  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    PackingSlipItem? editingItem,
  }) {
    _parent = parent;

    // Wire loading flag so isSheetLoading covers in-progress saves.
    isAddingItemFlag = parent.isAddingItem;

    this.itemCode.value = itemCode;
    this.itemName.value = itemName;

    // maxQty cap from parent remaining-qty calculation.
    maxQty.value = parent.bsMaxQty.value;

    if (editingItem != null) {
      // Edit mode — restore existing qty and metadata.
      editingItemName.value = editingItem.name;
      itemOwner.value       = editingItem.owner;
      itemCreation.value    = editingItem.creation;
      itemModified.value    = editingItem.modified;
      itemModifiedBy.value  = editingItem.modifiedBy;

      final qty = editingItem.qty;
      qtyController.text =
          qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    } else {
      // Add mode — pre-fill qty with remaining qty from parent.
      editingItemName.value = null;
      itemOwner.value       = null;
      itemCreation.value    = null;
      itemModified.value    = null;
      itemModifiedBy.value  = null;

      qtyController.text = parent.bsQtyController.text;
    }

    isAddMode = editingItem == null;

    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
