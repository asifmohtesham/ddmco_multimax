import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/widgets/frappe_form_layout.dart';

class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isReadOnly = controller.isSubmitted;
      // Show loading only if data is empty and we aren't creating a new one
      final isLoading = controller.data.isEmpty && controller.name != 'New Stock Entry';

      return FrappeFormLayout(
        title: controller.name,
        isLoading: isLoading,
        // Disable save button if document is submitted
        onSave: isReadOnly ? null : controller.save,

        body: SingleChildScrollView(
          padding: const EdgeInsets.all(FrappeTheme.spacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              _buildSection("Overview", [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        controller.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusPill(status: controller.status),
                  ],
                ),
                const Divider(height: 24),

                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Stock Entry Type",
                    fieldname: "stock_entry_type",
                    fieldtype: "Link",
                    optionsLink: "Stock Entry Type",
                    reqd: true,
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Purpose",
                    fieldname: "purpose",
                    fieldtype: "Select",
                    options: [
                      'Material Issue',
                      'Material Receipt',
                      'Material Transfer',
                      'Material Consumption for Manufacture',
                      'Manufacture',
                      'Repack',
                      'Send to Subcontractor'
                    ],
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Posting Date",
                    fieldname: "posting_date",
                    fieldtype: "Date",
                    reqd: true,
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- Warehouses ---
              _buildSection("Movement", [
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Default Source Warehouse",
                    fieldname: "from_warehouse",
                    fieldtype: "Link",
                    optionsLink: "Warehouse",
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
                const SizedBox(height: 12),
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                    label: "Default Target Warehouse",
                    fieldname: "to_warehouse",
                    fieldtype: "Link",
                    optionsLink: "Warehouse",
                    readOnly: isReadOnly,
                  ),
                  controller: controller,
                ),
              ]),
              const SizedBox(height: 16),

              // --- Items Table ---
              _buildSection("Items", [
                FrappeFieldFactory(
                  config: FrappeFieldConfig(
                      label: "Stock Items",
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
                        FrappeFieldConfig(label: "Source Warehouse", fieldname: "s_warehouse", fieldtype: "Link", optionsLink: "Warehouse"),
                        FrappeFieldConfig(label: "Target Warehouse", fieldname: "t_warehouse", fieldtype: "Link", optionsLink: "Warehouse"),
                        FrappeFieldConfig(label: "UOM", fieldname: "uom", fieldtype: "Link", optionsLink: "UOM"),
                        FrappeFieldConfig(label: "Basic Rate", fieldname: "basic_rate", fieldtype: "Currency"),
                        FrappeFieldConfig(label: "Amount", fieldname: "amount", fieldtype: "Currency", readOnly: true),
                      ]
                  ),
                  controller: controller,
                ),
              ]),

              const SizedBox(height: 80), // Padding for sticky footer
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