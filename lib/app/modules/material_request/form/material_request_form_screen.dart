import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/widgets/frappe_form_layout.dart'; // Import Standard Layout

class MaterialRequestFormScreen extends GetView<MaterialRequestFormController> {
  const MaterialRequestFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isReadOnly = controller.docstatus > 0;
      final isNew = controller.data.isEmpty && controller.name == 'New Request';

      return FrappeFormLayout(
        title: controller.name,
        // Show loader only if we are loading existing data and it's empty
        isLoading: controller.data.isEmpty && !isNew,
        // Hide Save button if document is submitted (Read Only)
        onSave: isReadOnly ? null : controller.save,

        body: SingleChildScrollView(
          padding: const EdgeInsets.all(FrappeTheme.spacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. Header & Details ---
              _buildSection("Details", [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        controller.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusPill(status: controller.status),
                  ],
                ),
                const Divider(height: 24),

                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Type",
                    fieldname: "material_request_type",
                    fieldtype: "Select",
                    options: [
                      'Purchase',
                      'Material Transfer',
                      'Material Issue',
                      'Manufacture',
                      'Customer Provided',
                    ],
                    reqd: true,
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Required By",
                    fieldname: "schedule_date",
                    fieldtype: "Date",
                    reqd: true,
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Target Warehouse",
                    fieldname: "set_warehouse",
                    fieldtype: "Link",
                    optionsLink: "Warehouse",
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- 2. ITEMS TABLE ---
              _buildSection("Items", [
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Requested Items",
                    fieldname: "items",
                    fieldtype: "Table",
                    readOnly: isReadOnly,
                    childFields: [
                      // List View Columns
                      FrappeFieldConfig(
                        label: "Item Code",
                        fieldname: "item_code",
                        fieldtype: "Link",
                        optionsLink: "Item",
                        reqd: true,
                        inListView: true,
                      ),
                      FrappeFieldConfig(
                        label: "Qty",
                        fieldname: "qty",
                        fieldtype: "Float",
                        reqd: true,
                        inListView: true,
                      ),

                      // Detail View Columns
                      FrappeFieldConfig(
                        label: "Required By",
                        fieldname: "schedule_date",
                        fieldtype: "Date",
                      ),
                      FrappeFieldConfig(
                        label: "Warehouse",
                        fieldname: "warehouse",
                        fieldtype: "Link",
                        optionsLink: "Warehouse",
                      ),
                      FrappeFieldConfig(
                        label: "UOM",
                        fieldname: "uom",
                        fieldtype: "Link",
                        optionsLink: "UOM",
                      ),
                      FrappeFieldConfig(
                        label: "Description",
                        fieldname: "description",
                        fieldtype: "Small Text",
                      ),
                    ],
                  ),
                  controller: controller,
                ),
              ]),

              const SizedBox(height: 80), // Bottom padding for sticky button
            ],
          ),
        ),
      );
    });
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
