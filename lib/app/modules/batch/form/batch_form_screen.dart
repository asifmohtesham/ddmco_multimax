// app/modules/batch/form/batch_form_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'dart:ui';

class BatchFormScreen extends GetView<BatchFormController> {
  const BatchFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Obx(() => PopScope(
      canPop: !controller.isDirty.value,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await controller.confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Obx(() => Text(controller.batch.value?.name ?? 'Batch Details')),
          actions: [
            // Export Button
            Obx(() {
              final batchId = controller.generatedBatchId.value;
              if (controller.isEditMode && batchId.isNotEmpty) {
                return PopupMenuButton<String>(
                  icon: controller.isExporting.value
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: colorScheme.onSurface, strokeWidth: 2))
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
                ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
              icon: Icon(Icons.save, color: controller.isDirty.value ? colorScheme.primary : Colors.grey),
              onPressed: controller.isDirty.value ? controller.saveBatch : null,
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
                  _buildSectionCard(
                    context,
                    title: 'Label Preview',
                    children: [
                      Center(child: _buildLabelPreview(context)),
                    ],
                  ),

                // --- Primary Details ---
                _buildSectionCard(
                  context,
                  title: 'General Information',
                  children: [
                    // Item Code
                    GestureDetector(
                      onTap: controller.isEditMode ? null : () => _showItemPicker(context),
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: controller.itemController,
                          decoration: const InputDecoration(
                            labelText: 'Item Code *',
                            hintText: 'Select Item',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          readOnly: true, // Always handled by picker or locked in edit
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
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),

                // --- Purchase Details ---
                _buildSectionCard(
                  context,
                  title: 'Source',
                  children: [
                    GestureDetector(
                      onTap: () => _showPOPicker(context),
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: controller.customPurchaseOrderController,
                          decoration: const InputDecoration(
                            labelText: 'Purchase Order',
                            hintText: 'Link PO',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.receipt_long_outlined),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // --- Dates & Quantity ---
                _buildSectionCard(
                  context,
                  title: 'Dates & Packaging',
                  children: [
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
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: controller.expDateController,
                            readOnly: true,
                            onTap: () => controller.pickDate(controller.expDateController),
                            decoration: const InputDecoration(
                              labelText: 'Expiry Date',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.event_busy_outlined),
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
                        prefixIcon: Icon(Icons.layers_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        }),
      ),
    ));
  }

  Widget _buildSectionCard(BuildContext context, {required String title, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildLabelPreview(BuildContext context) {
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
        width: 300,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
        ),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            // Column 1: 60% Width (Variant + EAN)
            Expanded(
              flex: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    variant,
                    style: const TextStyle(fontFamily: 'ShureTechMono', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  // Linear Barcode
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: BarcodeWidget(
                      barcode: Barcode.ean8(drawSpacers: false),
                      data: barcodeData.isNotEmpty ? barcodeData : 'UNKNOWN',
                      drawText: true,
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'ShureTechMono',
                        color: Colors.black,
                        fontFeatures: [FontFeature.slashedZero()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),

            // Column 2: 30% Width (QR + Batch ID)
            Expanded(
              flex: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: QrImageView(
                      eyeStyle: QrEyeStyle(color: Theme.of(context).colorScheme.primary, eyeShape: QrEyeShape.circle),
                      dataModuleStyle: QrDataModuleStyle(color: Theme.of(context).colorScheme.primary),
                      embeddedImageStyle: QrEmbeddedImageStyle(color: Theme.of(context).colorScheme.primary),
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      data: controller.generatedBatchId.value,
                      version: QrVersions.auto,
                      padding: EdgeInsets.all(2),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.generatedBatchId.value.replaceAll('-', '-\n'),
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'ShureTechMono',
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      fontFeatures: [FontFeature.slashedZero()],
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemPicker(BuildContext context) {
    controller.searchItems('');
    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search Item Name or Code...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (val) => controller.searchItems(val),
                  ),
                ),
                Expanded(
                  child: Obx(() {
                    if (controller.isFetchingItems.value) return const Center(child: CircularProgressIndicator());
                    return ListView.separated(
                      controller: scrollController,
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
          );
        },
      ),
      isScrollControlled: true,
    );
  }

  void _showPOPicker(BuildContext context) {
    controller.searchPurchaseOrders('');
    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search Purchase Orders...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (val) => controller.searchPurchaseOrders(val),
                  ),
                ),
                Expanded(
                  child: Obx(() {
                    if (controller.isFetchingPOs.value) return const Center(child: CircularProgressIndicator());
                    return ListView.separated(
                      controller: scrollController,
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
          );
        },
      ),
      isScrollControlled: true,
    );
  }
}