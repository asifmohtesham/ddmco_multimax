import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class StockEntryItemFormSheet extends StatelessWidget {
  final StockEntryFormController controller;
  final ScrollController? scrollController;

  const StockEntryItemFormSheet({
    super.key,
    required this.controller,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.currentItemNameKey.value != null;
      final docStatus = controller.stockEntry.value?.docstatus ?? 0;

      return GlobalItemFormSheet(
        key: ValueKey(controller.currentItemNameKey.value ?? 'new'),
        formKey: controller.itemFormKey,
        scrollController: scrollController,
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,
        itemSubtext: controller.currentVariantOf,

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        qtyInfoText: null,

        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: docStatus == 0,

        isLoading: controller.isAddingItem.value,
        onSubmit: controller.addItem,
        onDelete: isEditing
            ? () => controller.deleteItem(controller.currentItemNameKey.value!)
            : null,

        owner: controller.bsItemOwner.value,
        creation: controller.bsItemCreation.value,
        modified: controller.bsItemModified.value,
        modifiedBy: controller.bsItemModifiedBy.value,

        customFields: [
          // Batch No
          Obx(() => GlobalItemFormSheet.buildInputGroup(
            label: 'Batch No',
            color: Colors.purple,
            bgColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : null,
            child: TextFormField(
              key: const ValueKey('batch_field'),
              controller: controller.bsBatchController,
              readOnly: controller.bsIsBatchValid.value,
              autofocus: false,
              style: const TextStyle(fontFamily: 'ShureTechMono'),
              decoration: InputDecoration(
                hintText: 'Enter or scan batch',
                // UX FIX: Use helperText to indicate Invalid Batch gracefully
                helperText: controller.batchError.value,
                helperStyle: TextStyle(
                    color: controller.batchError.value != null ? Colors.red : Colors.grey,
                    fontWeight: controller.batchError.value != null ? FontWeight.bold : FontWeight.normal
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: controller.batchError.value != null ? Colors.red : Colors.purple.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: controller.batchError.value != null ? Colors.red : Colors.purple, width: 2),
                ),
                filled: true,
                fillColor: controller.bsIsBatchValid.value ? Colors.purple.shade50 : Colors.white,
                suffixIcon: controller.isValidatingBatch.value
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple)))
                    : (controller.bsIsBatchValid.value
                    ? IconButton(
                  icon: const Icon(Icons.edit, color: Colors.purple),
                  onPressed: controller.resetBatchValidation,
                  tooltip: 'Edit Batch',
                )
                    : IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => controller.validateBatch(controller.bsBatchController.text),
                  tooltip: 'Validate',
                )),
              ),
              onFieldSubmitted: (value) => controller.validateBatch(value),
            ),
          )),

          // Invoice Serial
          if (controller.posUploadSerialOptions.isNotEmpty)
            Obx(() => GlobalItemFormSheet.buildInputGroup(
              label: 'Invoice Serial No',
              color: Colors.blueGrey,
              child: DropdownButtonFormField<String>(
                value: controller.selectedSerial.value,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                items: controller.posUploadSerialOptions.map((s) {
                  return DropdownMenuItem(value: s, child: Text(s));
                }).toList(),
                onChanged: (value) => controller.selectedSerial.value = value,
              ),
            )),

          // Rack Fields
          Builder(builder: (context) {
            final type = controller.selectedStockEntryType.value;
            final showSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
            final showTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSource)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: GlobalItemFormSheet.buildInputGroup(
                      label: 'Source Rack',
                      color: Colors.orange,
                      bgColor: controller.isSourceRackValid.value ? Colors.orange.shade50 : null,
                      child: Obx(() => TextFormField(
                        key: const ValueKey('source_rack_field'),
                        controller: controller.bsSourceRackController,
                        readOnly: controller.isSourceRackValid.value,
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Rack',
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
                          fillColor: controller.isSourceRackValid.value ? Colors.orange.shade50 : Colors.white,
                          suffixIcon: controller.isValidatingSourceRack.value
                              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)))
                              : (controller.isSourceRackValid.value
                              ? IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            onPressed: controller.resetSourceRackValidation,
                          )
                              : IconButton(
                            icon: const Icon(Icons.arrow_forward, color: Colors.orange),
                            onPressed: () => controller.validateRack(controller.bsSourceRackController.text, true),
                          )),
                        ),
                        onFieldSubmitted: (val) => controller.validateRack(val, true),
                      )),
                    ),
                  ),

                if (showSource && showTarget) const SizedBox(width: 12),

                if (showTarget)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: GlobalItemFormSheet.buildInputGroup(
                      label: 'Target Rack',
                      color: Colors.green,
                      bgColor: controller.isTargetRackValid.value ? Colors.green.shade50 : null,
                      child: Obx(() => TextFormField(
                        key: const ValueKey('target_rack_field'),
                        controller: controller.bsTargetRackController,
                        readOnly: controller.isTargetRackValid.value,
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Rack',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.green.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.green, width: 2),
                          ),
                          filled: true,
                          fillColor: controller.isTargetRackValid.value ? Colors.green.shade50 : Colors.white,
                          suffixIcon: controller.isValidatingTargetRack.value
                              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green)))
                              : (controller.isTargetRackValid.value
                              ? IconButton(
                            icon: const Icon(Icons.edit, color: Colors.green),
                            onPressed: controller.resetTargetRackValidation,
                          )
                              : IconButton(
                            icon: const Icon(Icons.arrow_forward, color: Colors.green),
                            onPressed: () => controller.validateRack(controller.bsTargetRackController.text, false),
                          )),
                        ),
                        onFieldSubmitted: (val) => controller.validateRack(val, false),
                      )),
                    ),
                  ),
                Obx(() {
                  if (controller.rackError.value != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                      child: Text(
                        controller.rackError.value!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
            );
          }),
        ],
      );
    });
  }
}