//
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/delivery_note_item_card.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/item_group_card.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

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
            final name = note?.name ?? 'Loading...';
            final poNo = note?.poNo;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                if (poNo != null && poNo.isNotEmpty)
                  Text(poNo, style: const TextStyle(fontSize: 16)),
              ],
            );
          }),
          actions: [
            // Save Button Logic
            Obx(() {
              // Hide if document is submitted/cancelled
              if (controller.deliveryNote.value?.docstatus != 0) return const SizedBox.shrink();

              return controller.isSaving.value
                  ? const Center(
                  child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  )
              )
                  : IconButton(
                icon: Icon(Icons.save, color: controller.isDirty.value ? Colors.white : Colors.white54),
                onPressed: controller.isDirty.value ? controller.saveDeliveryNote : null,
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
          if (controller.isLoading.value && controller.deliveryNote.value == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final note = controller.deliveryNote.value;
          if (note == null) {
            return const Center(child: Text('Delivery note not found.'));
          }

          return SafeArea(
            child: TabBarView(
              children: [
                _buildDetailsView(note),
                _buildItemsView(),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(DeliveryNote note) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. General Information Card
          _buildSectionCard(
            title: 'General Information',
            children: [
              if (note.name != 'New Delivery Note') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Delivery Note ID', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(note.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                    StatusPill(status: note.status),
                  ],
                ),
                const Divider(height: 24),
              ],
              TextFormField(
                initialValue: note.customer,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. References Card
          if (note.poNo != null && note.poNo!.isNotEmpty)
            _buildSectionCard(
              title: 'References',
              children: [
                TextFormField(
                  initialValue: note.poNo,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Purchase Order (PO)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long_outlined, color: Colors.blueGrey),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),

          if (note.poNo != null && note.poNo!.isNotEmpty) const SizedBox(height: 16),

          // 3. Schedule Card
          _buildSectionCard(
            title: 'Schedule',
            children: [
              TextFormField(
                initialValue: note.postingDate,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Posting Date',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 4. Summary Card
          _buildSectionCard(
            title: 'Summary',
            children: [
              _buildSummaryRow('Total Quantity', '${note.totalQty.toStringAsFixed(2)} Items'),
              const Divider(),
              _buildSummaryRow(
                  'Grand Total',
                  '${FormattingHelper.getCurrencySymbol(note.currency)} ${note.grandTotal.toStringAsFixed(2)}',
                  isBold: true
              ),
            ],
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

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

  Widget _buildItemsView() {
    return Column(
      children: [
        // 1. Filters (Moved to Top)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Obx(() => Row(
            children: [
              _buildFilterChip('All', controller.allCount),
              const SizedBox(width: 8),
              _buildFilterChip('Pending', controller.pendingCount),
              const SizedBox(width: 8),
              _buildFilterChip('Completed', controller.completedCount),
            ],
          )),
        ),
        const Divider(height: 1),

        // 2. Item List (Middle - Expanded)
        Expanded(
          child: Obx(() {
            if (controller.isLoading.value && controller.posUpload.value == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final currentExpandedKey = controller.expandedInvoice.value;

            final posUpload = controller.posUpload.value;
            final deliveryNoteItems = controller.deliveryNote.value?.items ?? [];

            if (posUpload == null) {
              if (deliveryNoteItems.isEmpty) {
                return const Center(child: Text('No items to display.'));
              }
              return ListView.builder(
                controller: controller.scrollController, // ADDED
                padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0, bottom: 80.0),
                itemCount: deliveryNoteItems.length,
                itemBuilder: (context, index) {
                  final item = deliveryNoteItems[index];
                  // Register Key
                  if (item.name != null && !controller.itemKeys.containsKey(item.name)) {
                    controller.itemKeys[item.name!] = GlobalKey();
                  }

                  return DeliveryNoteItemCard(item: item);
                },
              );
            }

            final posItems = posUpload.items;
            final groupedDnItems = controller.groupedItems;

            // Apply filtering logic
            final filteredItems = posItems.where((posItem) {
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
              controller: controller.scrollController,
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0, bottom: 80.0),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final posItem = filteredItems[index];
                final serialNumber = posItem.idx.toString();
                final dnItemsForThisPosItem = groupedDnItems[serialNumber] ?? [];
                final expansionKey = '${posItem.idx}';

                // Register Key
                if (!controller.itemKeys.containsKey(expansionKey)) {
                  controller.itemKeys[expansionKey] = GlobalKey();
                }

                final cumulativeQty = dnItemsForThisPosItem.fold(0.0, (sum, item) => sum + item.qty);

                return Container(
                  key: controller.itemKeys[expansionKey], // Attach Key
                  child: ItemGroupCard(
                    isExpanded: currentExpandedKey == expansionKey,
                    serialNo: posItem.idx,
                    itemName: posItem.itemName,
                    rate: posItem.rate,
                    totalQty: posItem.quantity,
                    scannedQty: cumulativeQty,
                    onToggle: () => controller.toggleInvoiceExpand(expansionKey),
                    children: dnItemsForThisPosItem.map((item) {
                      // Register Key
                      if (item.name != null && !controller.itemKeys.containsKey(item.name)) {
                        controller.itemKeys[item.name!] = GlobalKey();
                      }

                      return DeliveryNoteItemCard(item: item);
                    }).toList(),
                  ),
                );
              },
            );
          }),
        ),

        // 3. Scanner (Moved to Bottom)
        // Only show if document is editable (Draft status)
        Obx(() {
          if (controller.deliveryNote.value?.docstatus != 0) return const SizedBox.shrink();

          if (controller.isScanning.value || controller.isAddingItem.value) {
            return BarcodeInputWidget(
              onScan: (code) {}, // No-op when busy
              isLoading: controller.isScanning.value,
              isSuccess: controller.isAddingItem.value,
              controller: controller.barcodeController,
              activeRoute: AppRoutes.DELIVERY_NOTE_FORM,
            );
          }
          return BarcodeInputWidget(
            onScan: (code) => controller.scanBarcode(code), // Updated to use scanBarcode
            controller: controller.barcodeController,
            activeRoute: AppRoutes.DELIVERY_NOTE_FORM,
          );
        }),
      ],
    );
  }

  Widget _buildFilterChip(String label, int count) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: controller.itemFilter.value == label,
      onSelected: (bool selected) {
        if (selected) {
          controller.setFilter(label);
        }
      },
    );
  }
}