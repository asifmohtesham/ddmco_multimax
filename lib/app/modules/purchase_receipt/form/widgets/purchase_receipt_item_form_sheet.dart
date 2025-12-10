import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class PurchaseReceiptItemFormSheet extends GetView<PurchaseReceiptFormController> {
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
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
                        controller.currentItemNameKey.value != null ? 'Edit Item' : 'Add Item',
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

            // Batch Input
            Obx(() => _buildInputGroup(
              label: 'Batch No',
              color: Colors.purple,
              // Grey out background if validated
              bgColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : null,
              child: TextFormField(
                key: const ValueKey('batch_field'),
                controller: controller.bsBatchController,
                focusNode: controller.batchFocusNode,
                // Lock field if validated
                readOnly: controller.bsIsBatchReadOnly.value,
                autofocus: !controller.bsIsBatchReadOnly.value && controller.currentItemNameKey.value == null,
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
                  // If validated, fill color matches wrapper. If editing, white.
                  fillColor: controller.bsIsBatchReadOnly.value ? Colors.purple.shade50 : Colors.white,

                  // Reactive Icon
                  suffixIcon: _isValidatingIcon(
                    controller.bsIsLoadingBatch.value,
                    controller.bsIsBatchValid.value,
                    color: Colors.purple,
                    onSubmit: () => controller.validateBatch(controller.bsBatchController.text),
                    onReset: controller.resetBatchValidation,
                  ),
                ),
                onFieldSubmitted: (value) => controller.validateBatch(value),
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
                // Lock field if validated
                readOnly: controller.isTargetRackValid.value,
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
                  fillColor: controller.isTargetRackValid.value ? Colors.green.shade50 : Colors.white,

                  // Reactive Icon
                  suffixIcon: _isValidatingIcon(
                    controller.isValidatingTargetRack.value,
                    controller.isTargetRackValid.value,
                    color: Colors.green,
                    onSubmit: () => controller.validateRack(controller.bsRackController.text),
                    onReset: controller.resetRackValidation,
                  ),
                ),
                onFieldSubmitted: (val) => controller.validateRack(val),
              ),
            )),

            const SizedBox(height: 16),

            // Quantity Input
            _buildInputGroup(
              label: 'Quantity',
              color: Colors.black87,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('qty_field'),
                      controller: controller.bsQtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        final qty = double.tryParse(value);
                        if (qty == null) return 'Invalid number';
                        if (qty <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ),
                  _buildQtyButton(Icons.remove, () => controller.adjustSheetQty(-1)),
                  _buildQtyButton(Icons.add, () => controller.adjustSheetQty(1)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
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
            )),

            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
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

  Widget _buildQtyButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Icon(icon, size: 20),
        ),
      ),
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
      // Show Green Edit/Reset Icon to allow user to re-enable field
      return IconButton(
        icon: const Icon(Icons.edit, size: 20), // Or Icons.check_circle if strictly status
        tooltip: 'Edit Field',
        onPressed: onReset,
        color: color,
      );
    }

    // Show Submit/Check icon to trigger validation
    return IconButton(
      icon: const Icon(Icons.check),
      onPressed: onSubmit,
      color: Colors.grey,
    );
  }
}