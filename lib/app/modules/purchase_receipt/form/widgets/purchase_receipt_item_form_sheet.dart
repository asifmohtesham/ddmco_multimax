import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/purchase_receipt/form/controllers/purchase_receipt_item_form_controller.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

/// Purchase Receipt item-entry bottom sheet.
///
/// Now a [GetView<PurchaseReceiptItemFormController>] — all field state
/// is read from the ephemeral child controller only.
class PurchaseReceiptItemFormSheet
    extends GetView<PurchaseReceiptItemFormController> {
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final parent = Get.find<PurchaseReceiptFormController>();

    return Obx(() {
      final bool isEditable = parent.isEditable;
      final bool isEditing  = controller.editingItemName.value != null;

      return GlobalItemFormSheet(
        formKey:      controller.formKey,
        scrollController: scrollController,
        title: isEditing
            ? (isEditable ? 'Update Item' : 'View Item')
            : 'Add Item',
        itemCode:    controller.itemCode.value,
        itemName:    controller.itemName.value,
        itemSubtext: controller.variantOf.value,

        // ── Metadata footer ────────────────────────────────────────────────
        owner:      controller.itemOwner.value,
        creation:   controller.itemCreation.value,
        modified:   controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // ── Qty ──────────────────────────────────────────────────────────────
        qtyController: controller.qtyController,
        onIncrement:   () => controller.adjustQty(1),
        onDecrement:   () => controller.adjustQty(-1),
        isQtyReadOnly: !isEditable,
        qtyInfoText: controller.poQty.value > 0
            ? 'PO Ordered: ${controller.poQty.value}'
            : null,

        // ── Save / delete ───────────────────────────────────────────────────
        isSaveEnabled: controller.isSheetValid.value && isEditable,
        isLoading:     controller.isValidatingBatch.value,
        onSubmit:      () async {
          await controller.submit();
          Get.back();
        },
        onDelete: (isEditing && isEditable)
            ? () => parent.deleteItem(controller.editingItemName.value!)
            : null,

        // ── Custom fields ───────────────────────────────────────────────────
        customFields: [
          // 1. Batch No (purple, readOnly-when-valid, helperText error)
          Obx(() => GlobalItemFormSheet.buildInputGroup(
            label:   'Batch No',
            color:   Colors.purple,
            bgColor: controller.isBatchValid.value ? Colors.purple.shade50 : null,
            child: TextFormField(
              key:       const ValueKey('pr_batch_field'),
              controller: controller.batchController,
              readOnly:   !isEditable || controller.isBatchReadOnly.value,
              autofocus:  false,
              decoration: InputDecoration(
                hintText: 'Enter or scan batch',
                helperText: controller.batchError.value,
                helperStyle: TextStyle(
                  color: controller.batchError.value != null
                      ? Colors.red
                      : Colors.grey,
                  fontWeight: controller.batchError.value != null
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: controller.batchError.value != null
                        ? Colors.red
                        : Colors.purple.shade200,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: controller.batchError.value != null
                        ? Colors.red
                        : Colors.purple,
                    width: 2,
                  ),
                ),
                filled:    true,
                fillColor: (controller.isBatchReadOnly.value || !isEditable)
                    ? Colors.purple.shade50
                    : Colors.white,
                suffixIcon: isEditable
                    ? _isValidatingIcon(
                        controller.isValidatingBatch.value,
                        controller.isBatchValid.value,
                        color:    Colors.purple,
                        onSubmit: () => controller
                            .validateBatch(controller.batchController.text),
                        onReset:  controller.resetBatch,
                      )
                    : null,
              ),
              onFieldSubmitted: isEditable
                  ? (val) => controller.validateBatch(val)
                  : null,
            ),
          )),

          // 2. Target Rack (green, required)
          Obx(() => GlobalItemFormSheet.buildInputGroup(
            label:   'Target Rack',
            color:   Colors.green,
            bgColor: controller.isRackValid.value ? Colors.green.shade50 : null,
            child: TextFormField(
              key:        const ValueKey('pr_rack_field'),
              controller: controller.rackController,
              autofocus:  false,
              readOnly:   !isEditable || controller.isRackValid.value,
              decoration: InputDecoration(
                hintText: 'Rack',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: Colors.green.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: Colors.green, width: 2),
                ),
                filled:    true,
                fillColor: (controller.isRackValid.value || !isEditable)
                    ? Colors.green.shade50
                    : Colors.white,
                suffixIcon: isEditable
                    ? _isValidatingIcon(
                        controller.isValidatingRack.value,
                        controller.isRackValid.value,
                        color:    Colors.green,
                        onSubmit: () => controller
                            .validateRack(controller.rackController.text),
                        onReset:  controller.resetRack,
                      )
                    : null,
              ),
              onChanged: isEditable
                  ? (_) {
                      if (controller.isRackValid.value) {
                        controller.isRackValid.value = false;
                      }
                      controller.validateSheet();
                    }
                  : null,
              onFieldSubmitted: isEditable
                  ? (val) => controller.validateRack(val)
                  : null,
            ),
          )),
        ],
      );
    });
  }

  // Preserved verbatim from original sheet (spinner → edit → forward chevron)
  Widget? _isValidatingIcon(
    bool isLoading,
    bool isValid, {
    required Color color,
    required VoidCallback onSubmit,
    required VoidCallback onReset,
  }) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(
          width:  24,
          height: 24,
          child:  CircularProgressIndicator(strokeWidth: 2.5, color: color),
        ),
      );
    }
    if (isValid) {
      return IconButton(
        icon:    const Icon(Icons.edit, size: 20),
        tooltip: 'Edit Field',
        onPressed: onReset,
        color: color,
      );
    }
    return IconButton(
      icon:      const Icon(Icons.arrow_forward),
      onPressed: onSubmit,
      color:     Colors.grey,
    );
  }
}
