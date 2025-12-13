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

      return GlobalItemFormSheet(
        owner: controller.bsItemOwner.value,
        creation: controller.bsItemCreation.value,
        modified: controller.bsItemModified.value,
        modifiedBy: controller.bsItemModifiedBy.value,

        formKey: controller.itemFormKey,
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

        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true,

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

        // Standardized Global Scan Integration
        onScan: (code) => controller.addItemFromBarcode(code),
        scanController: controller.barcodeController,
        isScanning: controller.isScanning.value,

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
                  controller.validateSheet();
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
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Enter Batch',
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
              onChanged: (_) => controller.validateSheet(),
              onFieldSubmitted: (val) {
                if (!controller.bsIsBatchReadOnly.value) {
                  controller.validateAndFetchBatch(val);
                }
              },
            ),
          ),

          // Rack (Standard Text Input - Scanning handled globally via onScan)
          GlobalItemFormSheet.buildInputGroup(
            label: 'Rack',
            color: Colors.orange,
            bgColor: controller.bsIsRackValid.value ? Colors.orange.shade50 : null,
            child: Obx(() => TextFormField(
              controller: controller.bsRackController,
              readOnly: controller.bsIsRackValid.value,
              decoration: InputDecoration(
                hintText: 'Enter Rack ID',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.orange.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.orange, width: 2),
                ),
                filled: controller.bsIsRackValid.value,
                fillColor: controller.bsIsRackValid.value ? Colors.orange.shade50 : null,
                suffixIcon: controller.isValidatingRack.value
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (controller.bsIsRackValid.value
                    ? IconButton(
                  icon: const Icon(Icons.edit, color: Colors.orange),
                  onPressed: controller.resetRackValidation,
                )
                    : IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => controller.validateRack(controller.bsRackController.text),
                )),
              ),
              onFieldSubmitted: (val) => controller.validateRack(val),
            )),
          ),
        ],
      );
    });
  }
}