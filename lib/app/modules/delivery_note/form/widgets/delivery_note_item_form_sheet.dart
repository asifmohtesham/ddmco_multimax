import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  /// Compact chip showing available balance.
  /// Shows a small spinner while [isLoading], the chip when [balance] > 0,
  /// or nothing otherwise.
  Widget _balanceChip({
    required double balance,
    required bool isLoading,
    required Color color,
    String prefix = 'Avail:',
  }) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 4.0, left: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            ),
            const SizedBox(width: 6),
            Text('Fetching balance...',
                style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      );
    }
    if (balance <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          '$prefix ${balance % 1 == 0 ? balance.toInt() : balance}',
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

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
        isLoading: controller.isValidatingBatch.value || controller.isAddingItem.value,
        onSubmit: controller.submitSheet,
        onDelete: isEditing
            ? () {
                final item = controller.deliveryNote.value?.items
                    .firstWhereOrNull(
                        (i) => i.name == controller.editingItemName.value);
                if (item != null) controller.confirmAndDeleteItem(item);
              }
            : null,
        onScan: (code) => controller.scanBarcode(code),
        scanController: controller.barcodeController,
        isScanning: controller.isScanning.value,
        customFields: [
          // ── Invoice Serial No ─────────────────────────────────────────
          if (controller.bsAvailableInvoiceSerialNos.isNotEmpty)
            GlobalItemFormSheet.buildInputGroup(
              label: 'Invoice Serial No',
              color: Colors.blueGrey,
              child: DropdownButtonFormField<String>(
                value: controller.bsInvoiceSerialNo.value,
                decoration: InputDecoration(
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  hintText: 'Select Serial',
                ),
                items: controller.bsAvailableInvoiceSerialNos.map((s) {
                  return DropdownMenuItem(value: s, child: Text('Serial #\$s'));
                }).toList(),
                onChanged: (value) {
                  controller.bsInvoiceSerialNo.value = value;
                  controller.validateSheet();
                },
              ),
            ),

          // ── Batch No ──────────────────────────────────────────────────
          Obx(() => GlobalItemFormSheet.buildInputGroup(
                label: 'Batch No',
                color: Colors.purple,
                bgColor: controller.bsIsBatchValid.value
                    ? Colors.purple.shade50
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      key: const ValueKey('batch_field'),
                      controller: controller.bsBatchController,
                      readOnly: controller.bsIsBatchValid.value,
                      autofocus: false,
                      style: const TextStyle(fontFamily: 'ShureTechMono'),
                      decoration: InputDecoration(
                        hintText: 'Enter or scan batch',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.purple.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Colors.purple, width: 2),
                        ),
                        filled: true,
                        fillColor: controller.bsIsBatchValid.value
                            ? Colors.purple.shade50
                            : Colors.white,
                        suffixIcon: controller.isValidatingBatch.value
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.purple),
                                ))
                            : (controller.bsIsBatchValid.value
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (controller.batchInfoTooltip.value !=
                                          null)
                                        Tooltip(
                                          message:
                                              controller.batchInfoTooltip.value!,
                                          triggerMode: TooltipTriggerMode.tap,
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 8.0),
                                            child: Icon(Icons.info_outline,
                                                color: Colors.blue),
                                          ),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.purple),
                                        onPressed:
                                            controller.resetBatchValidation,
                                        tooltip: 'Edit Batch',
                                      ),
                                    ],
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.check,
                                        color: Colors.purple),
                                    onPressed: () =>
                                        controller.validateAndFetchBatch(
                                            controller.bsBatchController.text),
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
                    // Balance chip
                    Obx(() => _balanceChip(
                          balance: controller.bsBatchBalance.value,
                          isLoading: controller.isLoadingBatchBalance.value,
                          color: Colors.purple,
                          prefix: 'Batch Qty:',
                        )),
                  ],
                ),
              )),

          // ── Source Rack ───────────────────────────────────────────────
          GlobalItemFormSheet.buildInputGroup(
            label: 'Rack',
            color: Colors.orange,
            bgColor:
                controller.bsIsRackValid.value ? Colors.orange.shade50 : null,
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
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.orange.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Colors.orange, width: 2),
                        ),
                        filled: true,
                        fillColor: controller.bsIsRackValid.value
                            ? Colors.orange.shade50
                            : Colors.white,
                        suffixIcon: controller.isValidatingRack.value
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.orange),
                                ))
                            : (controller.bsIsRackValid.value
                                ? IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.orange),
                                    onPressed:
                                        controller.resetRackValidation,
                                    tooltip: 'Edit Rack',
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.check,
                                        color: Colors.orange),
                                    onPressed: () => controller.validateRack(
                                        controller.bsRackController.text),
                                    tooltip: 'Validate',
                                  )),
                      ),
                      onFieldSubmitted: (val) => controller.validateRack(val),
                    )),
                // Balance chip
                Obx(() => _balanceChip(
                      balance: controller.bsRackBalance.value,
                      isLoading: controller.isLoadingRackBalance.value,
                      color: Colors.orange,
                      prefix: 'Rack Qty:',
                    )),
                // Rack stock error
                if (controller.rackError.value != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                    child: Text(
                      controller.rackError.value!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
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
