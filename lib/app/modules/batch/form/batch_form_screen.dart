// app/modules/batch/form/batch_form_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'dart:ui'; // For font features

class BatchFormScreen extends GetView<BatchFormController> {
  const BatchFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.batch.value?.name ?? 'Batch Details')),
        actions: [
          Obx(() => controller.isSaving.value
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
              : IconButton(
            icon: const Icon(Icons.save),
            onPressed: controller.saveBatch,
          )
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Generated Batch ID & QR ---
              if (controller.generatedBatchId.value.isNotEmpty)
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                        ),
                        // Using QR Server API to render QR Code reliably without extra packages
                        child: Image.network(
                          'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${controller.generatedBatchId.value}',
                          width: 120,
                          height: 120,
                          loadingBuilder: (c, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(width: 120, height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                          },
                          errorBuilder: (c, o, s) => const SizedBox(width: 120, height: 120, child: Icon(Icons.qr_code_2, size: 60, color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        controller.generatedBatchId.value,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          // Font features to differentiate 0 and O
                          fontFeatures: [FontFeature.slashedZero()],
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),

              _buildSectionTitle('Primary Details'),
              const SizedBox(height: 12),

              // Item Code (Searchable)
              GestureDetector(
                onTap: controller.isEditMode ? null : () => _showItemPicker(context),
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: controller.itemController,
                    decoration: InputDecoration(
                      labelText: 'Item Code *',
                      hintText: 'Select Item',
                      border: const OutlineInputBorder(),
                      filled: controller.isEditMode,
                      fillColor: controller.isEditMode ? Colors.grey.shade100 : null,
                      prefixIcon: const Icon(Icons.inventory_2),
                      suffixIcon: controller.isEditMode ? null : const Icon(Icons.arrow_drop_down),
                    ),
                  ),
                ),
              ),

              // Barcode Display
              if (controller.itemBarcode.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: TextFormField(
                    key: ValueKey(controller.itemBarcode.value),
                    initialValue: controller.itemBarcode.value,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Item Barcode (EAN)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Purchase Order (Searchable)
              GestureDetector(
                onTap: () => _showPOPicker(context),
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: controller.customPurchaseOrderController,
                    decoration: const InputDecoration(
                      labelText: 'Purchase Order (Link)',
                      hintText: 'Select PO',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              TextFormField(
                controller: controller.descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('Dates & Quantity'),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller.mfgDateController,
                      readOnly: true,
                      onTap: () => controller.pickDate(controller.mfgDateController),
                      decoration: const InputDecoration(
                        labelText: 'Mfg Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: controller.expDateController,
                      readOnly: true,
                      onTap: () => controller.pickDate(controller.expDateController),
                      decoration: const InputDecoration(
                        labelText: 'Expiry Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.event_busy),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller.customPackagingQtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Packaging Qty (Custom)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.layers),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
    );
  }

  // --- Picker Bottom Sheets ---

  void _showItemPicker(BuildContext context) {
    controller.searchItems(''); // Reset/Init
    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search Item Name or Code...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => controller.searchItems(val),
              ),
            ),
            Expanded(
              child: Obx(() {
                if (controller.isFetchingItems.value) return const Center(child: CircularProgressIndicator());
                return ListView.separated(
                  itemCount: controller.itemList.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = controller.itemList[i];
                    return ListTile(
                      title: Text(item['item_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(item['item_code'] ?? ''),
                      onTap: () => controller.selectItem(item),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _showPOPicker(BuildContext context) {
    controller.searchPurchaseOrders(''); // Reset/Init
    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search Purchase Orders...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => controller.searchPurchaseOrders(val),
              ),
            ),
            Expanded(
              child: Obx(() {
                if (controller.isFetchingPOs.value) return const Center(child: CircularProgressIndicator());
                return ListView.separated(
                  itemCount: controller.poList.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final po = controller.poList[i];
                    return ListTile(
                      title: Text(po['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${po['supplier']} • ${po['transaction_date']}'),
                      onTap: () => controller.selectPurchaseOrder(po['name']),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}