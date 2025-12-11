import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class StockEntryItemFormSheet extends GetView<StockEntryFormController> {
  final ScrollController? scrollController;

  const StockEntryItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEditing = controller.currentItemNameKey.value != null;

      return GlobalItemFormSheet(
        scrollController: scrollController,
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.currentItemCode,
        itemName: controller.currentItemName,
        itemSubtext: controller.currentVariantOf,

        qtyController: controller.bsQtyController,
        onIncrement: () => controller.adjustSheetQty(1),
        onDecrement: () => controller.adjustSheetQty(-1),
        qtyInfoText: controller.bsMaxQty.value > 0
            ? 'Stock Balance: ${controller.bsMaxQty.value}'
            : null,

        isSaveEnabled: controller.isSheetValid.value && controller.stockEntry.value?.docstatus == 0,
        isLoading: controller.isValidatingBatch.value || controller.isValidatingSourceRack.value || controller.isValidatingTargetRack.value,

        onSubmit: controller.addItem,
        onDelete: isEditing
            ? () => controller.deleteItem(controller.currentItemNameKey.value!)
            : null,

        customFields: [
          // Batch No
          GlobalItemFormSheet.buildInputGroup(
            label: 'Batch No',
            color: Colors.purple,
            child: TextFormField(
              controller: controller.bsBatchController,
              readOnly: controller.bsIsBatchReadOnly.value,
              autofocus: false,
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
                suffixIcon: !controller.bsIsBatchReadOnly.value
                    ? IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: Colors.purple),
                  onPressed: () => controller.validateBatch(controller.bsBatchController.text),
                )
                    : const Icon(Icons.check_circle, color: Colors.purple),
              ),
              onFieldSubmitted: (value) => controller.validateBatch(value),
            ),
          ),

          // Invoice Serial
          if (controller.posUploadSerialOptions.isNotEmpty)
            GlobalItemFormSheet.buildInputGroup(
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
            ),

          // Rack Fields
          Builder(builder: (context) {
            final type = controller.selectedStockEntryType.value;
            final showSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
            final showTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showSource)
                      Expanded(
                        child: GlobalItemFormSheet.buildInputGroup(
                          label: 'Source Rack',
                          color: Colors.orange,
                          child: TextFormField(
                            controller: controller.bsSourceRackController,
                            focusNode: controller.sourceRackFocusNode,
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
                              suffixIcon: controller.isSourceRackValid.value
                                  ? const Icon(Icons.check_circle, color: Colors.orange, size: 20)
                                  : IconButton(
                                icon: const Icon(Icons.arrow_forward, color: Colors.orange),
                                onPressed: () => controller.validateRack(controller.bsSourceRackController.text, true),
                              ),
                            ),
                            onFieldSubmitted: (val) => controller.validateRack(val, true),
                          ),
                        ),
                      ),

                    if (showSource && showTarget) const SizedBox(width: 12),

                    if (showTarget)
                      Expanded(
                        child: GlobalItemFormSheet.buildInputGroup(
                          label: 'Target Rack',
                          color: Colors.green,
                          child: TextFormField(
                            controller: controller.bsTargetRackController,
                            focusNode: controller.targetRackFocusNode,
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
                              suffixIcon: controller.isTargetRackValid.value
                                  ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                  : IconButton(
                                icon: const Icon(Icons.arrow_forward, color: Colors.green),
                                onPressed: () => controller.validateRack(controller.bsTargetRackController.text, false),
                              ),
                            ),
                            onFieldSubmitted: (val) => controller.validateRack(val, false),
                          ),
                        ),
                      ),
                  ],
                ),
                if (controller.rackError.value != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                    child: Text(
                      controller.rackError.value!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            );
          }),
        ],
      );
    });
  }
}