import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

/// Item bottom sheet for Material Request.
///
/// Migrated to [GlobalItemFormSheet] so that:
///   • Qty increment/decrement behaves identically to Stock Entry & Delivery Note
///   • isDirty is set BEFORE the sheet closes (no timing race)
///   • Navigator.of(context).pop() is used instead of Get.back() to avoid
///     the GetX LateInitializationError on the snackbar AnimationController
///   • SafeArea + viewInsets are handled inside GlobalItemFormSheet
///   • Delete button, loading spinner, and form validation are consistent
class MaterialRequestItemFormSheet extends StatelessWidget {
  final MaterialRequestFormController controller;

  const MaterialRequestItemFormSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.currentItemNameKey.value != null;
      final docStatus = controller.materialRequest.value?.docstatus ?? 0;

      return GlobalItemFormSheet(
        key: ValueKey(controller.currentItemNameKey.value ?? 'new'),
        formKey: controller.itemFormKey,
        scrollController: null,
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,

        // ── Quantity ────────────────────────────────────────────────────
        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),

        // ── Save / validation ───────────────────────────────────────────
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: docStatus == 0,
        isLoading: controller.isAddingItem.value,
        onSubmit: controller.saveItem,

        // ── Delete (edit mode only) ─────────────────────────────────────
        onDelete: isEditing
            ? () => controller.deleteItem(
                  controller.materialRequest.value!.items.firstWhere(
                    (i) => i.name == controller.currentItemNameKey.value,
                  ),
                )
            : null,

        // ── Custom fields ───────────────────────────────────────────────
        customFields: [
          // Warehouse picker — same GestureDetector + AbsorbPointer pattern
          // as StockEntry/DeliveryNote for doctype-specific pickers that are
          // not part of GlobalItemFormSheet's standard fields.
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
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}
