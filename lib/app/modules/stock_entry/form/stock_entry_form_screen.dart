import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:intl/intl.dart';

class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.stockEntry.value?.name ?? 'Loading...')),
          actions: [
            Obx(() => controller.isSaving.value 
              ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Colors.white)))
              : IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: controller.saveStockEntry,
                )),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Items'),
            ],
          ),
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          final entry = controller.stockEntry.value;
          if (entry == null) {
            return const Center(child: Text('Stock entry not found.'));
          }

          return TabBarView(
            children: [
              _buildDetailsView(context, entry),
              _buildItemsView(context, entry),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(BuildContext context, StockEntry entry) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        child: Obx(() {
          final type = controller.selectedStockEntryType.value;
          final isMaterialIssue = type == 'Material Issue';
          final isMaterialReceipt = type == 'Material Receipt';
          final isMaterialTransfer = type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

          final showReferenceNo = isMaterialIssue;
          final showFromWarehouse = isMaterialIssue || isMaterialTransfer;
          final showToWarehouse = isMaterialReceipt || isMaterialTransfer;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: controller.selectedStockEntryType.value,
                decoration: const InputDecoration(
                  labelText: 'Stock Entry Type',
                  border: OutlineInputBorder(),
                ),
                items: controller.stockEntryTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (value) => controller.selectedStockEntryType.value = value!,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: entry.postingDate,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Posting Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: entry.postingTime,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Posting Time',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Warehouses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              if (showFromWarehouse) ...[
                DropdownButtonFormField<String>(
                  value: controller.selectedFromWarehouse.value,
                  decoration: const InputDecoration(
                    labelText: 'From Warehouse',
                    border: OutlineInputBorder(),
                    helperText: 'Source Warehouse',
                  ),
                  items: controller.warehouses.map((wh) {
                    return DropdownMenuItem(value: wh, child: Text(wh, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (value) => controller.selectedFromWarehouse.value = value,
                  isExpanded: true,
                ),
                const SizedBox(height: 16),
              ],

              if (showToWarehouse) ...[
                DropdownButtonFormField<String>(
                  value: controller.selectedToWarehouse.value,
                  decoration: const InputDecoration(
                    labelText: 'To Warehouse',
                    border: OutlineInputBorder(),
                    helperText: 'Target Warehouse',
                  ),
                  items: controller.warehouses.map((wh) {
                    return DropdownMenuItem(value: wh, child: Text(wh, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (value) => controller.selectedToWarehouse.value = value,
                  isExpanded: true,
                ),
                const SizedBox(height: 16),
              ],

              if (showReferenceNo) ...[
                TextFormField(
                  controller: controller.customReferenceNoController,
                  decoration: const InputDecoration(
                    labelText: 'Reference No',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (controller.posUploadSerialOptions.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: controller.selectedSerial.value,
                    decoration: const InputDecoration(
                      labelText: 'Invoice Serial Number',
                      border: OutlineInputBorder(),
                    ),
                    items: controller.posUploadSerialOptions.map((s) {
                      return DropdownMenuItem(value: s, child: Text(s));
                    }).toList(),
                    onChanged: (value) => controller.selectedSerial.value = value,
                  ),
                if (controller.posUploadSerialOptions.isNotEmpty) const SizedBox(height: 16),
              ],

              if (entry.name != 'New Stock Entry') ...[
                 const Divider(),
                 _buildReadOnlyRow('Status', entry.status),
                 _buildReadOnlyRow('Total Amount', entry.totalAmount.toStringAsFixed(2)),
                 if (entry.owner != null) _buildReadOnlyRow('Owner', entry.owner!),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, StockEntry entry) {
    final items = entry.items;

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items in this entry.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(2),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Code + Name
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 15)),
                                      if (item.itemName != null)
                                        Text(item.itemName!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Text('${item.qty} qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              ],
                            ),
                            const Divider(height: 20),
                            
                            // Details Grid
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                if (item.batchNo != null) _buildItemStat('Batch', item.batchNo!, isMono: true),
                                if (item.itemGroup != null) _buildItemStat('Group', item.itemGroup!),
                                if (item.customVariantOf != null) _buildItemStat('Variant Of', item.customVariantOf!),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Warehouse/Rack Flow (Requirement 6)
                            Obx(() {
                              final type = controller.selectedStockEntryType.value;
                              final showSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
                              final showTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
                              
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  children: [
                                    if (showSource) Expanded(child: _buildLocationInfo('Source', item.sWarehouse, item.rack)),
                                    if (showSource && showTarget) const Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                                    if (showTarget) Expanded(child: _buildLocationInfo('Target', item.tWarehouse, item.toRack)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        _buildBottomScanField(context),
      ],
    );
  }

  Widget _buildItemStat(String label, String value, {bool isMono = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, fontFamily: isMono ? 'monospace' : null)),
      ],
    );
  }

  Widget _buildLocationInfo(String label, String? warehouse, String? rack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        if (warehouse != null) Text(warehouse, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (rack != null) Text('$rack', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildBottomScanField(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: TextFormField(
          controller: controller.barcodeController,
          decoration: InputDecoration(
            hintText: 'Scan or enter barcode',
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: Obx(() => controller.isScanning.value
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => controller.scanBarcode(controller.barcodeController.text),
                )),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          ),
          onFieldSubmitted: (value) => controller.scanBarcode(value),
        ),
      ),
    );
  }
}

class StockEntryItemFormSheet extends GetView<StockEntryFormController> {
  const StockEntryItemFormSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView( // Fix overflow
        child: Container(
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 16.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.0, // Handle keyboard
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add Item', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('${controller.currentItemCode}${controller.currentVariantOf != '' ? ' | ${controller.currentVariantOf}' : ''}: ${controller.currentItemName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              
              // Batch No
              Obx(() => TextFormField(
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchReadOnly.value,
                autofocus: !controller.bsIsBatchReadOnly.value,
                decoration: InputDecoration(
                  labelText: 'Batch No',
                  border: const OutlineInputBorder(),
                  filled: controller.bsIsBatchReadOnly.value,
                  fillColor: controller.bsIsBatchReadOnly.value ? Colors.grey.shade100 : null,
                  suffixIcon: !controller.bsIsBatchReadOnly.value
                      ? IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () => controller.validateBatch(controller.bsBatchController.text),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green),
                ),
                onFieldSubmitted: (value) => controller.validateBatch(value),
              )),
              const SizedBox(height: 16),
              
              // Rack Fields
              Obx(() {
                final type = controller.selectedStockEntryType.value;
                final showSource = type == 'Material Issue' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
                final showTarget = type == 'Material Receipt' || type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

                return Column(
                  children: [
                    if (showSource) ...[
                      TextFormField(
                        controller: controller.bsSourceRackController,
                        focusNode: controller.sourceRackFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Source Rack',
                          border: const OutlineInputBorder(),
                          suffixIcon: controller.isSourceRackValid.value 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : IconButton(
                                  icon: const Icon(Icons.check),
                                  onPressed: () => controller.validateRack(controller.bsSourceRackController.text, true),
                                ),
                        ),
                        onFieldSubmitted: (val) => controller.validateRack(val, true),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (showTarget) ...[
                      TextFormField(
                        controller: controller.bsTargetRackController,
                        focusNode: controller.targetRackFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Target Rack',
                          border: const OutlineInputBorder(),
                          suffixIcon: controller.isTargetRackValid.value 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : IconButton(
                                  icon: const Icon(Icons.check),
                                  onPressed: () => controller.validateRack(controller.bsTargetRackController.text, false),
                                ),
                        ),
                        onFieldSubmitted: (val) => controller.validateRack(val, false),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              }),

              // Quantity
              TextFormField(
                controller: controller.bsQtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                child: Obx(() => ElevatedButton(
                  onPressed: controller.bsIsBatchValid.value ? controller.addItem : null,
                  child: const Text('Add Item'),
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
