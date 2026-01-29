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
      final isSabbMode = controller.useSerialBatchFields.value == 0;
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

        // Disable main Qty input in SABB mode to force using the bundle list sum?
        // Or keep it read-only. Let's keep it read-only if SABB.
        isQtyReadOnly: isSabbMode,

        customFields: [
          // --- LEGACY MODE: OLD BATCH FIELD ---
          if (!isSabbMode)
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

          // --- SABB MODE: INLINE ENTRIES ---
          if (isSabbMode) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Text("Batch Bundle Entries", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),

            // List of Added Batches
            Obx(() => Container(
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: controller.sabbEntries.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("No batches added")))
                  : ListView.separated(
                shrinkWrap: true,
                itemCount: controller.sabbEntries.length,
                separatorBuilder: (_,__) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final entry = controller.sabbEntries[index];
                  return ListTile(
                    dense: true,
                    title: Text(entry.batchNo, style: const TextStyle(fontFamily: 'ShureTechMono')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Qty: ${entry.qty}"),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => controller.removeSabbEntry(index),
                        )
                      ],
                    ),
                  );
                },
              ),
            )),

            const SizedBox(height: 12),

            // Inline Input for New Batch
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 2,
                  child: GlobalItemFormSheet.buildInputGroup(
                    label: 'Batch No',
                    color: Colors.purple,
                    child: TextField(
                      controller: controller.bsBatchController, // Reuse controller for temporary input
                      decoration: const InputDecoration(
                        hintText: 'Scan/Enter',
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) { /* Focus Qty? */ },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: GlobalItemFormSheet.buildInputGroup(
                    label: 'Qty',
                    color: Colors.purple,
                    child: TextField(
                      // You might need a separate controller for this temporary qty
                      // For now, assuming user types 1.0 or we add a temp controller to the class
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '1.0',
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (val) {
                        // Logic to add
                        final qty = double.tryParse(val) ?? 0;
                        controller.addSabbEntry(controller.bsBatchController.text, qty);
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.purple, size: 32),
                  onPressed: () {
                    // Simple implementation using fixed 1.0 or parsing a temp field
                    // Ideally, add `bsTempQtyController` to Controller
                    controller.addSabbEntry(controller.bsBatchController.text, 1.0);
                  },
                )
              ],
            ),
          ],

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

          // --- New Warehouse Fields ---
          Builder(builder: (context) {
            final type = controller.selectedStockEntryType.value;
            final showSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
            final showTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

            return Column(
              children: [
                if (showSource)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: GlobalItemFormSheet.buildInputGroup(
                      label: 'Source Warehouse',
                      color: Colors.orange,
                      child: Obx(() => DropdownButtonFormField<String>(
                        value: controller.bsItemSourceWarehouse.value,
                        decoration: InputDecoration(
                          hintText: 'Default: ${controller.selectedFromWarehouse.value ?? "None"}',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        isExpanded: true,
                        items: controller.warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => controller.bsItemSourceWarehouse.value = val,
                      )),
                    ),
                  ),

                if (showTarget)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: GlobalItemFormSheet.buildInputGroup(
                      label: 'Target Warehouse',
                      color: Colors.green,
                      child: Obx(() => DropdownButtonFormField<String>(
                        value: controller.bsItemTargetWarehouse.value,
                        decoration: InputDecoration(
                          hintText: 'Default: ${controller.selectedToWarehouse.value ?? "None"}',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        isExpanded: true,
                        items: controller.warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => controller.bsItemTargetWarehouse.value = val,
                      )),
                    ),
                  ),
              ],
            );
          }),

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