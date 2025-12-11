import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class PackingSlipItemFormSheet extends GetView<PackingSlipFormController> {
  const PackingSlipItemFormSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.isEditing.value;

      return GlobalItemFormSheet(
        formKey: controller.itemFormKey, // PASSED KEY
        scrollController: null,
        title: isEditing ? 'Edit Pack Item' : 'Pack Item',
        itemCode: controller.currentItemCode ?? '-',
        itemName: controller.currentItemName ?? '-',

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustQty(1),
        onDecrement: () => controller.adjustQty(-1),
        qtyInfoText: 'Remaining: ${controller.bsMaxQty.value.toStringAsFixed(2)}',

        // Pass the validation observable for Dirty Check
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true, // Used as fallback or if not Rx

        onSubmit: controller.addItemToSlip,
        onDelete: isEditing ? controller.deleteCurrentItem : null,

        customFields: [
          // Item Info Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                if (controller.currentBatchNo != null && controller.currentBatchNo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 80, child: Text('Batch No', style: TextStyle(color: Colors.grey, fontSize: 12))),
                        Expanded(child: Text(controller.currentBatchNo!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}