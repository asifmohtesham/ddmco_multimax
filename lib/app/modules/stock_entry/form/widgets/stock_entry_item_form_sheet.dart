import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
        isQtyReadOnly: controller.currentBatches.isNotEmpty,
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
          // const SizedBox(height: 12),
          _buildStockMovementSection(context),
          // const SizedBox(height: 16),
          _buildBatchIdentificationSection(context),
          // const SizedBox(height: 16),
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
    // Determine visibility based on logic (assuming controller has implicit logic, or we check field content)
    // For visual balance, we always reserve space but may disable fields
    final showSource = controller.itemSourceWarehouse.value != null || controller.sourceRackController.text.isNotEmpty;
    // Note: You might want to expose specific 'isSourceRequired' bools from controller for stricter logic

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SOURCE
              Expanded(
                child: _buildLocationColumn(
                  label: 'From',
                  warehouse: controller.itemSourceWarehouse.value,
                  rackController: controller.sourceRackController,
                  isValid: controller.isSourceRackValid.value,
                  onValidate: (v) => controller.validateRack(v, isSource: true),
                  iconColor: Colors.orange,
                ),
              ),

              // Directional Arrow
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 30),
                child: Icon(Icons.arrow_forward, color: Colors.grey.shade400, size: 20),
              ),

              // TARGET
              Expanded(
                child: _buildLocationColumn(
                  label: 'To',
                  warehouse: controller.itemTargetWarehouse.value,
                  rackController: controller.targetRackController,
                  isValid: controller.isTargetRackValid.value,
                  onValidate: (v) => controller.validateRack(v, isSource: false),
                  iconColor: Colors.green,
                ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warehouse Label
        if (warehouse != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              warehouse.split('-').first.trim(), // Minimalist: Show Code only
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('---', style: TextStyle(color: Colors.grey)),
          ),

        // Rack Input
        TextFormField(
          controller: rackController,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: '$label Rack',
            hintText: 'Scan/Enter',
            isDense: true,
            filled: true,
            fillColor: isValid ? iconColor.withValues(alpha: 0.05) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: iconColor)),
            suffixIcon: Icon(Icons.qr_code_scanner, size: 16, color: iconColor),
          ),
          onFieldSubmitted: onValidate,
        ),
      ],
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
        // Add Batch Row
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
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.purple.shade50,
                foregroundColor: Colors.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add),
              onPressed: () {
                if (controller.batchController.text.isNotEmpty) {
                  controller.addBatch(controller.batchController.text, 1.0);
                  controller.batchController.clear();
                }
              },
            ),
          ],
        ),

        // Batch List
        if (controller.currentBatches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(4),
              itemCount: controller.currentBatches.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 10, endIndent: 10),
              itemBuilder: (context, index) {
                final batch = controller.currentBatches[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(batch.batchNo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${batch.qty} units', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => controller.removeBatch(index),
                        child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.red.shade300),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(child: Text('No batches added', style: TextStyle(color: Colors.grey, fontSize: 12))),
          ),
      ],
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