import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class PackingSlipItemFormSheet extends GetView<PackingSlipFormController> {
  final ScrollController? scrollController;

  const PackingSlipItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.isEditing.value;

      return GlobalItemFormSheet(
        formKey: controller.itemFormKey,
        scrollController: scrollController, // Standardised scroll binding
        title: isEditing ? 'Edit Pack Item' : 'Pack Item',
        itemCode: controller.currentItemCode ?? '-',
        itemName: controller.currentItemName ?? '-',

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustQty(1),
        onDecrement: () => controller.adjustQty(-1),
        qtyInfoText: 'Remaining: ${controller.bsMaxQty.value.toStringAsFixed(2)}',

        // Pass the validation observable for Dirty Check
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true,

        onSubmit: controller.addItemToSlip,
        onDelete: isEditing ? controller.deleteCurrentItem : null,

        // Pass Metadata to Global Widget
        owner: controller.bsItemOwner.value,
        creation: controller.bsItemCreation.value,
        modified: controller.bsItemModified.value,
        modifiedBy: controller.bsItemModifiedBy.value,

        customFields: [
          // Item Info Container
          if (controller.currentBatchNo != null && controller.currentBatchNo!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          'Batch No',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          controller.currentBatchNo!,
                          style: TextStyle(
                            fontFamily: 'ShureTechMono',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}