import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

/// Item bottom sheet for Material Request.
///
/// Uses [GlobalItemFormSheet] for a UX identical to Stock Entry and
/// Delivery Note. Key consistency guarantees:
///
///   • Qty +/− buttons call [adjustSheetQty(1/-1)] → [validateSheet()] →
///     [isFormDirty] is updated automatically, enabling "Update Item" only
///     when the form actually changed (mirrors DeliveryNoteFormController).
///
///   • "Update Item" title + enabled state is driven by [isSheetValid] which
///     is false in edit mode until [isFormDirty] is true.
///
///   • [itemSubtext] = [bsItemVariantOf] so the header shows
///     "ITEM-CODE • variant_of" exactly like Stock Entry & Delivery Note.
///
///   • [isDirty] is marked BEFORE Navigator.pop (no Get.back race condition).
class MaterialRequestItemFormSheet extends StatelessWidget {
  final MaterialRequestFormController controller;

  const MaterialRequestItemFormSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.currentItemNameKey.value != null;
      final docStatus = controller.materialRequest.value?.docstatus ?? 0;
      final variantOf = controller.bsItemVariantOf.value;

      return GlobalItemFormSheet(
        key: ValueKey(controller.currentItemNameKey.value ?? 'new'),
        formKey: controller.itemFormKey,
        scrollController: null,

        // ── Header ──────────────────────────────────────────────────────────
        // itemSubtext shows variant_of identical to Stock Entry / Delivery Note.
        // It is reactive: if bsItemVariantOf changes after sheet opens, the
        // header updates without rebuilding the whole sheet.
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,
        itemSubtext: (variantOf != null && variantOf.isNotEmpty) ? variantOf : null,

        // ── Quantity ─────────────────────────────────────────────────────────
        qtyController: controller.bsQtyController,
        // adjustSheetQty → validateSheet → isFormDirty updated automatically
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),

        // ── Save / validation ─────────────────────────────────────────────────
        // isSaveEnabledRx = isSheetValid (which is false in edit mode until dirty)
        // isSaveEnabled   = docStatus == 0 (hard gate for submitted docs)
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: docStatus == 0,
        isLoading: controller.isAddingItem.value,
        onSubmit: controller.saveItem,

        // ── Delete (edit mode only) ───────────────────────────────────────────
        onDelete: isEditing
            ? () => controller.deleteItem(
                  controller.materialRequest.value!.items.firstWhere(
                    (i) => i.name == controller.currentItemNameKey.value,
                  ),
                )
            : null,

        // ── Custom fields ─────────────────────────────────────────────────────
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
