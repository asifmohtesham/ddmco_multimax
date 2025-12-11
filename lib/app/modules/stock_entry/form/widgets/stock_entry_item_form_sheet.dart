import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';

class StockEntryItemFormSheet extends GetView<StockEntryFormController> {
  final ScrollController? scrollController;

  const StockEntryItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        child: ListView(
          controller: scrollController,
          shrinkWrap: true,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.currentItemNameKey.value != null ? 'Edit Item' : 'Add Item',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${controller.currentItemCode}${controller.currentVariantOf != '' ? ' • ${controller.currentVariantOf}' : ''}',
                        style: const TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'monospace'),
                      ),
                      Text(
                        controller.currentItemName,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close),
                  style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                ),
              ],
            ),
            const Divider(height: 24),

            // Batch No
            Obx(() => _buildInputGroup(
              label: 'Batch No',
              color: Colors.purple,
              child: TextFormField(
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchReadOnly.value,
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
                  suffixIcon: !controller.bsIsBatchReadOnly.value
                      ? IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.purple),
                    onPressed: () => controller.validateBatch(controller.bsBatchController.text),
                  )
                      : const Icon(Icons.check_circle, color: Colors.purple),
                ),
                onFieldSubmitted: (value) => controller.validateBatch(value),
              ),
            )),

            const SizedBox(height: 16),

            // Invoice Serial
            Obx(() {
              if (controller.posUploadSerialOptions.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildInputGroup(
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
              );
            }),

            // Rack Fields Row
            Obx(() {
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
                          child: _buildInputGroup(
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
                                    : null,
                              ),
                              onFieldSubmitted: (val) => controller.validateRack(val, true),
                            ),
                          ),
                        ),

                      if (showSource && showTarget) const SizedBox(width: 12),

                      if (showTarget)
                        Expanded(
                          child: _buildInputGroup(
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
                                    : null,
                              ),
                              onFieldSubmitted: (val) => controller.validateRack(val, false),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Display Rack Error
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

            const SizedBox(height: 16),

            // Quantity Input
            Obx(() => QuantityInputWidget(
              controller: controller.bsQtyController,
              onIncrement: () => controller.adjustSheetQty(1),
              onDecrement: () => controller.adjustSheetQty(-1),
              label: 'Quantity',
              // Passing formatted info text
              infoText: controller.bsMaxQty.value > 0
                  ? 'Stock Balance: ${controller.bsMaxQty.value}'
                  : null,
            )),

            const SizedBox(height: 24),

            Obx(() {
              final isValid = controller.isSheetValid.value;
              return ElevatedButton(
                onPressed: isValid && controller.stockEntry.value?.docstatus == 0
                    ? controller.addItem
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: isValid ? Theme.of(context).primaryColor : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: isValid ? 2 : 0,
                ),
                child: Text(
                  controller.currentItemNameKey.value != null ? 'Update Item' : 'Add Item',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildInputGroup({required String label, required Color color, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }
}