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
/// Step-3: qtyController (base) is now the single source of truth.
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
    if (max > 0) return 'Remaining: ${max.toStringAsFixed(2)}';
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

    // In edit mode the Save button stays disabled until the user changes qty.
    if (editingItemName.value != null && !isFormDirty.value) {
      isSheetValid.value = false;
      return;
    }

    isSheetValid.value = true;
  }

  @override
  Future<void> submit() async {
    // Parse qty from base TEC (no longer reads parent.bsQtyController).
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0) return;
    // Sync parent alias so addItemToSlip() still compiles in step-3.
    // bsQtyController alias and addItemToSlip() are cleaned up in step-6.
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
      // Edit mode.
      editingItemName.value = editingItem.name;
      itemOwner.value       = editingItem.owner;
      itemCreation.value    = editingItem.creation;
      itemModified.value    = editingItem.modified;
      itemModifiedBy.value  = editingItem.modifiedBy;

      final qty = editingItem.qty;
      qtyController.text =
          qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    } else {
      // Add mode — pre-fill qty from parent's bsQtyController
      // (populated with remaining qty before _openItemSheet is called).
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
