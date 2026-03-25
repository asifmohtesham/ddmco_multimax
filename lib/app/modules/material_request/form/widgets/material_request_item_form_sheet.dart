import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

/// Item bottom sheet for Material Request.
///
/// Uses [GlobalItemFormSheet] for a UX identical to Stock Entry and
/// Delivery Note. Key consistency guarantees:
///
///   • [key: const ValueKey('mr_item_sheet')] on [GlobalItemFormSheet]
///     gives Flutter a stable element identity across Obx rebuilds.
///     The element (and its subtree, including [QuantityInputWidget] with
///     its `final` [_decKey] / [_incKey] fields) is updated in-place
///     rather than unmounted and remounted. This means:
///       - [_QtyRepeatController] instances survive Rx state changes
///         (no GetX tag churn, no mid-hold timer cancellation).
///       - Only changed params propagate down via normal widget diffing.
///
///   • The [Obx] scope is kept so that reactive params (title,
///     isSaveEnabled, itemSubtext, onDelete, isLoading) still re-read
///     the latest Rx values on every tick. The stable key ensures that
///     re-reading those params does NOT remount the widget subtree.
///
///   • Qty +/− buttons call [adjustSheetQty(1/-1)] → [validateSheet()] →
///     [isSheetValid] updated automatically, enabling "Update Item" only
///     when the form actually changed.
///
///   • "Update Item" title + enabled state is driven by [isSheetValid]
///     which is false in edit mode until [isFormDirty] is true.
///
///   • [itemSubtext] = [bsItemVariantOf] so the header shows
///     "ITEM-CODE • variant_of" exactly like Stock Entry & Delivery Note.
class MaterialRequestItemFormSheet extends StatelessWidget {
  final MaterialRequestFormController controller;

  const MaterialRequestItemFormSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing  = controller.currentItemNameKey.value != null;
      final docStatus  = controller.materialRequest.value?.docstatus ?? 0;
      final variantOf  = controller.bsItemVariantOf.value;

      return GlobalItemFormSheet(
        // ── Stable key ─────────────────────────────────────────────────────────
        //
        // CRITICAL: a stable ValueKey prevents Flutter from unmounting and
        // remounting this widget when the Obx rebuilds. Without it, every
        // Rx change constructs a new GlobalItemFormSheet → new
        // QuantityInputWidget → new UniqueKey objects for the +/− buttons
        // → _QtyRepeatController tag churn and mid-hold timer cancellation.
        //
        // Previously this was ValueKey(currentItemNameKey.value ?? 'new'),
        // which changed on edit → add transitions and caused remounts.
        // The sheet is opened fresh each time by openItemSheet(), so a
        // single constant key is correct for the lifetime of one sheet.
        key: const ValueKey('mr_item_sheet'),

        formKey:          controller.itemFormKey,
        scrollController: null,

        // ── Header ─────────────────────────────────────────────────────────
        title:        isEditing ? 'Update Item' : 'Add Item',
        itemCode:     controller.currentItemCode,
        itemName:     controller.currentItemName,
        // variantOf is reactive: bsItemVariantOf is set in openItemSheet()
        // and may update asynchronously (e.g. after a scan resolves).
        itemSubtext:  (variantOf != null && variantOf.isNotEmpty)
                          ? variantOf
                          : null,

        // ── Quantity ─────────────────────────────────────────────────────────
        qtyController: controller.bsQtyController,
        onIncrement:   () => controller.adjustSheetQty(1),
        onDecrement:   () => controller.adjustSheetQty(-1),

        // ── Save / validation ───────────────────────────────────────────────
        isSaveEnabledRx: controller.isSheetValid,
        // docStatus == 0 check: re-evaluated on each Obx tick so the
        // Save button hard-disables immediately if the doc is submitted.
        isSaveEnabled:   docStatus == 0,
        // isAddingItem drives the _AnimatedSaveButton spinner via
        // isSheetLoading; also passed as isLoading for the legacy path.
        isLoading:       controller.isAddingItem.value,
        onSubmit:        controller.saveItem,

        // ── Delete (edit mode only) ────────────────────────────────────────
        // onDelete reads currentItemNameKey.value at call time (not at
        // build time) so the closure always resolves the live item even
        // if the Rx value changes between build and tap.
        onDelete: isEditing
            ? () {
                final key = controller.currentItemNameKey.value;
                if (key == null) return;
                final item = controller.materialRequest.value?.items
                    .firstWhere((i) => i.name == key);
                if (item == null) return;
                controller.deleteItem(item);
              }
            : null,

        // ── Custom fields ───────────────────────────────────────────────────
        customFields: [
          _buildWarehouseField(context),
        ],
      );
    });
  }

  Widget _buildWarehouseField(BuildContext context) {
    return GlobalItemFormSheet.buildInputGroup(
      label: 'Warehouse',
      color: Colors.teal,
      child: GestureDetector(
        onTap: () => controller.showWarehousePicker(forItem: true),
        child: AbsorbPointer(
          child: TextFormField(
            controller: controller.bsWarehouseController,
            decoration: InputDecoration(
              hintText: 'Select Warehouse',
              prefixIcon:
                  Icon(Icons.store_outlined, color: Colors.teal.shade600),
              suffixIcon: const Icon(Icons.arrow_drop_down),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.teal.shade200),
              ),
              filled: true,
              fillColor: Colors.teal.shade50,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}
