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
            // Ensure we handle potential nulls gracefully and trigger updates
            final name = note?.name ?? 'Loading...';
            final poNo = note?.poNo;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                if (poNo != null && poNo.isNotEmpty)
                  Text(poNo),
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

  Widget _buildDetailsView(dynamic note) {
    // Re-applying the monospace style as requested previously
    const valueStyle = TextStyle(fontSize: 16, fontFamily: 'monospace');
    const labelStyle = TextStyle(fontSize: 14, color: Colors.grey);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.poNo != null && note.poNo.isNotEmpty) ...[
            Text('PO No:', style: labelStyle),
            Text(note.poNo!, style: valueStyle),
            const SizedBox(height: 12),
          ],
          Text('Customer:', style: labelStyle),
          Text(note.customer, style: valueStyle),
          const SizedBox(height: 12),
          Text('Posting Date:', style: labelStyle),
          Text(note.postingDate, style: valueStyle),
        ],
      ),
    );
  }

  Widget _buildItemsView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Obx(() {
            String labelText = 'Scan or enter barcode';
            Widget? suffixIcon;

            if (controller.isScanning.value) {
              labelText = 'Scanning...';
              suffixIcon = const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              );
            } else if (controller.isAddingItem.value) {
              labelText = 'Item Validated';
              suffixIcon = const Icon(Icons.check_circle, color: Colors.green);
            } else {
              suffixIcon = IconButton(
                icon: const Icon(Icons.camera_alt),
                onPressed: () {
                  final text = controller.barcodeController.text;
                  if (text.isNotEmpty) controller.addItemFromBarcode(text);
                },
              );
            }

            return TextFormField(
              controller: controller.barcodeController,
              autofocus: true,
              readOnly: controller.isScanning.value || controller.isAddingItem.value,
              decoration: InputDecoration(
                labelText: labelText,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: suffixIcon,
              ),
              onFieldSubmitted: (value) {
                if (value.isNotEmpty && !controller.isScanning.value && !controller.isAddingItem.value) {
                  controller.addItemFromBarcode(value);
                }
              },
            );
          }),
        ),
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
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 0.0, bottom: 80.0),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final posItem = filteredItems[index];
                final serialNumber = (posUpload.items.indexOf(posItem) + 1).toString();
                final dnItemsForThisPosItem = groupedDnItems[serialNumber] ?? [];
                final expansionKey = '${serialNumber}_$index';

                final cumulativeQty = dnItemsForThisPosItem.fold(0.0, (sum, item) => sum + item.qty);
                final isCompleted = cumulativeQty >= posItem.quantity;
                final bgColor = isCompleted ? const Color(0xFFE8F5E9) : null;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: ExpansionTile(
                    key: PageStorageKey(expansionKey),
                    backgroundColor: Colors.transparent,
                    collapsedBackgroundColor: Colors.transparent,
                    shape: const Border(),
                    title: Text('${posItem.idx}. ${posItem.itemName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                        ...dnItemsForThisPosItem.map((item) => DeliveryNoteItemCard(item: item)).toList(),
                    ],
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
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class AddItemBottomSheet extends GetView<DeliveryNoteFormController> {
  const AddItemBottomSheet({super.key});

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
          child: Obx(() => ListView(
            shrinkWrap: true,
            children: [
              Text('${controller.currentItemCode}: ${controller.currentItemName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<String>(
                value: controller.bsInvoiceSerialNo.value,
                items: controller.bsAvailableInvoiceSerialNos.map((serial) {
                  return DropdownMenuItem(value: serial, child: Text('Serial #$serial'));
                }).toList(),
                onChanged: (value) {
                  controller.bsInvoiceSerialNo.value = value;
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
                autofocus: !controller.bsIsBatchReadOnly.value,
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (controller.bsIsBatchValid.value && controller.bsInvoiceSerialNo.value != null && !controller.bsIsLoadingBatch.value) ? () {
                    if (formKey.currentState!.validate()) {
                      controller.submitSheet();
                    }
                  } : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                  child: const Text('Add Item'),
                ),
              ),
            ],
          )),
        ),
      ),
    );
  }
}
