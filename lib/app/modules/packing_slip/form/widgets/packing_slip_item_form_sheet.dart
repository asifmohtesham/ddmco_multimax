import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class PackingSlipItemFormSheet extends GetView<PackingSlipFormController> {
  const PackingSlipItemFormSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pack Item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Item Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Item Code', controller.currentItemCode ?? '-'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Item Name', controller.currentItemName ?? '-'),
                  if (controller.currentBatchNo != null && controller.currentBatchNo!.isNotEmpty) ...[
                    const Divider(height: 16),
                    _buildDetailRow('Batch No', controller.currentBatchNo!),
                  ]
                ],
              ),
            ),

            const SizedBox(height: 24),

            // REFACTORED: Quantity Input
            Obx(() => QuantityInputWidget(
              controller: controller.bsQtyController,
              onIncrement: () => controller.adjustQty(1),
              onDecrement: () => controller.adjustQty(-1),
              label: 'Quantity to Pack',
              // Passing formatted info text
              infoText: 'Remaining: ${controller.bsMaxQty.value.toStringAsFixed(2)}',
            )),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.addItemToSlip,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Confirm & Pack', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            // Delete Button (Only for existing items)
            if (controller.isEditing.value) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: controller.deleteCurrentItem,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Remove from Package', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],

            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
      ],
    );
  }
}