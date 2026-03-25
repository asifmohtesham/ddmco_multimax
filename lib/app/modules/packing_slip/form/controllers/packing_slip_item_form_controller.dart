import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Item-level sheet controller for Packing Slip.
///
/// Extends [ItemSheetControllerBase] to gain:
///   • formKey, qtyController, isSheetValid, saveButtonState
///   • metadata observables (itemOwner/Creation/Modified/ModifiedBy)
///   • deferred TEC/FocusNode disposal via onClose()
///   • setupAutoSubmit() worker
///   • submitWithFeedback() animated save-button flow
///
/// PS-specific notes:
///   • resolvedWarehouse → null  (PS has no warehouse concept)
///   • requiresBatch     → false (batch is a read-only display field)
///   • requiresRack      → false
///   • validateSheet mirrors the existing parent.validateSheet() logic
///     (qty > 0, qty ≤ bsMaxQty, dirty-check in edit mode)
///   • submit() delegates to parent.addItemToSlip(); sheet close is
///     owned by the parent coordinator (_openItemSheet), not here.
///
/// Lifecycle:
///   Get.put() just before bottomSheet opens
///   → initialise()
///   → sheet opens
///   → sheet closes
///   → Get.delete<PackingSlipItemFormController>()
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
  String? get qtyInfoText =>
      'Remaining: ${_parent.bsMaxQty.value.toStringAsFixed(2)}';

  @override
  Future<void> deleteCurrentItem() => _parent.deleteCurrentItem();

  @override
  void validateSheet() {
    final text = qtyController.text;
    final qty  = double.tryParse(text);

    if (qty == null || qty <= 0) {
      isSheetValid.value = false;
      return;
    }
    if (_parent.bsMaxQty.value > 0 && qty > _parent.bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }

    isFormDirty.value = isFieldsDirty;

    // In edit mode the Save button stays disabled until the user actually
    // changes the qty (dirty-check against the snapshot set in initialise).
    if (editingItemName.value != null && !isFormDirty.value) {
      isSheetValid.value = false;
      return;
    }

    isSheetValid.value = true;
  }

  @override
  Future<void> submit() async {
    // Sheet close is owned by the parent coordinator (_openItemSheet).
    // This method only commits the data change.
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

    // Reflect the remaining-qty cap from the parent.
    maxQty.value = parent.bsMaxQty.value;

    if (editingItem != null) {
      // Edit mode — load existing item state.
      editingItemName.value = editingItem.name;
      itemOwner.value       = editingItem.owner;
      itemCreation.value    = editingItem.creation;
      itemModified.value    = editingItem.modified;
      itemModifiedBy.value  = editingItem.modifiedBy;

      final qty = editingItem.qty;
      qtyController.text =
          qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    } else {
      // Add mode — clear metadata, pre-fill qty from parent bsQtyController.
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
