import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/form/batch_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';

class BatchFormScreen extends GetView<BatchFormController> {
  const BatchFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FrappeTheme.surface,
      appBar: MainAppBar(
        title: 'Batch Details',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined, color: FrappeTheme.textBody),
            onPressed: () => controller.save(),
          ),
        ],
      ),
      body: Obx(() {
        // Show loading only if we are loading an existing doc, not for new ones
        if (controller.data.isEmpty && controller.batchId != 'New Batch') {
          return const Center(child: CircularProgressIndicator(color: FrappeTheme.primary));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(FrappeTheme.spacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header Status Card ---
              if (controller.batchId != 'New Batch') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: controller.isExpired ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(FrappeTheme.radius),
                    border: Border.all(
                      color: controller.isExpired ? Colors.red.shade200 : Colors.green.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        controller.isExpired ? Icons.event_busy : Icons.check_circle,
                        color: controller.isExpired ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.batchId,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            controller.isExpired ? "Batch Expired" : "Batch Active",
                            style: TextStyle(
                              color: controller.isExpired ? Colors.red.shade700 : Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // --- 1. Item Details ---
              _buildSection("Overview", [
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
                    label: "Batch ID",
                    fieldname: "batch_id",
                    fieldtype: "Data",
                    readOnly: true, // Auto-set by system usually
                    hidden: true,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Description",
                    fieldname: "description",
                    fieldtype: "Small Text",
                    readOnly: true, // Fetched from item
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- 2. Dates ---
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
              ]),
              const SizedBox(height: 16),

              // --- 3. Inventory Info ---
              _buildSection("Inventory", [
                Row(
                  children: [
                    Expanded(
                      child: FrappeFieldFactory(
                        config: FrappeFieldConfig(
                          label: "Quantity",
                          fieldname: "batch_qty",
                          fieldtype: "Float",
                          readOnly: true, // System calculated
                        ),
                        controller: controller,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FrappeFieldFactory(
                        config: FrappeFieldConfig(
                          label: "Stock UOM",
                          fieldname: "stock_uom",
                          fieldtype: "Data",
                          readOnly: true,
                        ),
                        controller: controller,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Reference (PO/SO)",
                    fieldname: "reference_name",
                    fieldtype: "Dynamic Link",
                    readOnly: true,
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- 4. Settings ---
              _buildSection("Settings", [
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Disabled",
                    fieldname: "disabled",
                    fieldtype: "Check",
                  ),
                  controller: controller,
                ),
              ]),

              const SizedBox(height: 40),
            ],
          ),
        );
      }),
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
}