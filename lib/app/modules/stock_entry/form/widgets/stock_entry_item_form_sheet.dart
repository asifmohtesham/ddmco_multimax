import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/controllers/stock_entry_item_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';

class StockEntryItemFormSheet extends StatelessWidget {
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

      return GlobalItemFormSheet(
        key: ValueKey(controller.currentItemNameKey.value ?? 'new'),
        formKey: controller.itemFormKey,
        scrollController: scrollController,
        title: isEditing ? 'Update Item' : 'Add Item',

        // --- Standard Item Fields ---
        itemCode: controller.itemCode.value,
        itemName: controller.itemName.value,
        itemSubtext: controller.customVariantOf,

        // --- Quantity Control ---
        // If a bundle is active, we generally prefer the bundle manager to dictate qty,
        // but we allow manual override which then requires bundle update.
        isQtyReadOnly: controller.currentBundleId.value != null,
        qtyController: controller.qtyController,
        onIncrement: () => _modifyQty(1),
        onDecrement: () => _modifyQty(-1),

        // --- Actions ---
        isSaveEnabledRx: controller.isSaveEnabled,
        onSubmit: () => controller.submit(closeSheet: true),
        onDelete: isEditing ? controller.deleteItem : null,

        // --- Metadata ---
        owner: controller.itemOwner.value,
        creation: controller.itemCreation.value,
        modified: controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // --- Custom Form Body ---
        customFields: [
          _buildValidationErrors(),
          _buildInventoryDimensionFields(context),
          const SizedBox(height: 16),
          _buildBatchManagerSection(context),
        ],
      );
    });
  }

  void _modifyQty(double delta) {
    double current = double.tryParse(controller.qtyController.text) ?? 0;
    double newValue = current + delta;
    if (newValue >= 0) controller.qtyController.text = newValue.toString();
  }

  // --- Section: Inventory (Source/Target) ---
  Widget _buildInventoryDimensionFields(BuildContext context) {
    return Column(
      children: [
        // SOURCE
        _buildLocationColumn(
          label: 'Source Rack',
          warehouse: controller.itemSourceWarehouse.value,
          rackController: controller.sourceRackController,
          isValid: controller.isSourceRackValid.value,
          onValidate: (v) => controller.validateRack(v, isSource: true),
          iconColor: Colors.orange,
        ),
        const SizedBox(height: 12),

        // TARGET
        _buildLocationColumn(
          label: 'Target Rack',
          warehouse: controller.itemTargetWarehouse.value,
          rackController: controller.targetRackController,
          isValid: controller.isTargetRackValid.value,
          onValidate: (v) => controller.validateRack(v, isSource: false),
          iconColor: Colors.green,
        ),
      ],
    );
  }

  Widget _buildLocationColumn({
    required String label,
    required String? warehouse,
    required TextEditingController rackController,
    required bool isValid,
    required Function(String) onValidate,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
                'Warehouse',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)
            ),
            if (warehouse != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  warehouse,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: iconColor),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: rackController,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            label: Text(label),
            hintText: 'Scan $label Rack',
            isDense: true,
            filled: true,
            fillColor: isValid ? iconColor.withValues(alpha: 0.05) : Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: iconColor)),
            prefixIcon: Icon(Icons.dns_outlined, size: 16, color: Colors.grey.shade400),
            suffixIcon: Icon(Icons.qr_code_scanner, size: 18, color: iconColor),
          ),
          onFieldSubmitted: onValidate,
        ),
      ],
    );
  }

  // --- Section: Batch Bundle Manager ---
  Widget _buildBatchManagerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Serial / Batch Bundle", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),

        // Button to Open Manager
        OutlinedButton.icon(
          onPressed: controller.openBatchManager,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(controller.currentBundleId.value == null ? "Select Batches" : "Edit Batches"),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: Colors.blue.shade300),
          ),
        ),

        // Bundle Summary Preview
        if (controller.currentBundleEntries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${controller.currentBundleEntries.length} entries", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (controller.currentBundleId.value != null)
                        Text(controller.currentBundleId.value!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: controller.currentBundleEntries.length > 5 ? 5 : controller.currentBundleEntries.length,
                  separatorBuilder: (_,__) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final entry = controller.currentBundleEntries[idx];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(entry.batchNo ?? entry.serialNo ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      trailing: Text(entry.qty.toString(), style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
                if (controller.currentBundleEntries.length > 5)
                  Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text("+ ${controller.currentBundleEntries.length - 5} more", style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                  )
              ],
            ),
          )
        ]
      ],
    );
  }

  Widget _buildValidationErrors() {
    return Obx(() {
      if (controller.rackError.value != null) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          color: Colors.red.shade50,
          child: Row(
            children: [
              Icon(Icons.warning, size: 16, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(controller.rackError.value!, style: TextStyle(color: Colors.red.shade800, fontSize: 12))),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    });
  }
}