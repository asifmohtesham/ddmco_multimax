import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

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
                _buildItemsView(context, upload),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDetailsView(BuildContext context, dynamic upload) {
    final totalAmountController = TextEditingController(text: upload.totalAmount?.toString() ?? '0.0');
    final totalQtyController = TextEditingController(text: upload.totalQty?.toString() ?? '0');

    return Obx(() {
      // Use exact field names from DocType for permission checks
      final bool canEditStatus = controller.canEdit('status');
      final bool canEditAmount = controller.canEdit('total_amount');
      final bool canEditQty = controller.canEdit('total_qty');

      // Determine if any save action is possible
      final bool canSave = canEditStatus || canEditAmount || canEditQty;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReadOnlyField('Name', upload.name),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: upload.customer,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  border: OutlineInputBorder(),
                ),
                items: [upload.customer as String]
                    .map((label) => DropdownMenuItem(
                  child: Text(label, overflow: TextOverflow.ellipsis),
                  value: label,
                ))
                    .toList(),
                onChanged: null,
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
              ),
              const SizedBox(height: 16),

              // Status
              DropdownButtonFormField<String>(
                value: upload.status,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: const OutlineInputBorder(),
                  filled: !canEditStatus,
                  fillColor: !canEditStatus ? Colors.grey.shade100 : null,
                ),
                items: ['Pending', 'In Progress', 'Cancelled', 'Draft', 'Submitted']
                    .map((label) => DropdownMenuItem(child: Text(label), value: label))
                    .toList(),
                onChanged: canEditStatus ? (value) { /* Controller logic if needed */ } : null,
              ),
              const SizedBox(height: 16),

              // Total Amount
              TextFormField(
                controller: totalAmountController,
                readOnly: !canEditAmount,
                decoration: InputDecoration(
                  labelText: 'Total Amount',
                  border: const OutlineInputBorder(),
                  filled: !canEditAmount,
                  fillColor: !canEditAmount ? Colors.grey.shade100 : null,
                  suffixIcon: !canEditAmount ? const Icon(Icons.lock, size: 16, color: Colors.grey) : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),

              // Total Quantity
              TextFormField(
                controller: totalQtyController,
                readOnly: !canEditQty,
                decoration: InputDecoration(
                  labelText: 'Total Quantity',
                  border: const OutlineInputBorder(),
                  filled: !canEditQty,
                  fillColor: !canEditQty ? Colors.grey.shade100 : null,
                  suffixIcon: !canEditQty ? const Icon(Icons.lock, size: 16, color: Colors.grey) : null,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),

              if (canSave)
                SizedBox(
                  width: double.infinity,
                  child: Obx(() => ElevatedButton(
                    onPressed: controller.isSaving.value ? null : () {
                      final updatedData = <String, dynamic>{};

                      // Dynamically add only editable fields
                      if (canEditAmount) {
                        updatedData['total_amount'] = double.tryParse(totalAmountController.text) ?? 0.0;
                      }
                      if (canEditQty) {
                        updatedData['total_qty'] = double.tryParse(totalQtyController.text) ?? 0.0;
                      }
                      // Handle status update if needed

                      if (updatedData.isNotEmpty) {
                        controller.updatePosUpload(updatedData);
                      }
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: controller.isSaving.value
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Update', style: TextStyle(fontSize: 16)),
                  )),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildReadOnlyField(String label, String value) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
    );
  }

  Widget _buildItemsView(BuildContext context, dynamic upload) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
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
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final originalIndex = controller.posUpload.value!.items.indexOf(item);
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.grey.shade200,
                              child: Text('${originalIndex + 1}', style: const TextStyle(fontSize: 10, color: Colors.black)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.itemName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildItemStat('Qty', item.quantity.toString()),
                            _buildItemStat('Rate', item.rate.toStringAsFixed(2)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Amount: ${item.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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

  Widget _buildItemStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}