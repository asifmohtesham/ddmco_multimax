import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class MaterialRequestItemFormSheet extends StatelessWidget {
  final MaterialRequestFormController controller;

  const MaterialRequestItemFormSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // viewInsets.bottom = keyboard height (0 when keyboard is closed).
    // SafeArea bottom covers the gesture nav bar / home indicator.
    // Both are needed: one for keyboard, one for the nav bar itself.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      // SafeArea handles the gesture nav bar / home indicator
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle ─────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Item title ────────────────────────────────────────────
            Text(
              controller.currentItemCode.isEmpty
                  ? 'New Item'
                  : controller.currentItemCode,
              style: Get.textTheme.titleLarge,
            ),
            if (controller.currentItemName.isNotEmpty)
              Text(
                controller.currentItemName,
                style: Get.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey),
              ),

            const Divider(height: 24),

            // ── Quantity ─────────────────────────────────────────────
            QuantityInputWidget(
              controller: controller.bsQtyController,
              label: 'Quantity',
              onChanged: (_) => controller.validateSheet(),
              onIncrement: () => controller.adjustSheetQty(1),
              onDecrement: () => controller.adjustSheetQty(-1),
            ),

            const SizedBox(height: 16),

            // ── Warehouse picker ───────────────────────────────────────
            GestureDetector(
              onTap: () => controller.showWarehousePicker(forItem: true),
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.bsWarehouseController,
                  decoration: const InputDecoration(
                    labelText: 'Warehouse',
                    prefixIcon: Icon(Icons.store_outlined),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                    border: OutlineInputBorder(),
                    hintText: 'Select Warehouse',
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Save / Update button ────────────────────────────────────
            Obx(() => SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: controller.isSheetValid.value
                        ? controller.saveItem
                        : null,
                    child: Text(
                      controller.currentItemNameKey.value != null
                          ? 'Update'
                          : 'Add',
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
