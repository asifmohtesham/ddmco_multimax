import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart';

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

  Widget _buildDetailsView(dynamic receipt) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supplier: ${receipt.supplier}'),
          Text('Posting Date: ${receipt.postingDate}'),
        ],
      ),
    );
  }

  Widget _buildItemsView(dynamic receipt) {
    final items = receipt.items as List<dynamic>? ?? [];

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(++index)}. ${item.itemCode}: ${item.itemName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(item.batchNo ?? 'N/A'),
                  ],
                ),
                const SizedBox(height: 8),
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
