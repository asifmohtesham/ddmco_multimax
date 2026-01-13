import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/widgets/stock_balance_chart.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/widgets/frappe_field_factory.dart'; // The GENERIC Factory
import 'package:multimax/models/frappe_field_config.dart'; // The GENERIC Config
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: FrappeTheme.surface,
        appBar: MainAppBar(
          title: 'Item Details',
          showBack: true,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.save_outlined,
                color: FrappeTheme.textBody,
              ),
              onPressed: () => controller.save(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: FrappeTheme.primary,
            labelColor: FrappeTheme.primary,
            unselectedLabelColor: FrappeTheme.textLabel,
            tabs: [
              Tab(text: "Overview"),
              Tab(text: "Stock"),
              Tab(text: "Attributes"),
            ],
          ),
        ),
        body: Obx(() {
          // Check the generic 'data' map instead of 'item.value'
          if (controller.data.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: FrappeTheme.primary),
            );
          }

          return TabBarView(
            children: [
              _buildOverviewTab(),
              _buildStockTab(),
              _buildAttributesTab(),
            ],
          );
        }),
      ),
    );
  }

  // --- TAB 1: OVERVIEW (Using Generic Widgets) ---
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(FrappeTheme.spacing),
      child: Column(
        children: [
          // Header Image Card
          _buildHeaderCard(),
          const SizedBox(height: 16),

          // 1. General Section
          _buildSection("General", [
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Item Name",
                fieldname: "item_name",
                fieldtype: "Data",
                readOnly: true,
              ),
              controller: controller, // PASSING IT HERE
            ),
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Item Group",
                fieldname: "item_group",
                fieldtype: "Link",
                optionsLink: "Item Group",
                readOnly: true,
              ),
              controller: controller,
            ),
          ]),

          const SizedBox(height: 16),

          // 2. Inventory Section (Fixes your missing field error!)
          _buildSection("Inventory", [
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Default UOM",
                fieldname: "stock_uom",
                fieldtype: "Link",
                optionsLink: "UOM",
                readOnly: true,
              ),
              controller: controller,
            ),
            // We safely access 'valuation_method' here via the generic controller logic
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Valuation Method",
                fieldname: "valuation_method",
                fieldtype: "Select",
                readOnly: true,
              ),
              controller: controller,
            ),
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Opening Stock",
                fieldname: "opening_stock",
                fieldtype: "Float",
                readOnly: true,
              ),
              controller: controller,
            ),
          ]),

          const SizedBox(height: 16),

          // 3. Description
          _buildSection("Info", [
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Description",
                fieldname: "description",
                fieldtype: "Text",
                readOnly: true,
              ),
              controller: controller,
            ),
          ]),
        ],
      ),
    );
  }

  // --- TAB 2: STOCK (Custom Chart + Generic Data) ---
  Widget _buildStockTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(FrappeTheme.spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "WAREHOUSE LEVELS",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: FrappeTheme.textLabel,
            ),
          ),
          const SizedBox(height: 12),

          // Use the specific observable for the chart
          Obx(() {
            if (controller.isLoadingStock.value)
              return const LinearProgressIndicator();
            return StockBalanceChart(stockLevels: controller.stockLevels);
          }),

          const SizedBox(height: 24),
          const Text(
            "SETTINGS",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: FrappeTheme.textLabel,
            ),
          ),
          const SizedBox(height: 12),

          // Generic fields for stock settings
          _buildSection("Configuration", [
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Has Batch No",
                fieldname: "has_batch_no",
                fieldtype: "Check",
                readOnly: true,
              ),
              controller: controller,
            ),
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Has Serial No",
                fieldname: "has_serial_no",
                fieldtype: "Check",
                readOnly: true,
              ),
              controller: controller,
            ),
            FrappeFieldFactory(
              config: FrappeFieldConfig(
                label: "Shelf Life (Days)",
                fieldname: "shelf_life_in_days",
                fieldtype: "Int",
                readOnly: true,
              ),
              controller: controller,
            ),
          ]),
        ],
      ),
    );
  }

  // --- TAB 3: ATTRIBUTES (Child Table) ---
  Widget _buildAttributesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(FrappeTheme.spacing),
      child: FrappeFieldFactory(
        config: FrappeFieldConfig(
          label: "Item Attributes",
          fieldname: "attributes", // Matches the child table key in Frappe
          fieldtype: "Table",
          childFields: [
            FrappeFieldConfig(
              label: "Attribute",
              fieldname: "attribute",
              fieldtype: "Data",
              inListView: true,
            ),
            FrappeFieldConfig(
              label: "Value",
              fieldname: "attribute_value",
              fieldtype: "Data",
              inListView: true,
            ),
          ],
        ),
        controller: controller, // PASSING IT HERE
      ),
    );
  }

  // --- Helpers ---

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

  Widget _buildHeaderCard() {
    final String? imgUrl = controller.image;
    final String baseUrl = Get.find<ApiProvider>().baseUrl;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: FrappeTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
              image: (imgUrl != null && imgUrl.isNotEmpty)
                  ? DecorationImage(
                      image: NetworkImage('$baseUrl$imgUrl'),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: (imgUrl == null || imgUrl.isEmpty)
                ? const Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.itemName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: FrappeTheme.textBody,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.itemCode,
                  style: const TextStyle(
                    fontSize: 13,
                    color: FrappeTheme.textLabel,
                    fontFamily: 'ShureTechMono',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
