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
          _buildSerialBatchBundleFields(context),
          _buildInventoryDimensionFields(context),
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

        // Directional Arrow
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
                    warehouse,
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
  Widget _buildSerialBatchBundleFields(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Searchable Dropdown for Batch Input
            RawAutocomplete<Map<String, dynamic>>(
              textEditingController: controller.batchController,
              focusNode: FocusNode(),
              optionsBuilder: (TextEditingValue textEditingValue) {
                return controller.searchBatches(textEditingValue.text);
              },
              displayStringForOption: (option) => option['batch'] ?? '',
              onSelected: (option) {
                if (option['batch'] != null) {
                  controller.addEntry(option['batch'], 1.0);
                  controller.batchController.clear();
                }
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4.0,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: 200,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(
                              option['batch'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Balance: ${option['qty']}',
                              style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                return TextFormField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Scan/Enter Batch',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, color: Colors.purple),
                      onPressed: () {
                        if (textController.text.isNotEmpty) {
                          onFieldSubmitted();
                        }
                      },
                    ),
                  ),
                  onFieldSubmitted: (val) {
                    if (val.isNotEmpty) {
                      controller.addEntry(val, 1.0);
                      textController.clear();
                    }
                  },
                );
              },
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
      },
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        prefixIcon: Container(
          width: 140,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Text(
            batch.batchNo ?? '-',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),

        // Requirement: Append Remove button as suffix
        suffixIcon: controller.currentBundleEntries.length > 1 ? IconButton(
          icon: Icon(Icons.close, size: 18, color: Colors.red.shade300),
          onPressed: () => controller.removeEntry(index),
          tooltip: 'Remove',
        ) : null,
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