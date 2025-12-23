import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
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
          appBar: MainAppBar(
            title: controller.stockEntry.value?.name ?? 'Loading...',
            status: controller.stockEntry.value?.status,
            actions: [
              Obx(() => controller.isSaving.value
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                  ),
                ),
              )
                  : IconButton(
                icon: const Icon(Icons.save),
                onPressed: (controller.isDirty.value &&
                    controller.stockEntry.value?.docstatus == 0 &&
                    (controller.stockEntry.value?.items.isNotEmpty ?? false))
                    ? controller.saveStockEntry
                    : null,
              )),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Logistics & Details'),
                Tab(text: 'Items (Scan)'),
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
      padding: const EdgeInsets.all(16.0),
      child: Form(
        child: Obx(() {
          final type = controller.selectedStockEntryType.value;
          final isMaterialIssue = type == 'Material Issue';
          final isMaterialReceipt = type == 'Material Receipt';
          final isMaterialTransfer = type == 'Material Transfer' || type == 'Material Transfer for Manufacture';
          final isEditable = entry.docstatus == 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (type != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.deepOrange.shade50, Colors.lightGreen.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: isEditable ? () => _showStockEntryTypePicker(context) : null,
                        child: Row(
                          children: [
                            Icon(Icons.category, size: 20, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(type, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 16)),
                            const Spacer(),
                            if(isEditable) const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: (isEditable && (isMaterialIssue || isMaterialTransfer)) ? () => _showWarehousePicker(context, true) : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('FROM', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    controller.selectedFromWarehouse.value ?? (isMaterialReceipt ? 'N/A' : 'Select Source'),
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: (isMaterialIssue || isMaterialTransfer) ? Colors.black87 : Colors.grey
                                    ),
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                  )
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.arrow_forward_rounded, color: Colors.blue.shade300),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: (isEditable && (isMaterialReceipt || isMaterialTransfer)) ? () => _showWarehousePicker(context, false) : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('TO', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    controller.selectedToWarehouse.value ?? (isMaterialIssue ? 'N/A' : 'Select Target'),
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: (isMaterialReceipt || isMaterialTransfer) ? Colors.black87 : Colors.grey
                                    ),
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),

              const Text("Reference & Schedule", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCompactField(label: 'Date', value: entry.postingDate, icon: Icons.calendar_today),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCompactField(label: 'Time', value: entry.postingTime, icon: Icons.access_time),
                  ),
                ],
              ),
              if (isMaterialIssue) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller.customReferenceNoController,
                  readOnly: !isEditable,
                  decoration: InputDecoration(
                    labelText: 'Reference / Work Order',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    _buildSummaryRow('Total Quantity', '${entry.customTotalQty?.toStringAsFixed(2) ?? "0"}'),
                    const Divider(),
                    _buildSummaryRow('Total Amount', '\$${entry.totalAmount.toStringAsFixed(2)}', isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, StockEntry entry) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              // REMOVED Obx() here. 'entry' is a plain object passed from parent Obx.
              // 'controller.entrySource' is not an Rx variable in the provided controller logic (it's a plain Enum property set at init).
              child: Builder(builder: (context) {
                // 1. Handle Empty State
                if (entry.items.isEmpty && controller.entrySource != StockEntrySource.posUpload) {
                  return _buildEmptyState();
                }

                // 2. Dispatch Layout based on Entry Source
                switch (controller.entrySource) {
                  case StockEntrySource.posUpload:
                  // Wrap POS View in Obx because it listens to controller.posUpload Rx
                    return Obx(() => _buildPosUploadItemsView(entry));
                  case StockEntrySource.materialRequest:
                    return _buildMaterialRequestItemsView(entry);
                  case StockEntrySource.manual:
                  default:
                    return _buildStandardItemsView(entry);
                }
              }),
            ),
          ],
        ),

        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _buildBottomScanField(context),
        ),
      ],
    );
  }

  Widget _buildStandardItemsView(StockEntry entry) {
    return ListView.separated(
      controller: controller.scrollController,
      padding: const EdgeInsets.only(top: 8.0, bottom: 100.0),
      itemCount: entry.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (context, index) {
        final item = entry.items[index];
        _ensureItemKey(item);

        return StockEntryItemCard(
          item: item,
          onTap: controller.stockEntry.value?.docstatus == 0 ? () => controller.editItem(item) : null,
          onDelete: controller.stockEntry.value?.docstatus == 0 ? () => controller.deleteItem(item.name!) : null,
        );
      },
    );
  }

  Widget _buildMaterialRequestItemsView(StockEntry entry) {
    return ListView.separated(
      controller: controller.scrollController,
      padding: const EdgeInsets.only(top: 8.0, bottom: 100.0),
      itemCount: entry.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 0),
      itemBuilder: (context, index) {
        final item = entry.items[index];
        _ensureItemKey(item);

        double? maxQty;
        final refItem = controller.mrReferenceItems.firstWhereOrNull(
                (r) => r['item_code'] == item.itemCode
        );
        if (refItem != null) {
          maxQty = (refItem['qty'] as num).toDouble();
        }

        return StockEntryItemCard(
          item: item,
          maxQty: maxQty,
          onTap: controller.stockEntry.value?.docstatus == 0 ? () => controller.editItem(item) : null,
          onDelete: controller.stockEntry.value?.docstatus == 0 ? () => controller.deleteItem(item.name!) : null,
        );
      },
    );
  }

  Widget _buildPosUploadItemsView(StockEntry entry) {
    if (controller.posUpload.value == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final posUpload = controller.posUpload.value!;
    final groupedItems = controller.groupedItems;

    return ListView.builder(
      controller: controller.scrollController,
      padding: const EdgeInsets.only(top: 8.0, bottom: 100.0, left: 8.0, right: 8.0),
      itemCount: posUpload.items.length,
      itemBuilder: (context, index) {
        final posItem = posUpload.items[index];
        final serialNumber = posItem.idx.toString();
        final expansionKey = '$serialNumber';

        final itemsInGroup = groupedItems[serialNumber] ?? [];
        final currentScannedQty = itemsInGroup.fold(0.0, (sum, item) => sum + item.qty);

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
              _ensureItemKey(item);
              return Container(
                  key: item.name != null ? controller.itemKeys[item.name] : null,
                  child: StockEntryItemCard(
                    item: item,
                    onTap: controller.stockEntry.value?.docstatus == 0 ? () => controller.editItem(item) : null,
                    onDelete: controller.stockEntry.value?.docstatus == 0 ? () => controller.deleteItem(item.name!) : null,
                  )
              );
            }).toList(),
          );
        });
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Ready to Scan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          const Text('Scan items, batches or racks to start.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBottomScanField(BuildContext context) {
    if (controller.stockEntry.value?.docstatus != 0) return Container();

    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4))]
      ),
      padding: const EdgeInsets.only(bottom: 0),
      child: Obx(() => BarcodeInputWidget(
        onScan: (code) => controller.scanBarcode(code),
        isLoading: controller.isScanning.value,
        controller: controller.barcodeController,
        activeRoute: AppRoutes.STOCK_ENTRY_FORM,
        hintText: 'Scan Item / Batch ...',
      )),
    );
  }

  Widget _buildCompactField({required String label, required String? value, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(value ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          )
        ],
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

  void _showWarehousePicker(BuildContext context, bool isSource) {
    if (controller.warehouses.isEmpty && !controller.isFetchingWarehouses.value) {
      controller.fetchWarehouses();
    }

    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(
          children: [
            Text(isSource ? 'Select Source Warehouse' : 'Select Target Warehouse', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() {
                if (controller.isFetchingWarehouses.value) return const Center(child: CircularProgressIndicator());
                return ListView.separated(
                  itemCount: controller.warehouses.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final wh = controller.warehouses[i];
                    return ListTile(
                      title: Text(wh),
                      onTap: () {
                        if(isSource) controller.selectedFromWarehouse.value = wh;
                        else controller.selectedToWarehouse.value = wh;
                        Get.back();
                      },
                    );
                  },
                );
              }),
            )
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

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

  void _ensureItemKey(StockEntryItem item) {
    if (item.name != null && !controller.itemKeys.containsKey(item.name)) {
      controller.itemKeys[item.name!] = GlobalKey();
    }
  }
}