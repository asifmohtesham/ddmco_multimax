import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/controllers/stock_entry_item_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class StockEntryItemFormSheet extends StatelessWidget {
  // Use the ITEM controller, not the main Form controller
  final StockEntryItemFormController controller;
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
      // We need to access parent for docstatus, but ItemController should have that logic or expose it
      // Assuming passed controller handles "isSaveEnabled" logic based on parent status internally or we rely on parent via controller._parent
      // For safety, we just use isSheetValid for now.

      return GlobalItemFormSheet(
        key: ValueKey(controller.currentItemNameKey.value ?? 'new'),
        formKey: controller.itemFormKey, // If global sheet needs key, pass it. Assuming it manages internal state or passed via controller.
        scrollController: scrollController,
        title: isEditing ? 'Update Item' : 'Add Item',
        itemCode: controller.itemCode.value,
        itemName: controller.itemName.value,
        itemSubtext: controller.customVariantOf,

        // Disable main Qty field editing if using batches
        isQtyReadOnly: controller.currentBatches.isNotEmpty,
        qtyController: controller.qtyController,

        // Add simple increment logic if needed, or rely on text field
        onIncrement: () {
          double current = double.tryParse(controller.qtyController.text) ?? 0;
          controller.qtyController.text = (current + 1).toString();
        },
        onDecrement: () {
          double current = double.tryParse(controller.qtyController.text) ?? 0;
          if (current > 0) controller.qtyController.text = (current - 1).toString();
        },
        qtyInfoText: null,

        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true, // Controlled by Rx above

        isLoading: false, // controller.isAddingItem.value (if async submit)
        onSubmit: controller.submit,
        onDelete: isEditing
            ? () => controller.deleteItem() // Ensure deleteItem exists in ItemController or calls parent
            : null,

        owner: controller.itemOwner.value,
        creation: controller.itemCreation.value,
        modified: controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        customFields: [
          // --- Toggle Batch Mode ---
          Obx(() => SwitchListTile(
            title: const Text('Use Serial/Batch Fields', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Toggle between Legacy Field and Bundle', style: TextStyle(fontSize: 12, color: Colors.grey)),
            value: controller.useSerialBatchFields.value,
            onChanged: (val) {
              controller.useSerialBatchFields.value = val;
              // Optional: Clear batch controller when switching to avoid confusion
              // controller.batchController.clear();
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          )),

          // --- Conditional Batch Input ---
          Obx(() {
            if (controller.useSerialBatchFields.value) {
              // 1. Legacy Single Field (Use Serial/Batch Fields = Checked)
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlobalItemFormSheet.buildInputGroup(
                  label: 'Batch No',
                  color: Colors.purple,
                  child: TextFormField(
                    controller: controller.batchController,
                    decoration: const InputDecoration(
                      hintText: 'Enter Batch No',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      suffixIcon: Icon(Icons.qr_code, color: Colors.purple),
                    ),
                    onChanged: (val) => controller.validateBatch(val),
                  ),
                ),
              );
            } else {
              // 2. Serial and Batch Bundle Manager (Use Serial/Batch Fields = Unchecked)
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Serial and Batch Bundle', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                    const SizedBox(height: 8),

                    // Batch Entry Row
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: controller.batchController,
                            decoration: const InputDecoration(
                              hintText: 'Batch No',
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.purple),
                          onPressed: () {
                            if (controller.batchController.text.isNotEmpty) {
                              controller.addBatch(controller.batchController.text, 1.0);
                              controller.batchController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(),

                    // Batch List
                    if (controller.currentBatches.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No batches added.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: controller.currentBatches.length,
                        itemBuilder: (context, index) {
                          final batch = controller.currentBatches[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(batch.batchNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${batch.qty}'),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed: () => controller.removeBatch(index),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            }
          }),

          // Batch Validation Error (Shared)
          if (controller.batchError.value != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(controller.batchError.value!, style: const TextStyle(color: Colors.red)),
            ),

          // Invoice Serial (Context specific)
          // Access parent properties via controller.parent if needed

          // --- Warehouse Fields ---
          // Using Dropdowns if list available, otherwise text fields or disabled if fixed
          if (controller.itemSourceWarehouse.value != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlobalItemFormSheet.buildInputGroup(
                label: 'Source Warehouse',
                color: Colors.orange,
                child: Text(controller.itemSourceWarehouse.value!, style: const TextStyle(fontSize: 16)),
              ),
            ),

          // Rack Fields
          Row(
            children: [
              Expanded(
                child: GlobalItemFormSheet.buildInputGroup(
                    label: 'Source Rack',
                    color: Colors.orange,
                    bgColor: controller.isSourceRackValid.value ? Colors.orange.shade50 : null,
                    child: TextFormField(
                      controller: controller.sourceRackController,
                      decoration: const InputDecoration(hintText: 'Rack', border: OutlineInputBorder()),
                      onFieldSubmitted: (v) => controller.validateRack(v, isSource: true),
                    )
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlobalItemFormSheet.buildInputGroup(
                    label: 'Target Rack',
                    color: Colors.green,
                    bgColor: controller.isTargetRackValid.value ? Colors.green.shade50 : null,
                    child: TextFormField(
                      controller: controller.targetRackController,
                      decoration: const InputDecoration(hintText: 'Rack', border: OutlineInputBorder()),
                      onFieldSubmitted: (v) => controller.validateRack(v, isSource: false),
                    )
                ),
              )
            ],
          ),

          if (controller.rackError.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(controller.rackError.value!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
        ],
      );
    });
  }
}