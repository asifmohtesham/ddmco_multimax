import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.itemCode),
          subtitle: Text('Quantity: ${item.qty}'),
          trailing: Text('Rate: ${item.rate}'),
        );
      },
    );
  }
}
