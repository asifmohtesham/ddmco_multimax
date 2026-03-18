import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.editingItemName.value != null;

      // Explicitly read every Rx field that effectiveMaxQty depends on so
      // that Obx registers them as reactive dependencies and rebuilds the
      // Available label whenever any of them change.
      // ignore: unused_local_variable
      final _ = controller.bsMaxQty.value;
      // ignore: unused_local_variable
      final __ = controller.bsBatchBalance.value;
      // ignore: unused_local_variable
      final ___ = controller.bsRackBalance.value;
      // ignore: unused_local_variable
      final ____ = controller.bsIsRackValid.value;

      final effectiveMax = controller.effectiveMaxQty;

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
        itemSubtext: controller.bsItemVariantOf.value,
        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        qtyInfoText: effectiveMax < 999999.0
            ? 'Available: \${effectiveMax.toStringAsFixed(0)}'
            : null,
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true,
        isLoading:
            controller.isValidatingBatch.value || controller.isAddingItem.value,
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  hintText: 'Select Serial',
                ),
                items: controller.bsAvailableInvoiceSerialNos.map((s) {
                  return DropdownMenuItem(
                      value: s, child: Text('Serial #\$s'));
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
                child: ValidatedFieldWidget(
                  fieldKey: const ValueKey('batch_field'),
                  controller: controller.bsBatchController,
                  color: Colors.purple,
                  hintText: 'Enter or scan batch',
                  isReadOnly: controller.bsIsBatchReadOnly.value,
                  isValid: controller.bsIsBatchValid.value,
                  isValidating: controller.isValidatingBatch.value,
                  hasError: controller.bsBatchError.value != null,
                  helperText: controller.bsBatchError.value,
                  onValidate: () => controller
                      .validateAndFetchBatch(controller.bsBatchController.text),
                  onReset: controller.resetBatchValidation,
                  extraSuffixActions: [
                    if (controller.batchInfoTooltip.value != null)
                      Tooltip(
                        message: controller.batchInfoTooltip.value!,
                        triggerMode: TooltipTriggerMode.tap,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(Icons.info_outline, color: Colors.blue),
                        ),
                      ),
                  ],
                  onChanged: (_) => controller.validateSheet(),
                  onFieldSubmitted: (val) {
                    if (!controller.bsIsBatchValid.value) {
                      controller.validateAndFetchBatch(val);
                    }
                  },
                  chip: Obx(() => BalanceChip(
                        balance: controller.bsBatchBalance.value,
                        isLoading: controller.isLoadingBatchBalance.value,
                        color: Colors.purple,
                        prefix: 'Batch Qty:',
                        forceShow: controller.bsIsBatchValid.value,
                      )),
                ),
              )),

          // ── Source Rack ───────────────────────────────────────────────
          Obx(() => GlobalItemFormSheet.buildInputGroup(
                label: 'Rack',
                color: Colors.orange,
                bgColor: controller.bsIsRackValid.value
                    ? Colors.orange.shade50
                    : null,
                child: ValidatedFieldWidget(
                  fieldKey: const ValueKey('rack_field'),
                  controller: controller.bsRackController,
                  focusNode: controller.bsRackFocusNode,
                  color: Colors.orange,
                  hintText: 'Enter or scan rack',
                  isReadOnly: controller.bsIsRackValid.value,
                  isValid: controller.bsIsRackValid.value,
                  isValidating: controller.isValidatingRack.value,
                  onValidate: () => controller
                      .validateRack(controller.bsRackController.text),
                  onReset: controller.resetRackValidation,
                  onFieldSubmitted: (val) => controller.validateRack(val),
                  chip: Obx(() => BalanceChip(
                        balance: controller.bsRackBalance.value,
                        isLoading: controller.isLoadingRackBalance.value,
                        color: Colors.orange,
                        prefix: 'Rack Qty:',
                      )),
                  errorText: controller.rackError.value,
                ),
              )),
        ],
      );
    });
  }
}
