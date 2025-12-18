import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class MaterialRequestItemFormSheet extends StatelessWidget {
  final MaterialRequestFormController controller;

  const MaterialRequestItemFormSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(controller.currentItemCode.isEmpty ? 'New Item' : controller.currentItemCode,
              style: Get.textTheme.titleLarge),
          if (controller.currentItemName.isNotEmpty)
            Text(controller.currentItemName, style: Get.textTheme.bodyMedium?.copyWith(color: Colors.grey)),

          const Divider(height: 24),

          QuantityInputWidget(
            controller: controller.bsQtyController,
            label: 'Quantity',
            onChanged: (_) => controller.validateSheet(),
            onIncrement: () => controller.adjustSheetQty(1),
            onDecrement: () => controller.adjustSheetQty(-1),
          ),

          const SizedBox(height: 24),

          Obx(() => SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: controller.isSheetValid.value ? controller.saveItem : null,
              child: Text(controller.currentItemNameKey.value != null ? 'Update' : 'Add'),
            ),
          )),
        ],
      ),
    );
  }
}