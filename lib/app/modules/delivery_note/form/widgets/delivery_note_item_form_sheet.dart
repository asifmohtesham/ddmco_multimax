import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/serial_batch_bundle_widget.dart';

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.editingItemName.value != null;
      final isSabbMode = controller.useSerialBatchFields.value == 0; // Check Mode

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

        isQtyReadOnly: isSabbMode, // Disable manual qty in SABB mode
        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        qtyInfoText: controller.bsMaxQty.value > 0
            ? 'Max Available: ${controller.bsMaxQty.value}'
            : null,

        // Only enable save if the sheet is valid
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true,

        // UPDATED: Show loading if validating batch OR if adding/submitting (auto-submit)
        isLoading: controller.isValidatingBatch.value || controller.isAddingItem.value,

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

        // Standardised Global Scan Integration
        onScan: (code) => controller.scanBarcode(code),
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
                  hintText: 'Select Serial',
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

          if (isSabbMode)
            SerialBatchBundleWidget(mixin: controller),

          // Batch No
          if (!isSabbMode)
            Obx(() => GlobalItemFormSheet.buildInputGroup(
              label: 'Batch No',
              color: Colors.purple,
              bgColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : null,
              child: TextFormField(
                key: const ValueKey('batch_field'),
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchValid.value,
                autofocus: false,
                style: TextStyle(fontFamily: 'ShureTechMono',),
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
                  fillColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : Colors.white,
                  suffixIcon: controller.isValidatingBatch.value
                      ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple)))
                      : (controller.bsIsBatchValid.value
                      ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Helpful Tooltip
                      if (controller.batchInfoTooltip.value != null)
                        Tooltip(
                          message: controller.batchInfoTooltip.value!,
                          triggerMode: TooltipTriggerMode.tap,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(Icons.info_outline, color: Colors.blue),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.purple),
                        onPressed: controller.resetBatchValidation,
                        tooltip: 'Edit Batch',
                      ),
                    ],
                  )
                      : IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => controller.validateAndFetchBatch(controller.bsBatchController.text),
                    tooltip: 'Validate',
                  )),
                ),
                onChanged: (_) => controller.validateSheet(),
                onFieldSubmitted: (val) {
                  if (!controller.bsIsBatchValid.value) {
                    controller.validateAndFetchBatch(val);
                  }
                },
              ),
            )),

          // Rack
          GlobalItemFormSheet.buildInputGroup(
            label: 'Rack',
            color: Colors.orange,
            bgColor: controller.bsIsRackValid.value ? Colors.orange.shade50 : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(() => TextFormField(
                  key: const ValueKey('rack_field'),
                  controller: controller.bsRackController,
                  focusNode: controller.bsRackFocusNode,
                  readOnly: controller.bsIsRackValid.value,
                  decoration: InputDecoration(
                    hintText: 'Enter or scan rack',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.orange.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                    filled: true,
                    fillColor: controller.bsIsRackValid.value ? Colors.orange.shade50 : Colors.white,
                    suffixIcon: controller.isValidatingRack.value
                        ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)))
                        : (controller.bsIsRackValid.value
                        ? IconButton(
                      icon: const Icon(Icons.edit, color: Colors.orange),
                      onPressed: controller.resetRackValidation,
                      tooltip: 'Edit Rack',
                    )
                        : IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => controller.validateRack(controller.bsRackController.text),
                      tooltip: 'Validate',
                    )),
                  ),
                  onFieldSubmitted: (val) => controller.validateRack(val),
                )),
                // Display Rack Stock Error
                if (controller.rackError.value != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                    child: Text(
                      controller.rackError.value!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  )
                else if (controller.bsIsRackValid.value)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                    child: Text(
                      controller.bsBatchController.text.isNotEmpty
                          ? 'Batch ${controller.bsBatchController.text} in Rack: ${controller.bsMaxQty.value}'
                          : 'Available in Rack: ${controller.bsMaxQty.value}',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold),
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