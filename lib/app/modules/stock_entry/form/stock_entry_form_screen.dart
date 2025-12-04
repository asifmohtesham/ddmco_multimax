import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.stockEntry.value?.name ?? 'Loading...')),
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
              _buildDetailsView(entry),
              _buildItemsView(context, entry),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(dynamic entry) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Purpose: ${entry.purpose}'),
          Text('Posting Date: ${entry.postingDate}'),
        ],
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, dynamic entry) {
    final items = entry.items as List<dynamic>? ?? [];

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items in this entry.'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item.itemCode),
                      subtitle: Text('Quantity: ${item.qty}'),
                      trailing: Text('Rate: ${item.basicRate}'),
                    );
                  },
                ),
        ),
        _buildBottomScanField(context),
      ],
    );
  }

  Widget _buildBottomScanField(BuildContext context) {
    // Only show if editable? Assuming yes for now.
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

class StockEntryItemQtySheet extends GetView<StockEntryFormController> {
  const StockEntryItemQtySheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add Item', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('${controller.currentItemCode}: ${controller.currentItemName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: controller.bsQtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.addItem,
                child: const Text('Add Item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
