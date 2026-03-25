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
/// Step-3: qtyController (base) is now the single source of truth for qty.
///   submit() reads qtyController.text and passes parsed qty to
///   parent.addItemToSlipWithQty(qty), removing the direct dependency
///   on parent.bsQtyController.
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
    // Read from base qtyController (single source of truth after step-3).
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
    // Step-3: read directly from base TEC — no bsQtyController sync shim.
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0) return;
    await _parent.addItemToSlipWithQty(qty);
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

      // Step-3: pre-fill from bsMaxQty directly, not bsQtyController.
      final remaining = parent.bsMaxQty.value;
      qtyController.text = remaining > 0
          ? (remaining % 1 == 0
              ? remaining.toInt().toString()
              : remaining.toString())
          : '0';
    }

    isAddMode = editingItem == null;

    initBaseListeners();
    captureSnapshot();
    validateSheet();
  }
}
