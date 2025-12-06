import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';

class PurchaseReceiptFormScreen extends GetView<PurchaseReceiptFormController> {
  const PurchaseReceiptFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.purchaseReceipt.value?.name ?? 'Loading...')),
          actions: [
            if (controller.purchaseReceipt.value?.docstatus == 0)
              Obx(() => controller.isSaving.value
                ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Colors.white)))
                : IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: controller.savePurchaseReceipt,
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

          final receipt = controller.purchaseReceipt.value;
          if (receipt == null) {
            return const Center(child: Text('Purchase receipt not found.'));
          }

          return TabBarView(
            children: [
              _buildDetailsView(context, receipt),
              _buildItemsView(context, receipt),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(BuildContext context, PurchaseReceipt receipt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller.supplierController,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                border: OutlineInputBorder(),
              ),
              readOnly: true, 
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller.postingDateController,
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
                    controller: controller.postingTimeController,
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
            Obx(() => DropdownButtonFormField<String>(
              value: controller.setWarehouse.value,
              decoration: const InputDecoration(
                labelText: 'Set Accepted Warehouse',
                border: OutlineInputBorder(),
              ),
              items: controller.warehouses.map((wh) {
                return DropdownMenuItem(value: wh, child: Text(wh, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (value) => controller.setWarehouse.value = value,
            )),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  DefaultTabController.of(context).animateTo(1);
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next: Add Items'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, PurchaseReceipt receipt) {
    final items = receipt.items;

    return Column(
      children: [
        Expanded(
          child: items.isEmpty ?
            const Center(child: Text('No items in this receipt.')) :
            ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                             CircleAvatar(
                                radius: 12, 
                                backgroundColor: Colors.grey.shade200,
                                child: Text('${index + 1}', style: const TextStyle(fontSize: 10, color: Colors.black)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${item.itemCode}: ${item.itemName ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => controller.editItem(item),
                              ),
                          ],
                        ),
                        const Divider(height: 20),
                        if (item.batchNo != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text('Batch: ${item.batchNo}', style: const TextStyle(fontFamily: 'monospace')),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoColumn('Rack', item.rack ?? 'N/A'),
                            _buildInfoColumn('Quantity', NumberFormat('#,##0.##').format(item.qty)),
                          ],
                        ),
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

  Widget _buildInfoColumn(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
          ),
        ),
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
                ? Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
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

class PurchaseReceiptItemFormSheet extends GetView<PurchaseReceiptFormController> {
  const PurchaseReceiptItemFormSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView( 
        child: Container(
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 16.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.0, 
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.currentItemNameKey != null ? 'Edit Item' : 'Add Item', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Text(
                      '${controller.currentOwner} • ${controller.getRelativeTime(controller.currentCreation)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Item Code
              TextFormField(
                readOnly: true,
                initialValue: '${controller.currentItemCode}',
                decoration: InputDecoration(
                  labelText: 'Item Code',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  suffixIcon: const Icon(Icons.check_circle, color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),

              // Item Name
              TextFormField(
                readOnly: true,
                initialValue: '${controller.currentItemName}',
                decoration: InputDecoration(
                  labelText: 'Item Name',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  suffixIcon: const Icon(Icons.check_circle, color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),

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
                return Column(
                  children: [
                    TextFormField(
                      controller: controller.bsRackController,
                      focusNode: controller.targetRackFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Target Rack',
                        border: const OutlineInputBorder(),
                        suffixIcon: controller.isTargetRackValid.value
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : IconButton(
                          icon: const Icon(Icons.check),
                          onPressed: () => controller.validateRack(controller.bsRackController.text, false),
                        ),
                      ),
                      onFieldSubmitted: (val) => controller.validateRack(val, false),
                    ),
                    const SizedBox(height: 16),
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

              if (controller.currentModifiedBy.isNotEmpty) const SizedBox(height: 16),
              if (controller.currentModifiedBy.isNotEmpty) const Divider(),
              // Footer: Modified info
              if (controller.currentModifiedBy.isNotEmpty) Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Last modified by ${controller.currentModifiedBy} • ${controller.getRelativeTime(controller.currentModified)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: Obx(() => ElevatedButton(
                  onPressed: controller.bsIsBatchValid.value ? controller.addItem : null,
                  child: Text(controller.currentItemNameKey != null ? 'Save' : 'Add Item'),
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
