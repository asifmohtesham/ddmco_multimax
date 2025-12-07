import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/widgets/stock_entry_item_card.dart';
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
              onPressed: controller.stockEntry.value?.docstatus == 0 ? () => controller.saveStockEntry : null,
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
            padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 0),
            itemBuilder: (context, index) {
              final item = items[index];
              return StockEntryItemCard(item: item, index: index);
            },
          ),
        ),
        _buildBottomScanField(context),
      ],
    );
  }

  Widget _buildBottomScanField(BuildContext context) {
    if (controller.stockEntry.value?.docstatus != 0) return Container();

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
                        controller.currentItemNameKey != null ? 'Edit Item' : 'Add Item',
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

            // Batch Field with styling
            Obx(() => _buildInputGroup(
              label: 'Batch No',
              color: Colors.purple,
              child: TextFormField(
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchReadOnly.value,
                autofocus: !controller.bsIsBatchReadOnly.value,
                decoration: InputDecoration(
                  hintText: 'Enter or scan batch',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.purple),
                  ),
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

            // Invoice Serial Dropdown (if available)
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

              return Row(
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
              );
            }),

            const SizedBox(height: 16),

            // Quantity Field with Controls
            _buildInputGroup(
              label: 'Quantity',
              color: Colors.black87,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller.bsQtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  _buildQtyButton(Icons.remove, () => controller.adjustSheetQty(-1)),
                  _buildQtyButton(Icons.add, () => controller.adjustSheetQty(1)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            Obx(() {
              // Determine if button should be active
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
                  controller.currentItemNameKey != null ? 'Update Item' : 'Add Item',
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
            color: color.withOpacity(0.05), // Very light background tint
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}