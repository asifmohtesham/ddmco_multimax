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
              _buildDetailsView(receipt),
              _buildItemsView(receipt),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(PurchaseReceipt receipt) {
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
              readOnly: true, // Usually comes from PO
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
          ],
        ),
      ),
    );
  }

  Widget _buildItemsView(PurchaseReceipt receipt) {
    final items = receipt.items;

    if (items.isEmpty) {
      return const Center(child: Text('No items in this receipt.'));
    }

    return ListView.builder(
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
}
