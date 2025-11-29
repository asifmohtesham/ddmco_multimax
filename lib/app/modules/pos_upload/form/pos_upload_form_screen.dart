import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';
import 'package:intl/intl.dart';

class PosUploadFormScreen extends GetView<PosUploadFormController> {
  const PosUploadFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() => Text(controller.posUpload.value?.name ?? 'Loading...')),
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

          final upload = controller.posUpload.value;
          if (upload == null) {
            return const Center(child: Text('POS Upload not found.'));
          }

          return SafeArea(
            child: TabBarView(
              children: [
                _buildDetailsView(context, upload),
                _buildItemsView(upload),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(BuildContext context, dynamic upload) {
    // In a real app, you'd likely manage form state within the controller
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: upload.customer,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
              ),
              // This is a temporary list. In a real app, you would fetch this from the backend.
              items: [upload.customer as String]
                  .map((label) => DropdownMenuItem(
                        child: Text(label, overflow: TextOverflow.ellipsis),
                        value: label,
                      ))
                  .toList(),
              onChanged: (value) { /* Handle change */ },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: upload.date,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(upload.date) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2101),
                );
                if (pickedDate != null) {
                  // Update controller state, e.g.:
                  // controller.updateDate(DateFormat('yyyy-MM-dd').format(pickedDate));
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: upload.status,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: ['Pending', 'In Progress', 'Cancelled', 'Draft', 'Submitted']
                  .toSet() // Use a Set to ensure unique items
                  .toList()
                  .map((label) => DropdownMenuItem(child: Text(label), value: label))
                  .toList(),
              onChanged: (value) { /* Handle change */ },
            ),
            const SizedBox(height: 16),
            Text('Total Amount: ${upload.totalAmount?.toStringAsFixed(2) ?? 'N/A'}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Total Quantity: ${upload.totalQty?.toString() ?? 'N/A'}', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsView(dynamic upload) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            onChanged: controller.filterItems,
            decoration: const InputDecoration(
              labelText: 'Search Items',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            final items = controller.filteredItems;
            if (items.isEmpty) {
              return const Center(child: Text('No items found.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                // Find the original index from the full list to display correctly.
                final originalIndex = controller.posUpload.value!.items.indexOf(item);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ListTile(
                    leading: CircleAvatar(child: Text((originalIndex + 1).toString())),
                    title: Text(
                      item.itemName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Quantity: ${item.quantity}'),
                            Text('Rate: ${item.rate.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Amount: ${item.amount.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}
