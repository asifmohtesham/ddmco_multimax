import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';
// Ensure you import the new card widget
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_item_card.dart';

class PurchaseReceiptFormScreen extends GetView<PurchaseReceiptFormController> {
  const PurchaseReceiptFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            final receipt = controller.purchaseReceipt.value;
            final name = receipt?.name ?? 'Loading...';
            final supplier = receipt?.supplier;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                if (supplier != null && supplier.isNotEmpty)
                  Text(supplier, style: const TextStyle(fontSize: 16)),
              ],
            );
          }),
          actions: [
            Obx(() {
              if (controller.purchaseReceipt.value?.docstatus == 1) return const SizedBox.shrink();

              return controller.isSaving.value
                  ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                  )
              )
                  : IconButton(
                icon: const Icon(Icons.save),
                onPressed: controller.savePurchaseReceipt,
              );
            }),
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

          return SafeArea(
            child: TabBarView(
              children: [
                _buildDetailsView(context, receipt),
                _buildItemsView(context, receipt),
              ],
            ),
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
            // Standardizing input decoration look
            TextFormField(
              controller: controller.supplierController,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
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
        // Scan Field Moved to Top for Consistency with DeliveryNote
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Obx(() {
            String labelText = 'Scan or enter barcode';
            Widget? suffixIcon;

            if (controller.isScanning.value) {
              labelText = 'Scanning...';
              suffixIcon = const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              );
            } else {
              suffixIcon = IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => controller.scanBarcode(controller.barcodeController.text),
              );
            }

            return TextFormField(
              controller: controller.barcodeController,
              decoration: InputDecoration(
                labelText: labelText,
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: suffixIcon,
                border: const OutlineInputBorder(),
              ),
              onFieldSubmitted: (value) => controller.scanBarcode(value),
            );
          }),
        ),
        const Divider(),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items in this receipt.'))
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 80.0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return PurchaseReceiptItemCard(item: item, index: index);
            },
          ),
        ),
      ],
    );
  }
}

class PurchaseReceiptItemFormSheet extends GetView<PurchaseReceiptFormController> {
  // Added ScrollController for DraggableScrollableSheet support
  final ScrollController? scrollController;

  const PurchaseReceiptItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    // Draggable Sheet implementation pattern
    if (scrollController == null) {
      // Fallback if called directly via Get.bottomSheet without Draggable wrapper
      // But typically we should wrap the call in DraggableScrollableSheet
      return _buildContent(context);
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      controller.currentItemNameKey != null ? 'Edit Item' : 'Add Item',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (controller.currentOwner.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    children: [
                      Text(
                        '${controller.currentOwner} • ${controller.getRelativeTime(controller.currentCreation)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

              // Item Details Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildReadOnlyRow('Item Code', controller.currentItemCode),
                    const Divider(height: 16),
                    _buildReadOnlyRow('Item Name', controller.currentItemName),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Batch No
              Obx(() => TextFormField(
                controller: controller.bsBatchController,
                readOnly: controller.bsIsBatchReadOnly.value,
                autofocus: !controller.bsIsBatchReadOnly.value && controller.currentItemNameKey == null,
                decoration: InputDecoration(
                  labelText: 'Batch No',
                  border: const OutlineInputBorder(),
                  filled: controller.bsIsBatchReadOnly.value,
                  fillColor: controller.bsIsBatchReadOnly.value ? Colors.grey.shade100 : null,
                  suffixIcon: isValidatingIcon(
                    controller.isValidatingBatch.value,
                    controller.bsIsBatchValid.value,
                    isReadOnly: controller.bsIsBatchReadOnly.value,
                    onCheck: () => controller.validateBatch(controller.bsBatchController.text),
                  ),
                ),
                onFieldSubmitted: (value) => controller.validateBatch(value),
              )),
              const SizedBox(height: 16),

              // Rack Fields
              Obx(() {
                return TextFormField(
                  controller: controller.bsRackController,
                  focusNode: controller.targetRackFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Target Rack',
                    border: const OutlineInputBorder(),
                    suffixIcon: isValidatingIcon(
                      controller.isValidatingTargetRack.value,
                      controller.isTargetRackValid.value,
                      onCheck: () => controller.validateRack(controller.bsRackController.text, false),
                    ),
                  ),
                  onFieldSubmitted: (val) => controller.validateRack(val, false),
                );
              }),
              const SizedBox(height: 16),

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

              if (controller.currentModifiedBy.isNotEmpty) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Last modified by ${controller.currentModifiedBy} • ${controller.getRelativeTime(controller.currentModified)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              SizedBox(
                width: double.infinity,
                child: Obx(() => ElevatedButton(
                  onPressed: controller.bsIsBatchValid.value ? controller.addItem : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  child: Text(controller.currentItemNameKey != null ? 'Update Item' : 'Add Item'),
                )),
              ),
              // Add padding for keyboard
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget? isValidatingIcon(bool isLoading, bool isValid, {bool isReadOnly = false, VoidCallback? onCheck}) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (isValid || isReadOnly) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    return IconButton(
      icon: const Icon(Icons.check),
      onPressed: onCheck,
    );
  }
}