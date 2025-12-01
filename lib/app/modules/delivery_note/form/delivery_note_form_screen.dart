import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/form/widgets/delivery_note_item_card.dart';

class DeliveryNoteFormScreen extends GetView<DeliveryNoteFormController> {
  const DeliveryNoteFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Obx(() {
            final note = controller.deliveryNote.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note?.name ?? 'Loading...'),
                if (note?.poNo != null && note!.poNo!.isNotEmpty)
                  Text(note.poNo!, style: const TextStyle(fontSize: 14, color: Colors.white70)),
              ],
            );
          }),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Items'),
            ],
          ),
        ),
        body: Obx(() {
          if (controller.isLoading.value && controller.deliveryNote.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final note = controller.deliveryNote.value;
          if (note == null) {
            return const Center(child: Text('Delivery note not found.'));
          }

          return TabBarView(
            children: [
              _buildDetailsView(note),
              _buildItemsView(),
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
          if (note.poNo != null && note.poNo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text('PO No: ${note.poNo}', style: Theme.of(Get.context!).textTheme.titleMedium),
            ),
          Text('Customer: ${note.customer}'),
          Text('Posting Date: ${note.postingDate}'),
        ],
      ),
    );
  }

  Widget _buildItemsView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller.barcodeController,
                  decoration: const InputDecoration(
                    labelText: 'Scan or enter barcode',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      controller.addItemFromBarcode(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Obx(() => DropdownButton<String>(
                value: controller.itemFilter.value,
                items: ['All', 'Completed', 'Pending']
                    .map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) controller.setFilter(newValue);
                },
              )),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final posUpload = controller.posUpload.value;
            final deliveryNoteItems = controller.deliveryNote.value?.items ?? [];

            // If no POS Upload is linked, just show a flat list of items
            if (posUpload == null) {
              if (deliveryNoteItems.isEmpty) {
                return const Center(child: Text('No items to display.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: deliveryNoteItems.length,
                itemBuilder: (context, index) {
                  final item = deliveryNoteItems[index];
                  return DeliveryNoteItemCard(item: item);
                },
              );
            }

            final posItems = posUpload.items;
            final groupedDnItems = controller.groupedItems;

            // Apply filtering logic based on cumulative quantity
            final filteredItems = posItems.where((posItem) {
              // Match POS Item index (1-based) to the grouping key
              final serialNumber = (posUpload.items.indexOf(posItem) + 1).toString();
              
              final dnItemsForThisPosItem = groupedDnItems[serialNumber] ?? [];
              final cumulativeQty = dnItemsForThisPosItem.fold(0.0, (sum, item) => sum + item.qty);
              
              if (controller.itemFilter.value == 'Completed') {
                return cumulativeQty >= posItem.quantity;
              } else if (controller.itemFilter.value == 'Pending') {
                return cumulativeQty < posItem.quantity;
              }
              return true;
            }).toList();

            if (filteredItems.isEmpty) {
              return const Center(child: Text('No items match the filter.'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final posItem = filteredItems[index];
                
                // Re-calculate serial number to access grouped items
                final serialNumber = (posUpload.items.indexOf(posItem) + 1).toString();
                final dnItemsForThisPosItem = groupedDnItems[serialNumber] ?? [];
                
                // Use a unique key for expansion state
                final expansionKey = '${serialNumber}_$index';

                final cumulativeQty = dnItemsForThisPosItem.fold(0.0, (sum, item) => sum + item.qty);
                final isCompleted = cumulativeQty >= posItem.quantity;
                final bgColor = isCompleted ? const Color(0xFFE8F5E9) : null;

                return ExpansionTile(
                  key: PageStorageKey(expansionKey),
                  backgroundColor: bgColor,
                  collapsedBackgroundColor: bgColor,
                  title: Text(posItem.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildInfoColumn('Quantity', '${cumulativeQty.toStringAsFixed(2)} / ${posItem.quantity.toStringAsFixed(2)}', width: 120),
                        _buildInfoColumn('Rate', posItem.rate.toStringAsFixed(2)),
                        _buildInfoColumn('Scanned', dnItemsForThisPosItem.length.toString()),
                      ],
                    ),
                  ),
                  onExpansionChanged: (isExpanded) {
                    controller.toggleInvoiceExpand(expansionKey);
                  },
                  initiallyExpanded: controller.expandedInvoice.value == expansionKey,
                  children: [
                    const Divider(height: 1),
                    if (dnItemsForThisPosItem.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: Text('No items scanned for this entry yet.')),
                      )
                    else
                      // Render the nested items using the custom card widget
                      ...dnItemsForThisPosItem.map((item) => DeliveryNoteItemCard(item: item)).toList(),
                  ],
                );
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildInfoColumn(String title, String value, {double? width}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace', // Monospace font as requested
            ),
          ),
        ],
      ),
    );
  }
}
