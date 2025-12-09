import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class PurchaseReceiptItemFormSheet extends GetView<PurchaseReceiptFormController> {
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

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
                child: TextFormField(
                  controller: controller.bsBatchController,
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
                    filled: controller.bsIsBatchReadOnly.value,
                    fillColor: controller.bsIsBatchReadOnly.value ? Colors.purple.shade50 : null,
                    suffixIcon: _isValidatingIcon(
                      controller.isValidatingBatch.value,
                      controller.bsIsBatchValid.value,
                      isReadOnly: controller.bsIsBatchReadOnly.value,
                      onCheck: () => controller.validateBatch(controller.bsBatchController.text),
                      color: Colors.purple,
                    ),
                  ),
                  onChanged: (_) => controller.checkForChanges(),
                  onFieldSubmitted: (value) => controller.validateBatch(value),
                ),
              )),

              const SizedBox(height: 16),

              // Rack Input - FIXED: Explicitly not readonly
              Obx(() => _buildInputGroup(
                label: 'Target Rack',
                color: Colors.green,
                child: TextFormField(
                  controller: controller.bsRackController,
                  focusNode: controller.targetRackFocusNode,
                  readOnly: false, // Ensure not readOnly
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
                    suffixIcon: _isValidatingIcon(
                      controller.isValidatingTargetRack.value,
                      controller.isTargetRackValid.value,
                      onCheck: () => controller.validateRack(controller.bsRackController.text, false),
                      color: Colors.green,
                    ),
                  ),
                  onChanged: (_) => controller.checkForChanges(),
                  onFieldSubmitted: (val) => controller.validateRack(val, false),
                ),
              )),

              const SizedBox(height: 16),

              // Quantity Input - FIXED: Added buttons
              _buildInputGroup(
                label: 'Quantity',
                color: Colors.black87,
                child: Row(
                  children: [
                    _buildQtyButton(Icons.remove, () => controller.adjustSheetQty(-1)),
                    Expanded(
                      child: TextFormField(
                        controller: controller.bsQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (_) => controller.checkForChanges(),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Required';
                          final qty = double.tryParse(value);
                          if (qty == null) return 'Invalid number';
                          if (qty <= 0) return 'Must be > 0';
                          if (controller.currentPurchaseOrderQty.value > 0 && qty > controller.currentPurchaseOrderQty.value) {
                            return 'Exceeds PO (${controller.currentPurchaseOrderQty.value})';
                          }
                          return null;
                        },
                      ),
                    ),
                    _buildQtyButton(Icons.add, () => controller.adjustSheetQty(1)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              Obx(() => SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (controller.currentItemNameKey.value == null || controller.isFormDirty.value) && controller.bsIsBatchValid.value
                      ? () {
                    if (formKey.currentState!.validate()) {
                      controller.addItem();
                    }
                  }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).primaryColor,
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
      ),
    );
  }

  Widget _buildInputGroup({required String label, required Color color, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
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

  Widget? _isValidatingIcon(bool isLoading, bool isValid, {bool isReadOnly = false, VoidCallback? onCheck, required Color color}) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)),
      );
    }
    if (isValid || isReadOnly) {
      return Icon(Icons.check_circle, color: color);
    }
    return IconButton(
      icon: const Icon(Icons.check),
      onPressed: onCheck,
      color: Colors.grey,
    );
  }
}