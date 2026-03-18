import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/balance_chip.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  // ---------------------------------------------------------------------------
  // Scoped reactive helpers — each subscribes only to the Rx fields it needs.
  // ---------------------------------------------------------------------------

  /// Rebuilds only the qtyInfoText string.
  /// Depends on: bsMaxQty, bsBatchBalance, bsRackBalance, bsIsRackValid.
  Widget _qtyInfoText(Widget Function(String?) builder) {
    return Obx(() {
      // ignore: unused_local_variable
      final _ = controller.bsMaxQty.value;
      // ignore: unused_local_variable
      final __ = controller.bsBatchBalance.value;
      // ignore: unused_local_variable
      final ___ = controller.bsRackBalance.value;
      // ignore: unused_local_variable
      final ____ = controller.bsIsRackValid.value;
      final max = controller.effectiveMaxQty;
      final text = max < 999999.0 ? 'Available: \${max.toStringAsFixed(0)}' : null;
      return builder(text);
    });
  }

  /// Rebuilds only the isLoading flag.
  /// Depends on: isValidatingBatch, isAddingItem.
  Widget _isLoading(Widget Function(bool) builder) {
    return Obx(() => builder(
          controller.isValidatingBatch.value || controller.isAddingItem.value,
        ));
  }

  /// Rebuilds only the isScanning flag.
  Widget _isScanning(Widget Function(bool) builder) {
    return Obx(() => builder(controller.isScanning.value));
  }

  // ---------------------------------------------------------------------------
  // Invoice Serial No field — scoped to its own Rx fields.
  // ---------------------------------------------------------------------------
  Widget _invoiceSerialField() {
    return Obx(() {
      if (controller.bsAvailableInvoiceSerialNos.isEmpty) {
        return const SizedBox.shrink();
      }
      return GlobalItemFormSheet.buildInputGroup(
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
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Batch No field — scoped Obx unchanged from Step 2.
  // ---------------------------------------------------------------------------
  Widget _batchField() {
    return Obx(() => GlobalItemFormSheet.buildInputGroup(
          label: 'Batch No',
          color: Colors.purple,
          bgColor:
              controller.bsIsBatchValid.value ? Colors.purple.shade50 : null,
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
        ));
  }

  // ---------------------------------------------------------------------------
  // Rack field — scoped Obx unchanged from Step 2.
  // ---------------------------------------------------------------------------
  Widget _rackField() {
    return Obx(() => GlobalItemFormSheet.buildInputGroup(
          label: 'Rack',
          color: Colors.orange,
          bgColor:
              controller.bsIsRackValid.value ? Colors.orange.shade50 : null,
          child: ValidatedFieldWidget(
            fieldKey: const ValueKey('rack_field'),
            controller: controller.bsRackController,
            focusNode: controller.bsRackFocusNode,
            color: Colors.orange,
            hintText: 'Enter or scan rack',
            isReadOnly: controller.bsIsRackValid.value,
            isValid: controller.bsIsRackValid.value,
            isValidating: controller.isValidatingRack.value,
            onValidate: () =>
                controller.validateRack(controller.bsRackController.text),
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
        ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Metadata is static after the sheet opens — read once, no Obx needed.
    final owner = controller.bsItemOwner.value;
    final creation = controller.bsItemCreation.value;
    final modified = controller.bsItemModified.value;
    final modifiedBy = controller.bsItemModifiedBy.value;
    final variantOf = controller.bsItemVariantOf.value;

    // Root Obx: only editingItemName changes the sheet structure.
    return Obx(() {
      final isEditing = controller.editingItemName.value != null;

      return _qtyInfoText((qtyInfoText) =>
          _isLoading((isLoading) =>
              _isScanning((isScanning) =>
                  GlobalItemFormSheet(
                    owner: owner,
                    creation: creation,
                    modified: modified,
                    modifiedBy: modifiedBy,
                    formKey: controller.itemFormKey,
                    scrollController: scrollController,
                    title: isEditing ? 'Update Item' : 'Add Item',
                    itemCode: controller.currentItemCode,
                    itemName: controller.currentItemName,
                    itemSubtext: variantOf,
                    qtyController: controller.bsQtyController,
                    onIncrement: () => controller.adjustSheetQty(1),
                    onDecrement: () => controller.adjustSheetQty(-1),
                    qtyInfoText: qtyInfoText,
                    isSaveEnabledRx: controller.isSheetValid,
                    isSaveEnabled: true,
                    isLoading: isLoading,
                    onSubmit: controller.submitSheet,
                    onDelete: isEditing
                        ? () {
                            final item = controller.deliveryNote.value?.items
                                .firstWhereOrNull((i) =>
                                    i.name ==
                                    controller.editingItemName.value);
                            if (item != null) {
                              controller.confirmAndDeleteItem(item);
                            }
                          }
                        : null,
                    onScan: (code) => controller.scanBarcode(code),
                    scanController: controller.barcodeController,
                    isScanning: isScanning,
                    customFields: [
                      _invoiceSerialField(),
                      _batchField(),
                      _rackField(),
                    ],
                  ))));});
  }
}
