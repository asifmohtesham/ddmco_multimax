import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_item_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

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
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                      )
                  )
              )
                  : IconButton(
                icon: const Icon(Icons.save),
                // Enable save only if dirty AND draft
                onPressed: (controller.isDirty.value && controller.isEditable)
                    ? controller.savePurchaseReceipt
                    : null,
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
    final bool isEditable = controller.isEditable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              title: 'General Information',
              children: [
                if (receipt.name != 'New Purchase Receipt') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Receipt ID', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(receipt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                      StatusPill(status: receipt.status),
                    ],
                  ),
                  const Divider(height: 24),
                ],
                TextFormField(
                  controller: controller.supplierController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.business),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  readOnly: true, // Supplier generally fixed after creation via arg, or add picker if needed
                ),
              ],
            ),

            const SizedBox(height: 16),

            _buildSectionCard(
              title: 'Schedule',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller.postingDateController,
                        readOnly: !isEditable,
                        decoration: const InputDecoration(
                          labelText: 'Posting Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: controller.postingTimeController,
                        readOnly: !isEditable,
                        decoration: const InputDecoration(
                          labelText: 'Posting Time',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.access_time),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            _buildSectionCard(
              title: 'Settings',
              children: [
                Obx(() => DropdownButtonFormField<String>(
                  value: controller.setWarehouse.value,
                  decoration: const InputDecoration(
                    labelText: 'Set Accepted Warehouse',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  items: controller.warehouses.map((wh) {
                    return DropdownMenuItem(value: wh, child: Text(wh, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: isEditable ? (value) => controller.setWarehouse.value = value : null,
                )),
              ],
            ),

            const SizedBox(height: 16),

            _buildSectionCard(
                title: 'Summary',
                children: [
                  _buildSummaryRow('Total Quantity', '${receipt.totalQty.toStringAsFixed(2)} Items'),
                  const Divider(),
                  _buildSummaryRow(
                      'Grand Total',
                      '${FormattingHelper.getCurrencySymbol(receipt.currency)} ${receipt.grandTotal.toStringAsFixed(2)}',
                      isBold: true
                  ),
                ]
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ... (Helpers _buildSectionCard, _buildSummaryRow remain the same) ...

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(
              value,
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  fontSize: isBold ? 16 : 14,
                  color: isBold ? Colors.black87 : Colors.black54
              )
          ),
        ],
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, PurchaseReceipt receipt) {
    final items = receipt.items;

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items in this receipt.'))
              : ListView.separated(
            padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 0),
            itemBuilder: (context, index) {
              final item = items[index];
              return PurchaseReceiptItemCard(item: item, index: index);
            },
          ),
        ),
        // Only show scanner if editable
        if (controller.isEditable)
          Obx(() => BarcodeInputWidget(
            onScan: (code) => controller.scanBarcode(code),
            isLoading: controller.isScanning.value,
            controller: controller.barcodeController,
            activeRoute: AppRoutes.PURCHASE_RECEIPT_FORM,
          )),
      ],
    );
  }
}