import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

class DeliveryNoteFormScreen extends GetView<DeliveryNoteFormController> {
  const DeliveryNoteFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.deliveryNote.value?.name ?? 'Loading...')),
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

          final note = controller.deliveryNote.value;
          if (note == null) {
            return const Center(child: Text('Delivery note not found.'));
          }

          return TabBarView(
            children: [
              _buildDetailsView(note),
              _buildItemsView(note),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(dynamic note) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer: ${note.customer}'),
          Text('Posting Date: ${note.postingDate}'),
        ],
      ),
    );
  }

  Widget _buildItemsView(dynamic note) {
    final items = note.items as List<dynamic>? ?? [];

    if (items.isEmpty) {
      return const Center(child: Text('No items in this note.'));
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
