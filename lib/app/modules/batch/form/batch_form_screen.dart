import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/widgets/frappe_form_layout.dart'; // Import Standard Layout
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';

class BatchFormScreen extends GetView<BatchFormController> {
  const BatchFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => FrappeFormLayout(
        title: 'Batch Details',
        isLoading:
            controller.data.isEmpty &&
            controller.generatedBatchId.value.isNotEmpty,
        onSave: controller.save,

        // Export Actions in AppBar
        actions: [
          if (controller.generatedBatchId.value.isNotEmpty)
            PopupMenuButton<String>(
              icon: controller.isExporting.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share, color: FrappeTheme.textBody),
              onSelected: (value) {
                if (value == 'png') controller.exportQrAsPng();
                if (value == 'pdf') controller.exportQrAsPdf();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'png',
                  child: Text('Export PNG'),
                ),
                const PopupMenuItem<String>(
                  value: 'pdf',
                  child: Text('Export PDF'),
                ),
              ],
            ),
        ],

        body: SingleChildScrollView(
          padding: const EdgeInsets.all(FrappeTheme.spacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Label Preview ---
              if (controller.generatedBatchId.value.isNotEmpty)
                _buildSection("Label Preview", [
                  Center(child: _buildLabelPreview(context)),
                ]),

              if (controller.generatedBatchId.value.isNotEmpty)
                const SizedBox(height: 16),

              // --- 1. General Section ---
              _buildSection("General", [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusPill(status: controller.batchStatus),
                    Flexible(
                      child: Transform.scale(
                        scale: 0.9,
                        child: FrappeFieldFactory(
                          config: FrappeFieldConfig(
                            label: "Disabled",
                            fieldname: "disabled",
                            fieldtype: "Check",
                          ),
                          controller: controller,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Batch ID",
                    fieldname: "name",
                    fieldtype: "Data",
                    readOnly: true,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Item Code",
                    fieldname: "item",
                    fieldtype: "Link",
                    optionsLink: "Item",
                    reqd: true,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Description",
                    fieldname: "description",
                    fieldtype: "Small Text",
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- 2. Source ---
              _buildSection("Source", [
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Purchase Order",
                    fieldname: "custom_purchase_order",
                    fieldtype: "Link",
                    optionsLink: "Purchase Order",
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- 3. Dates ---
              _buildSection("Lifecycle", [
                Row(
                  children: [
                    Expanded(
                      child: FrappeFieldFactory(
                        config: FrappeFieldConfig(
                          label: "Mfg Date",
                          fieldname: "manufacturing_date",
                          fieldtype: "Date",
                        ),
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FrappeFieldFactory(
                        config: FrappeFieldConfig(
                          label: "Expiry Date",
                          fieldname: "expiry_date",
                          fieldtype: "Date",
                        ),
                        controller: controller,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Packaging Qty",
                    fieldname: "custom_packaging_qty",
                    fieldtype: "Float",
                  ),
                  controller: controller,
                ),
              ]),

              const SizedBox(height: 80), // Padding for sticky footer
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FrappeTheme.textLabel,
              letterSpacing: 0.5,
            ),
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildLabelPreview(BuildContext context) {
    final batchId = controller.generatedBatchId.value;
    final itemCode = controller.getValue<String>('item') ?? 'Unknown Item';
    final variant = controller.itemVariantOf.value.isNotEmpty
        ? controller.itemVariantOf.value
        : itemCode;

    return AspectRatio(
      aspectRatio: 51 / 26,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              flex: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    variant,
                    style: const TextStyle(
                      fontFamily: 'ShureTechMono',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: BarcodeWidget(
                      barcode: Barcode.fromType(BarcodeType.CodeEAN8),
                      data: itemCode.isNotEmpty ? itemCode : 'UNKNOWN',
                      drawText: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: QrImageView(
                      data: batchId,
                      version: QrVersions.auto,
                      padding: const EdgeInsets.all(2),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    batchId,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'ShureTechMono',
                    ),
                    maxLines: 1,
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
}
