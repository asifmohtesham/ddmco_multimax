import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.editingItemName.value != null;
      final canSubmit = !controller.isSaving.value &&
          !controller.bsIsLoadingBatch.value &&
          (controller.isFormDirty.value || !isEditing);

      return GlobalItemFormSheet(
        scrollController: scrollController,
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        qtyInfoText: controller.bsMaxQty.value > 0
            ? 'Max Available: ${controller.bsMaxQty.value}'
            : null,

        isSaveEnabled: canSubmit,
        isLoading: controller.bsIsLoadingBatch.value,

        onSubmit: controller.submitSheet,
        onDelete: isEditing
            ? () {
          final item = controller.deliveryNote.value?.items
              .firstWhereOrNull((i) => i.name == controller.editingItemName.value);
          if (item != null) {
            controller.confirmAndDeleteItem(item);
          }
        }
            : null,

        customFields: [
          // Invoice Serial No
          if (controller.bsAvailableInvoiceSerialNos.isNotEmpty)
            GlobalItemFormSheet.buildInputGroup(
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

          // Batch No
          GlobalItemFormSheet.buildInputGroup(
            label: 'Batch No',
            color: Colors.purple,
            child: TextFormField(
              controller: controller.bsBatchController,
              readOnly: controller.bsIsBatchReadOnly.value || controller.bsIsLoadingBatch.value,
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
          ),

          // Rack
          GlobalItemFormSheet.buildInputGroup(
            label: 'Rack',
            color: Colors.orange,
            child: TextFormField(
              controller: controller.bsRackController,
              // focusNode: controller.bsRackFocusNode,
              autofocus: false, // DISABLED AUTOFOCUS
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
        ],
      );
    });
  }
}