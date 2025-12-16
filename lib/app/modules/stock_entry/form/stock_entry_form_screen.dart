import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/item_group_card.dart';

class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

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
          appBar: AppBar(
            title: Obx(() => Text(controller.stockEntry.value?.name ?? 'Loading...')),
            actions: [
              Obx(() => controller.isSaving.value
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)),
                ),
              )
                  : IconButton(
                icon: const Icon(Icons.save),
                onPressed: (controller.isDirty.value &&
                    controller.stockEntry.value?.docstatus == 0)
                    ? controller.saveStockEntry
                    : null,
              )),
            ],
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
                _buildDetailsView(context, entry),
                _buildItemsView(context, entry),
              ],
            );
          }),
        ),
      ),
    ));
  }

  Widget _buildDetailsView(BuildContext context, StockEntry entry) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Form(
        child: Obx(() {
          final type = controller.selectedStockEntryType.value;
          final isMaterialIssue = type == 'Material Issue';
          final isMaterialReceipt = type == 'Material Receipt';
          final isMaterialTransfer = type == 'Material Transfer' ||
              type == 'Material Transfer for Manufacture';

          final showReferenceNo = isMaterialIssue;
          final showFromWarehouse = isMaterialIssue || isMaterialTransfer;
          final showToWarehouse = isMaterialReceipt || isMaterialTransfer;
          final isEditable = entry.docstatus == 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionCard(
                title: 'General Information',
                children: [
                  if (entry.name != 'New Stock Entry') ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Entry ID',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              Text(entry.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                        ),
                        StatusPill(status: entry.status),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                  // UPDATED: Searchable Stock Entry Type Field
                  GestureDetector(
                    onTap: isEditable
                        ? () => _showStockEntryTypePicker(context)
                        : null,
                    child: AbsorbPointer(
                      child: TextFormField(
                        key: ValueKey(controller.selectedStockEntryType.value),
                        initialValue: controller.selectedStockEntryType.value,
                        decoration: const InputDecoration(
                          labelText: 'Stock Entry Type',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category_outlined),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        readOnly: true,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 2. Warehouses Card
              if (showFromWarehouse || showToWarehouse)
                _buildSectionCard(
                  title: 'Logistics',
                  children: [
                    if (showFromWarehouse)
                      DropdownButtonFormField<String>(
                        value: controller.selectedFromWarehouse.value,
                        decoration: const InputDecoration(
                          labelText: 'Source Warehouse',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.outbond_outlined,
                              color: Colors.orange),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        items: controller.warehouses.map((wh) {
                          return DropdownMenuItem(
                              value: wh,
                              child: Text(wh,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)));
                        }).toList(),
                        onChanged: isEditable
                            ? (value) =>
                        controller.selectedFromWarehouse.value = value
                            : null,
                        isExpanded: true,
                      ),
                    if (showFromWarehouse && showToWarehouse)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(
                            child: Icon(Icons.arrow_downward,
                                color: Colors.grey, size: 20)),
                      ),
                    if (showToWarehouse)
                      DropdownButtonFormField<String>(
                        value: controller.selectedToWarehouse.value,
                        decoration: const InputDecoration(
                          labelText: 'Target Warehouse',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.move_to_inbox_outlined,
                              color: Colors.green),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        items: controller.warehouses.map((wh) {
                          return DropdownMenuItem(
                              value: wh,
                              child: Text(wh,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)));
                        }).toList(),
                        onChanged: isEditable
                            ? (value) =>
                        controller.selectedToWarehouse.value = value
                            : null,
                        isExpanded: true,
                      ),
                  ],
                ),

              const SizedBox(height: 16),

              // 3. Schedule & References
              _buildSectionCard(
                title: 'Schedule & Reference',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.postingDate,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: entry.postingTime,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Time',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.access_time, size: 18),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showReferenceNo) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller.customReferenceNoController,
                      readOnly: !isEditable,
                      decoration: const InputDecoration(
                        labelText: 'Reference No',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // 4. Summary
              if (entry.name != 'New Stock Entry')
                _buildSectionCard(
                  title: 'Summary',
                  children: [
                    _buildSummaryRow('Total Quantity',
                        '${entry.customTotalQty?.toStringAsFixed(2) ?? "0"}'),
                    const Divider(),
                    _buildSummaryRow(
                        'Total Amount',
                        '\$${entry.totalAmount.toStringAsFixed(2)}',
                        isBold: true),
                    if (entry.owner != null) ...[
                      const Divider(),
                      _buildSummaryRow('Created By', entry.owner!),
                    ]
                  ],
                ),

              const SizedBox(height: 80),
            ],
          );
        }),
      ),
    );
  }

  // --- NEW: Searchable Stock Entry Type Picker ---
  void _showStockEntryTypePicker(BuildContext context) {
    final searchController = TextEditingController();
    final RxList<String> filteredTypes = RxList<String>(controller.stockEntryTypes);

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Entry Type', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Types',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) {
                        filteredTypes.assignAll(controller.stockEntryTypes);
                      } else {
                        filteredTypes.assignAll(controller.stockEntryTypes.where(
                                (t) => t.toLowerCase().contains(val.toLowerCase())));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingTypes.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filteredTypes.isEmpty) {
                        return const Center(child: Text('No types found'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: filteredTypes.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final type = filteredTypes[index];
                          final isSelected = type == controller.selectedStockEntryType.value;
                          return ListTile(
                            title: Text(type, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) : null,
                            onTap: () {
                              controller.selectedStockEntryType.value = type;
                              Get.back();
                            },
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 16),
          ...children,
        ]),
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
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: isBold ? 16 : 14, color: isBold ? Colors.black87 : Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, StockEntry entry) {
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            // CHECK: Material Issue + POS Reference
            if (controller.selectedStockEntryType.value == 'Material Issue' &&
                controller.posUpload.value != null) {
              return _buildGroupedItemsList(entry);
            }

            // Standard Flat List
            if (entry.items.isEmpty) {
              return const Center(child: Text('No items in this entry.'));
            }
            return ListView.separated(
              controller: controller.scrollController, // ADDED
              padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
              itemCount: entry.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 0),
              itemBuilder: (context, index) {
                final item = entry.items[index];

                // Register & Attach Key
                if (item.name != null && !controller.itemKeys.containsKey(item.name)) {
                  controller.itemKeys[item.name!] = GlobalKey();
                }

                return StockEntryItemCard(item: item, index: index);
              },
            );
          }),
        ),
        _buildBottomScanField(context),
      ],
    );
  }

  Widget _buildGroupedItemsList(StockEntry entry) {
    final posUpload = controller.posUpload.value!;
    final groupedItems = controller.groupedItems;

    return ListView.builder(
      controller: controller.scrollController, // ADDED
      padding: const EdgeInsets.only(top: 8.0, bottom: 80.0, left: 8.0, right: 8.0),
      itemCount: posUpload.items.length,
      itemBuilder: (context, index) {
        final posItem = posUpload.items[index];
        final serialNumber = posItem.idx.toString();
        final expansionKey = '$serialNumber';

        // Get items and calculate scan qty
        final itemsInGroup = groupedItems[serialNumber] ?? [];
        final currentScannedQty = itemsInGroup.fold(0.0, (sum, item) => sum + item.qty);

        // FIX: Wrap the individual card in Obx to listen to controller.expandedInvoice
        return Obx(() {
          final isExpanded = controller.expandedInvoice.value == expansionKey;

          return ItemGroupCard(
            isExpanded: isExpanded,
            serialNo: posItem.idx,
            itemName: posItem.itemName,
            rate: posItem.rate,
            totalQty: posItem.quantity,
            scannedQty: currentScannedQty,
            onToggle: () => controller.toggleInvoiceExpand(expansionKey),
            children: itemsInGroup.map((item) {
              final globalIndex = entry.items.indexOf(item);
              // Register Key
              if (item.name != null && !controller.itemKeys.containsKey(item.name)) {
                controller.itemKeys[item.name!] = GlobalKey();
              }

              return Container(
                  key: item.name != null ? controller.itemKeys[item.name] : null, // ATTACH KEY
                  child: StockEntryItemCard(item: item, index: globalIndex)
              );
            }).toList(),
          );
        });
      },
    );
  }

  Widget _buildBottomScanField(BuildContext context) {
    if (controller.stockEntry.value?.docstatus != 0) return Container();

    return Obx(() => BarcodeInputWidget(
      onScan: (code) => controller.scanBarcode(code),
      isLoading: controller.isScanning.value,
      controller: controller.barcodeController,
      activeRoute: AppRoutes.STOCK_ENTRY_FORM,
    ));
  }
}