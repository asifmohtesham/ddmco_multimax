import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/delivery_note_item_card.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/item_group_card.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart'; // Added
import 'package:multimax/app/data/utils/formatting_helper.dart'; // Added for currency
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart'; // Added

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
        Obx(() {
          if (controller.isScanning.value || controller.isAddingItem.value) {
            // Keep showing visual feedback if busy
            return BarcodeInputWidget(
              onScan: (code) {}, // No-op when busy
              isLoading: controller.isScanning.value,
              isSuccess: controller.isAddingItem.value,
              controller: controller.barcodeController,
            );
          }
          return BarcodeInputWidget(
            onScan: (code) => controller.addItemFromBarcode(code),
            controller: controller.barcodeController,
          );
        }),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
        const Divider(),
        Expanded(
          child: Obx(() {
            if (controller.isLoading.value && controller.posUpload.value == null) {
              return const Center(child: CircularProgressIndicator());
            }

            // Access the expandedInvoice value here to ensure Obx subscription
            final currentExpandedKey = controller.expandedInvoice.value;

            final posUpload = controller.posUpload.value;
            final deliveryNoteItems = controller.deliveryNote.value?.items ?? [];

            if (posUpload == null) {
              if (deliveryNoteItems.isEmpty) {
                return const Center(child: Text('No items to display.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 0.0, bottom: 80.0),
                itemCount: deliveryNoteItems.length,
                itemBuilder: (context, index) {
                  final item = deliveryNoteItems[index];
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
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 0.0, bottom: 80.0),
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
                    children: dnItemsForThisPosItem.map((item) => DeliveryNoteItemCard(item: item)).toList(),
                  ),
                );
              },
            );
          }),
        ),
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

class DeliveryNoteItemBottomSheet extends GetView<DeliveryNoteFormController> {
  final ScrollController? scrollController;

  const DeliveryNoteItemBottomSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Form(
          key: formKey,
          child: Obx(() {
            final isEditing = controller.editingItemName.value != null;
            // The logic: if editing, disable button if NOT dirty. If adding, disable if invalid.
            // Also always disable if saving or loading batch.
            final canSubmit = !controller.isSaving.value &&
                !controller.bsIsLoadingBatch.value &&
                controller.bsIsBatchValid.value &&
                controller.bsInvoiceSerialNo.value != null &&
                (!isEditing || controller.isFormDirty.value);

            return ListView(
              controller: scrollController, // Hook up the scroll controller
              shrinkWrap: true,
              children: [
                // Header: Owner and Created
                if (isEditing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Text(
                          '${controller.bsItemOwner.value ?? 'Unknown'} • ${controller.getRelativeTime(controller.bsItemCreation.value)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${controller.currentItemCode}: ${controller.currentItemName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Get.back(),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: controller.bsInvoiceSerialNo.value,
                  items: controller.bsAvailableInvoiceSerialNos.map((serial) {
                    return DropdownMenuItem(value: serial, child: Text('Serial #$serial'));
                  }).toList(),
                  onChanged: (value) {
                    controller.bsInvoiceSerialNo.value = value;
                    controller.checkForChanges();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Invoice Serial No',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: controller.bsBatchController,
                  readOnly: controller.bsIsBatchReadOnly.value || controller.bsIsLoadingBatch.value,
                  autofocus: !controller.bsIsBatchReadOnly.value && !isEditing,
                  decoration: InputDecoration(
                    labelText: 'Batch No',
                    border: const OutlineInputBorder(),
                    errorText: controller.bsBatchError.value,
                    suffixIcon: controller.bsIsLoadingBatch.value
                        ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                        : (controller.bsIsBatchReadOnly.value
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () => controller.validateAndFetchBatch(controller.bsBatchController.text),
                    )),
                  ),
                  onChanged: (_) => controller.checkForChanges(),
                  onFieldSubmitted: (val) {
                    if (!controller.bsIsBatchReadOnly.value && !controller.bsIsLoadingBatch.value) {
                      controller.validateAndFetchBatch(val);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (!controller.bsIsBatchValid.value) return 'Batch is not valid';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: controller.bsRackController,
                  focusNode: controller.bsRackFocusNode,
                  decoration: const InputDecoration(labelText: 'Source Rack', border: OutlineInputBorder()),
                  onChanged: (_) => controller.checkForChanges(),
                  validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: controller.bsQtyController,
                  decoration: InputDecoration(
                    labelText: 'Quantity (Max: ${controller.bsMaxQty.value})',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () => controller.adjustSheetQty(-6),
                        ),
                        Container(width: 1, height: 24, color: Colors.grey.shade400),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => controller.adjustSheetQty(6),
                        ),
                      ],
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) => controller.checkForChanges(),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    final qty = double.tryParse(value);
                    if (qty == null) return 'Invalid number';
                    if (qty <= 0) return 'Must be > 0';
                    if (qty % 6 != 0) return 'Must be a multiple of 6';
                    if (qty > controller.bsMaxQty.value && controller.bsMaxQty.value > 0) return 'Exceeds balance';
                    return null;
                  },
                ),

                if (isEditing) ...[
                  const SizedBox(height: 24),
                  const Text('Additional Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),

                  // Image Tile with Full Screen View
                  if (controller.bsItemImage.value != null && controller.bsItemImage.value!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: InkWell(
                        onTap: () {
                          final imageUrl = 'https://erp.multimax.cloud${controller.bsItemImage.value}';
                          Get.dialog(
                            Stack(
                              children: [
                                InteractiveViewer(
                                  child: Center(
                                    child: Image.network(imageUrl),
                                  ),
                                ),
                                Positioned(
                                  top: 30,
                                  right: 20,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                    onPressed: () => Get.back(),
                                  ),
                                ),
                              ],
                            ),
                            barrierColor: Colors.black.withOpacity(0.9),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Stack(
                            alignment: Alignment.topLeft,
                            children: [
                              Image.network(
                                'https://erp.multimax.cloud${controller.bsItemImage.value}',
                                // height: MediaQuery.of(context).size.height * 0.5,
                                width: MediaQuery.of(context).size.width * 0.5,
                                fit: BoxFit.scaleDown,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  // height: MediaQuery.of(context).size.height * 0.5,
                                  width: MediaQuery.of(context).size.width * 0.5,
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: const Text('Image load failed', style: TextStyle(color: Colors.grey)),
                                ),
                              ),
                              Container(
                                color: Colors.black26,
                                child: const Icon(Icons.zoom_in, color: Colors.white, size: 40),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Compact Grid for Details
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _buildCompactDetailItem('Item Group', controller.bsItemGroup.value),
                      _buildCompactDetailItem('Variant Of', controller.bsItemCustomVariantOf.value),
                      _buildCompactDetailItem('Stock', controller.bsItemCompanyTotalStock.value?.toStringAsFixed(2)),
                      _buildCompactDetailItem('Packed Qty', controller.bsItemPackedQty.value?.toStringAsFixed(2)),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  // Footer: Modified info
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Last modified by ${controller.bsItemModifiedBy.value ?? 'Unknown'} • ${controller.getRelativeTime(controller.bsItemModified.value)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canSubmit ? () {
                      if (formKey.currentState!.validate()) {
                        controller.submitSheet();
                      }
                    } : null,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                    ),
                    child: controller.isSaving.value
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(isEditing ? 'Update Item' : 'Add Item'),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCompactDetailItem(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: 150, // Fixed width for column-like look
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}