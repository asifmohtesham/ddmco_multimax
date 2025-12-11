import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

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
            // --- Header ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Obx(() => Text(
                        controller.editingItemName.value != null ? 'Edit Item' : 'Add Item',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      )),
                      const SizedBox(height: 4),
                      Text(
                        '${controller.currentItemCode} • ${controller.currentItemName}',
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: Colors.grey),
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

            // --- Invoice Serial No ---
            Obx(() {
              if (controller.bsAvailableInvoiceSerialNos.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildInputGroup(
                  label: 'Invoice Serial No',
                  color: Colors.blueGrey,
                  child: DropdownButtonFormField<String>(
                    value: controller.bsInvoiceSerialNo.value,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: controller.bsAvailableInvoiceSerialNos.map((s) {
                      return DropdownMenuItem(value: s, child: Text('Serial #$s'));
                    }).toList(),
                    onChanged: (value) {
                      controller.bsInvoiceSerialNo.value = value;
                      controller.checkForChanges();
                    },
                  ),
                ),
              );
            }),

            // --- Batch No ---
            Obx(() => _buildInputGroup(
              label: 'Batch No',
              color: Colors.purple,
              child: TextFormField(
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchReadOnly.value || controller.bsIsLoadingBatch.value,
                autofocus: !controller.bsIsBatchReadOnly.value && controller.editingItemName.value == null,
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
                  suffixIcon: controller.bsIsLoadingBatch.value
                      ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                      : (controller.bsIsBatchValid.value
                      ? const Icon(Icons.check_circle, color: Colors.purple)
                      : IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => controller.validateAndFetchBatch(controller.bsBatchController.text),
                  )),
                ),
                onChanged: (_) => controller.checkForChanges(),
                onFieldSubmitted: (val) {
                  if (!controller.bsIsBatchReadOnly.value) {
                    controller.validateAndFetchBatch(val);
                  }
                },
              ),
            )),

            const SizedBox(height: 16),

            // --- Rack ---
            _buildInputGroup(
              label: 'Rack',
              color: Colors.orange,
              child: TextFormField(
                controller: controller.bsRackController,
                focusNode: controller.bsRackFocusNode,
                decoration: InputDecoration(
                  hintText: 'Source Rack',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.orange.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.orange, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.shelves, color: Colors.orange),
                ),
                onChanged: (_) => controller.checkForChanges(),
              ),
            ),

            const SizedBox(height: 16),

            // --- REFACTORED: Quantity Input ---
            Obx(() => QuantityInputWidget(
              controller: controller.bsQtyController,
              onIncrement: () => controller.adjustSheetQty(1),
              onDecrement: () => controller.adjustSheetQty(-1),
              onChanged: (_) => controller.checkForChanges(),
              label: 'Quantity',
              helperText: controller.bsMaxQty.value > 0
                  ? 'Max Available: ${controller.bsMaxQty.value}'
                  : null,
            )),

            const SizedBox(height: 24),

            // --- Action Buttons ---
            Obx(() {
              final canSubmit = !controller.isSaving.value &&
                  !controller.bsIsLoadingBatch.value &&
                  (controller.isFormDirty.value || controller.editingItemName.value == null);

              return ElevatedButton(
                onPressed: canSubmit ? controller.submitSheet : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: canSubmit ? Theme.of(context).primaryColor : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: canSubmit ? 2 : 0,
                ),
                child: Text(
                  controller.editingItemName.value != null ? 'Update Item' : 'Add Item',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              );
            }),

            // --- Delete Button (Editing Mode) ---
            Obx(() {
              if (controller.editingItemName.value != null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Get.back();
                        final item = controller.deliveryNote.value?.items
                            .firstWhereOrNull((i) => i.name == controller.editingItemName.value);
                        if (item != null) {
                          controller.confirmAndDeleteItem(item);
                        }
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Remove Item', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),

            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
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
}