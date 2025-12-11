import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class PurchaseReceiptItemFormSheet extends GetView<PurchaseReceiptFormController> {
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final bool isEditable = controller.isEditable;
      final bool isEditing = controller.currentItemNameKey.value != null;

      return GlobalItemFormSheet(
        formKey: controller.itemFormKey, // PASSED KEY
        scrollController: scrollController,
        title: isEditing ? (isEditable ? 'Update Item' : 'View Item') : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,
        itemSubtext: controller.currentVariantOf,

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        isQtyReadOnly: !isEditable,
        qtyInfoText: controller.currentPurchaseOrderQty.value > 0
            ? 'PO Ordered: ${controller.currentPurchaseOrderQty.value}'
            : null,

        isSaveEnabled: controller.isSheetValid.value && isEditable,
        isLoading: controller.bsIsLoadingBatch.value,

        onSubmit: controller.addItem,
        onDelete: (isEditing && isEditable)
            ? () => controller.deleteItem(controller.currentItemNameKey.value!)
            : null,

        customFields: [
          // Batch Input
          GlobalItemFormSheet.buildInputGroup(
            label: 'Batch No',
            color: Colors.purple,
            bgColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : null,
            child: TextFormField(
              key: const ValueKey('batch_field'),
              controller: controller.bsBatchController,
              // focusNode: controller.batchFocusNode,
              readOnly: !isEditable || controller.bsIsBatchReadOnly.value,
              autofocus: false, // DISABLED AUTOFOCUS
              decoration: InputDecoration(
                hintText: 'Enter or scan batch',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.purple.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.purple, width: 2),
                ),
                filled: true,
                fillColor: (controller.bsIsBatchReadOnly.value || !isEditable) ? Colors.purple.shade50 : Colors.white,
                suffixIcon: isEditable ? _isValidatingIcon(
                  controller.bsIsLoadingBatch.value,
                  controller.bsIsBatchValid.value,
                  color: Colors.purple,
                  onSubmit: () => controller.validateBatch(controller.bsBatchController.text),
                  onReset: controller.resetBatchValidation,
                ) : null,
              ),
              onFieldSubmitted: isEditable ? (value) => controller.validateBatch(value) : null,
            ),
          ),

          // Rack Input
          GlobalItemFormSheet.buildInputGroup(
            label: 'Target Rack',
            color: Colors.green,
            bgColor: controller.isTargetRackValid.value ? Colors.green.shade50 : null,
            child: TextFormField(
              key: const ValueKey('rack_field'),
              controller: controller.bsRackController,
              // focusNode: controller.targetRackFocusNode,
              autofocus: false, // DISABLED AUTOFOCUS
              readOnly: !isEditable || controller.isTargetRackValid.value,
              decoration: InputDecoration(
                hintText: 'Rack',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.green.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.green, width: 2),
                ),
                filled: true,
                fillColor: (controller.isTargetRackValid.value || !isEditable) ? Colors.green.shade50 : Colors.white,
                suffixIcon: isEditable ? _isValidatingIcon(
                  controller.isValidatingTargetRack.value,
                  controller.isTargetRackValid.value,
                  color: Colors.green,
                  onSubmit: () => controller.validateRack(controller.bsRackController.text),
                  onReset: controller.resetRackValidation,
                ) : null,
              ),
              onChanged: isEditable ? (val) => controller.onRackChanged(val) : null,
              onFieldSubmitted: isEditable ? (val) => controller.validateRack(val) : null,
            ),
          ),
        ],
      );
    });
  }

  Widget? _isValidatingIcon(bool isLoading, bool isValid, {
    required Color color,
    required VoidCallback onSubmit,
    required VoidCallback onReset,
  }) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)),
      );
    }
    if (isValid) {
      return IconButton(
        icon: const Icon(Icons.edit, size: 20),
        tooltip: 'Edit Field',
        onPressed: onReset,
        color: color,
      );
    }
    return IconButton(
      icon: const Icon(Icons.arrow_forward),
      onPressed: onSubmit,
      color: Colors.grey,
    );
  }
}