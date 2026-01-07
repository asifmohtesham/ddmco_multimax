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
        // FIX: Check currentBundleEntries instead of currentBatches
        isQtyReadOnly: controller.currentBundleEntries.isNotEmpty,
        qtyController: controller.qtyController,
        onIncrement: () => _modifyQty(1),
        onDecrement: () => _modifyQty(-1),

        // --- Actions ---
        isSaveEnabledRx: controller.isSheetValid,
        isSaveEnabled: true,
        onSubmit: controller.submit,
        onDelete: isEditing ? controller.deleteItem : null,

        // --- Metadata ---
        owner: controller.itemOwner.value,
        creation: controller.itemCreation.value,
        modified: controller.itemModified.value,
        modifiedBy: controller.itemModifiedBy.value,

        // --- Custom Form Body ---
        customFields: [
          _buildBatchIdentificationSection(context),
          _buildStockMovementSection(context),
          _buildValidationErrors(),
        ],
      );
    });
  }

  void _modifyQty(double delta) {
    double current = double.tryParse(controller.qtyController.text) ?? 0;
    double newValue = current + delta;
    if (newValue >= 0) controller.qtyController.text = newValue.toString();
  }

  // --- Section: Stock Movement (Warehouses & Racks) ---
  Widget _buildStockMovementSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows_rounded, size: 18, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text('Stock Movement', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.blueGrey)),
            ],
          ),
          const Divider(height: 20),

          // Vertically Stacked Movement Fields
          Column(
            children: [
              // SOURCE
              _buildLocationColumn(
                label: 'From',
                warehouse: controller.itemSourceWarehouse.value,
                rackController: controller.sourceRackController,
                isValid: controller.isSourceRackValid.value,
                onValidate: (v) => controller.validateRack(v, isSource: true),
                iconColor: Colors.orange,
              ),

              // Vertical Directional Arrow
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(Icons.arrow_downward, color: Colors.grey.shade400, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Text('Transferring to...', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),

              // TARGET
              _buildLocationColumn(
                label: 'To',
                warehouse: controller.itemTargetWarehouse.value,
                rackController: controller.targetRackController,
                isValid: controller.isTargetRackValid.value,
                onValidate: (v) => controller.validateRack(v, isSource: false),
                iconColor: Colors.green,
              ),
            ],
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row for Label and Warehouse to save vertical space
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  label,
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
                    warehouse.split('-').first.trim(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: iconColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Rack Input
          TextFormField(
            controller: rackController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
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
      ),
    );
  }

  // --- Section: Batch & Serial (Identification) ---
  Widget _buildBatchIdentificationSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Toggle Header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => controller.useSerialBatchFields.toggle(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined, size: 18, color: Colors.purple),
                      const SizedBox(width: 8),
                      Text('Identification', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.purple)),
                    ],
                  ),
                  Row(
                    children: [
                      Text(controller.useSerialBatchFields.value ? 'Legacy' : 'Bundle',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      const SizedBox(width: 4),
                      Icon(controller.useSerialBatchFields.value ? Icons.toggle_off : Icons.toggle_on,
                          color: Colors.purple, size: 24),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(12),
            child: controller.useSerialBatchFields.value
                ? _buildLegacyBatchInput()
                : _buildBundleManager(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyBatchInput() {
    return TextFormField(
      controller: controller.batchController,
      decoration: InputDecoration(
        labelText: 'Batch Number',
        hintText: 'Enter Batch No',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.tag, size: 18),
        suffixIcon: controller.isBatchValid.value
            ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
            : null,
      ),
      onChanged: controller.validateBatch,
    );
  }

  Widget _buildBundleManager(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Add Batch Input Row
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: controller.batchController,
                decoration: InputDecoration(
                  hintText: 'Scan/Enter Batch',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add, color: Colors.purple),
                    onPressed: () {
                      if (controller.batchController.text.isNotEmpty) {
                        controller.addEntry(controller.batchController.text, 1.0);
                        controller.batchController.clear();
                      }
                    },
                  ),
                ),
                onFieldSubmitted: (val) {
                  if (val.isNotEmpty) {
                    controller.addEntry(val, 1.0);
                    controller.batchController.clear();
                  }
                },
              ),
            ),
          ],
        ),

        // Batch List
        if (controller.currentBundleEntries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: controller.currentBundleEntries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _buildBatchRow(context, index),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: Text(
                'No batches added',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBatchRow(BuildContext context, int index) {
    final batch = controller.currentBundleEntries[index];
    final isOutward = ['Material Issue', 'Material Transfer']
        .contains(controller.parent.selectedStockEntryType.value);

    return TextFormField(
      // Key ensures focus is preserved correctly if list reorders/updates
      key: ValueKey(batch.batchNo),
      initialValue: batch.qty.abs().toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),

        // Requirement: Prepend Batch No as prefix
        prefixIcon: Container(
          width: 150,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Text(
            batch.batchNo ?? '-',
            style: const TextStyle(
              fontFamily: 'ShureTechMono',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black54
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),

        // Requirement: Append Remove button as suffix
        suffixIcon: IconButton(
          icon: Icon(Icons.close, size: 18, color: Colors.red.shade300),
          onPressed: () => controller.removeEntry(index),
          tooltip: 'Remove',
        ),
      ),
      onChanged: (val) {
        final qty = double.tryParse(val);
        if (qty != null) {
          // Requirement: Negative if Outward, Positive if Inward
          final signedQty = isOutward ? -qty.abs() : qty.abs();
          controller.updateEntryQty(index, signedQty);
        }
      },
    );
  }

  Widget _buildValidationErrors() {
    return Column(
      children: [
        if (controller.batchError.value != null)
          _errorBanner(controller.batchError.value!),
        if (controller.rackError.value != null)
          _errorBanner(controller.rackError.value!),
      ],
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: Colors.red.shade800, fontSize: 12))),
        ],
      ),
    );
  }
}