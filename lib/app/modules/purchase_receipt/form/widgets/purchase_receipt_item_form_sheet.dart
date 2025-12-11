import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class PurchaseReceiptItemFormSheet extends GetView<PurchaseReceiptFormController> {
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final bool isEditable = controller.isEditable;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        child: Form(
          key: formKey,
          child: ListView(
            controller: scrollController,
            shrinkWrap: true,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Obx(() => Text(
                          controller.currentItemNameKey.value != null
                              ? (isEditable ? 'Edit Item' : 'View Item')
                              : 'Add Item',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        )),
                        const SizedBox(height: 4),
                        Text(
                          '${controller.currentItemCode}${controller.currentVariantOf.isNotEmpty ? ' • ${controller.currentVariantOf}' : ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'monospace'),
                        ),
                        Text(
                          controller.currentItemName,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                  ),
                ],
              ),
              const Divider(height: 24),

              if (controller.currentOwner.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Added by ${controller.currentOwner} • ${FormattingHelper.getRelativeTime(controller.currentCreation)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

              // Batch Input
              Obx(() => _buildInputGroup(
                label: 'Batch No',
                color: Colors.purple,
                bgColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : null,
                child: TextFormField(
                  key: const ValueKey('batch_field'),
                  controller: controller.bsBatchController,
                  focusNode: controller.batchFocusNode,
                  readOnly: !isEditable || controller.bsIsBatchReadOnly.value,
                  autofocus: isEditable && !controller.bsIsBatchReadOnly.value && controller.currentItemNameKey.value == null,
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
              )),

              const SizedBox(height: 16),

              // Rack Input
              Obx(() => _buildInputGroup(
                label: 'Target Rack',
                color: Colors.green,
                bgColor: controller.isTargetRackValid.value ? Colors.green.shade50 : null,
                child: TextFormField(
                  key: const ValueKey('rack_field'),
                  controller: controller.bsRackController,
                  focusNode: controller.targetRackFocusNode,
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
              )),

              const SizedBox(height: 16),

              // REFACTORED: Quantity Input
              QuantityInputWidget(
                controller: controller.bsQtyController,
                onIncrement: () => controller.adjustSheetQty(1),
                onDecrement: () => controller.adjustSheetQty(-1),
                isReadOnly: !isEditable,
                label: 'Quantity',
              ),

              const SizedBox(height: 24),

              // Submit Button
              if (isEditable)
                Obx(() => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.isSheetValid.value ? controller.addItem : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: controller.isSheetValid.value ? Theme.of(context).primaryColor : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    child: Text(controller.currentItemNameKey.value != null ? 'Update Item' : 'Add Item'),
                  ),
                ))
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Get.back(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Close'),
                  ),
                ),

              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputGroup({required String label, required Color color, required Widget child, Color? bgColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        Container(
          decoration: BoxDecoration(
            color: bgColor ?? color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
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
      icon: const Icon(Icons.check),
      onPressed: onSubmit,
      color: Colors.grey,
    );
  }
}