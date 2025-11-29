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
              _buildItemsView(entry),
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

  Widget _buildItemsView(dynamic entry) {
    final items = entry.items as List<dynamic>? ?? [];

    if (items.isEmpty) {
      return const Center(child: Text('No items in this entry.'));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.itemCode),
          subtitle: Text('Quantity: ${item.qty}'),
          trailing: Text('Rate: ${item.basicRate}'),
        );
      },
    );
  }
}
