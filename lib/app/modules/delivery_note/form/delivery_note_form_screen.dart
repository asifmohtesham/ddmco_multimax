import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
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
    return Obx(() => PopScope(
      canPop: !controller.isDirty.value,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await controller.confirmDiscard();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: MainAppBar(
            title: controller.deliveryNote.value?.name ?? 'Loading...',
            status: controller.deliveryNote.value?.status,
            isDirty: controller.isDirty.value,
            actions: [
              Obx(() {
                if (controller.deliveryNote.value?.docstatus != 0) return const SizedBox.shrink();
                return controller.isSaving.value
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        ),
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
                  _buildDetailsView(context, note),
                  _buildItemsView(context),
                ],
              ),
            );
          }),
        ),
      ),
    ));
  }

  Widget _buildDetailsView(BuildContext context, DeliveryNote note) {
    final cs = Theme.of(context).colorScheme;
    final bool isEditable = note.docstatus == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            context: context,
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
                          Text('Delivery Note ID', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          Text(note.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                    StatusPill(status: controller.isDirty.value ? 'Not Saved' : note.status),
                  ],
                ),
                const Divider(height: 24),
              ],
              Obx(() => TextFormField(
                initialValue: note.customer,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Customer',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  filled: true,
                  fillColor: cs.surface,
                  errorText: controller.customerError.value,
                ),
              )),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'Settings',
            children: [
              Obx(() => DropdownButtonFormField<String>(
                value: controller.setWarehouse.value,
                decoration: const InputDecoration(
                  labelText: 'Set Source Warehouse',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.store),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                hint: const Text('Select Warehouse'),
                items: controller.warehouses.map((wh) {
                  return DropdownMenuItem(value: wh, child: Text(wh, overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: isEditable ? (value) => controller.setWarehouse.value = value : null,
              )),
            ],
          ),
          const SizedBox(height: 16),
          if (note.poNo != null && note.poNo!.isNotEmpty)
            _buildSectionCard(
              context: context,
              title: 'References',
              children: [
                TextFormField(
                  initialValue: note.poNo,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Purchase Order (PO)',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long_outlined, color: cs.onSurfaceVariant),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),
          if (note.poNo != null && note.poNo!.isNotEmpty) const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
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
          _buildSectionCard(
            context: context,
            title: 'Summary',
            children: [
              _buildSummaryRow(context, 'Total Quantity', '${note.totalQty.toStringAsFixed(2)} Items'),
              const Divider(),
              _buildSummaryRow(
                context,
                'Grand Total',
                '${FormattingHelper.getCurrencySymbol(note.currency)} ${note.grandTotal.toStringAsFixed(2)}',
                isBold: true,
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required BuildContext context, required String title, required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value, {bool isBold = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
              color: isBold ? cs.onSurface : cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Obx(() {
      if (controller.setWarehouse.value == null || controller.setWarehouse.value!.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store_outlined, size: 64, color: cs.outlineVariant),
              const SizedBox(height: 16),
              const Text('Warehouse Not Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Please go to Details tab and set the Source Warehouse.', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        );
      }

      return Column(
        children: [
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
                  controller: controller.scrollController,
                  padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0, bottom: 80.0),
                  itemCount: deliveryNoteItems.length,
                  itemBuilder: (context, index) {
                    final item = deliveryNoteItems[index];
                    if (item.name != null && !controller.itemKeys.containsKey(item.name)) {
                      controller.itemKeys[item.name!] = GlobalKey();
                    }
                    return DeliveryNoteItemCard(item: item);
                  },
                );
              }

              final posItems = posUpload.items;
              final groupedDnItems = controller.groupedItems;

              final filteredItems = posItems.where((posItem) {
                final serialNumber = (posUpload.items.indexOf(posItem) + 1).toString();
                final dnItemsForThisPosItem = groupedDnItems[serialNumber] ?? [];
                final cumulativeQty = dnItemsForThisPosItem.fold(0.0, (sum, item) => sum + item.qty);
                if (controller.itemFilter.value == 'Completed') return cumulativeQty >= posItem.quantity;
                else if (controller.itemFilter.value == 'Pending') return cumulativeQty < posItem.quantity;
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

                  if (!controller.itemKeys.containsKey(expansionKey)) {
                    controller.itemKeys[expansionKey] = GlobalKey();
                  }

                  final cumulativeQty = dnItemsForThisPosItem.fold(0.0, (sum, item) => sum + item.qty);

                  return Container(
                    key: controller.itemKeys[expansionKey],
                    child: ItemGroupCard(
                      isExpanded: currentExpandedKey == expansionKey,
                      serialNo: posItem.idx,
                      itemName: posItem.itemName,
                      rate: posItem.rate,
                      totalQty: posItem.quantity,
                      scannedQty: cumulativeQty,
                      onToggle: () => controller.toggleInvoiceExpand(expansionKey),
                      children: dnItemsForThisPosItem.map((item) {
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
          Obx(() {
            if (controller.deliveryNote.value?.docstatus != 0) return const SizedBox.shrink();
            if (controller.isScanning.value || controller.isAddingItem.value) {
              return BarcodeInputWidget(
                onScan: (code) {},
                isLoading: controller.isScanning.value,
                isSuccess: controller.isAddingItem.value,
                controller: controller.barcodeController,
                activeRoute: AppRoutes.DELIVERY_NOTE_FORM,
              );
            }
            return BarcodeInputWidget(
              onScan: (code) => controller.scanBarcode(code),
              controller: controller.barcodeController,
              activeRoute: AppRoutes.DELIVERY_NOTE_FORM,
            );
          }),
        ],
      );
    });
  }

  Widget _buildFilterChip(String label, int count) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: controller.itemFilter.value == label,
      onSelected: (bool selected) {
        if (selected) controller.setFilter(label);
      },
    );
  }
}
