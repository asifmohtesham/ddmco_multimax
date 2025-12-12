// app/modules/batch/form/batch_form_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart'; // Add this to pubspec.yaml
import 'dart:ui';

class BatchFormScreen extends GetView<BatchFormController> {
  const BatchFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.batch.value?.name ?? 'Batch Details')),
        actions: [
          // Export Button
          Obx(() {
            if (controller.isEditMode && controller.generatedBatchId.value.isNotEmpty) {
              return PopupMenuButton<String>(
                icon: controller.isExporting.value
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.share),
                onSelected: (value) {
                  if (value == 'png') controller.exportQrAsPng();
                  if (value == 'pdf') controller.exportQrAsPdf();
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'png',
                    child: ListTile(
                      leading: Icon(Icons.image, color: Colors.blue),
                      title: Text('Export PNG'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'pdf',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf, color: Colors.red),
                      title: Text('Export PDF (Vector)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          }),

          Obx(() => controller.isSaving.value
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
              : IconButton(
            icon: const Icon(Icons.save),
            onPressed: controller.isDirty.value ? controller.saveBatch : null,
            color: controller.isDirty.value ? Colors.white : Colors.white38,
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
              // --- Label Preview Section ---
              if (controller.generatedBatchId.value.isNotEmpty)
                Center(
                  child: Column(
                    children: [
                      const Text('Label Preview', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      _buildLabelPreview(context),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),

              _buildSectionTitle('Primary Details'),
              const SizedBox(height: 12),

              // Item Code
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

              const SizedBox(height: 16),

              // Purchase Order
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

  Widget _buildLabelPreview(BuildContext context) {
    // Logic to mimic PDF generation
    final String variant = controller.itemVariantOf.value.isNotEmpty
        ? controller.itemVariantOf.value
        : controller.itemController.text;

    final String barcodeData = controller.itemBarcode.value.isNotEmpty
        ? controller.itemBarcode.value
        : controller.itemController.text;

    // Aspect Ratio 51mm / 26mm ~= 1.96
    return AspectRatio(
      aspectRatio: 51 / 26,
      child: Container(
        width: 300, // Fixed visual width, height auto by aspect ratio
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
        ),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            // Column 1: 65% Width (Variant + EAN)
            Expanded(
              flex: 65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    variant,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
                  const Spacer(),
                  // EAN Barcode
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: BarcodeWidget(
                      barcode: Barcode.ean8(drawSpacers: false),
                      data: barcodeData.isNotEmpty ? barcodeData : 'UNKNOWN',
                      drawText: true,
                      style: const TextStyle(
                        fontSize: 24,
                        fontFamily: 'monospace',
                        fontFeatures: [FontFeature.slashedZero(),],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Column 2: 35% Width (QR + Batch ID)
            Expanded(
              flex: 35,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: QrImageView(
                      data: controller.generatedBatchId.value,
                      version: QrVersions.auto,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.generatedBatchId.value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.slashedZero()],
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    controller.searchItems('');
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
    controller.searchPurchaseOrders('');
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