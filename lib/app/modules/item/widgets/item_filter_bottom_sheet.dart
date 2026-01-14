import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';
import 'package:multimax/controllers/frappe_filter_sheet_controller.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/models/frappe_filter.dart';

class ItemFilterBottomSheet extends GetView<FrappeFilterSheetController> {
  const ItemFilterBottomSheet({super.key});

  // Access the Item Data controller for dropdown lists
  ItemController get itemController => Get.find<ItemController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Items',
      activeFilterCount: controller.localFilters.length + (controller.showImagesOnly.value ? 1 : 0),

      // Sorting (delegated to parent ItemController)
      sortOptions: const [
        SortOption('Modified', 'modified'),
        SortOption('Status', 'docstatus'),
        SortOption('Item Code', 'item_code'),
      ],
      currentSortField: controller.listController.sortField.value,
      currentSortOrder: controller.listController.sortOrder.value,
      onSortChanged: controller.listController.setSort,

      onApply: controller.apply,
      onClear: controller.clear,

      filterWidgets: [
        // --- 1. Filter Rows ---
        ...controller.localFilters.asMap().entries.map((entry) {
          return _buildFilterRow(context, entry.key, entry.value);
        }),

        const SizedBox(height: 12),

        // --- 2. Add Button ---
        OutlinedButton.icon(
          onPressed: controller.addFilterRow,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Filter Condition'),
          style: OutlinedButton.styleFrom(
            foregroundColor: FrappeTheme.primary,
            side: const BorderSide(color: FrappeTheme.primary),
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FrappeTheme.radius)),
          ),
        ),

        const SizedBox(height: 16),
        const Divider(),

        // --- 3. Extra Options (Images) ---
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text("Show Images Only", style: TextStyle(fontWeight: FontWeight.w600)),
          value: controller.showImagesOnly.value,
          activeColor: FrappeTheme.primary,
          onChanged: controller.toggleImagesOnly,
        )
      ],
    ));
  }

  Widget _buildFilterRow(BuildContext context, int index, FrappeFilter filter) {
    final isAttribute = filter.config.fieldtype == 'Attribute';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Row Header: Field Select + Close
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _showSelectionSheet(
                  context: context,
                  title: "Select Field",
                  items: controller.listController.filterableFields.map((e) => e.label).toList(),
                  onSelected: (label) => controller.updateFilterField(index, label),
                ),
                child: Row(
                  children: [
                    Text(filter.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: FrappeTheme.primary)),
                    const Icon(Icons.arrow_drop_down, color: FrappeTheme.primary),
                  ],
                ),
              ),
              InkWell(
                onTap: () => controller.removeFilterRow(index),
                child: const Icon(Icons.close, color: Colors.grey, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row Content: Value Inputs
          if (isAttribute)
            _buildAttributeInputs(context, index, filter)
          else
            _buildStandardInputs(context, index, filter),
        ],
      ),
    );
  }

  Widget _buildAttributeInputs(BuildContext context, int index, FrappeFilter filter) {
    return Row(
      children: [
        // 1. Attribute Name
        Expanded(
          child: InkWell(
            onTap: () => _showSelectionSheet(
              context: context,
              title: "Select Attribute",
              items: itemController.itemAttributes,
              isLoading: itemController.isLoadingAttributes.value,
              onSelected: (val) {
                controller.updateExtra(index, 'attributeName', val);
                controller.updateValue(index, ''); // Reset value
                itemController.fetchAttributeValues(val); // Trigger fetch
              },
            ),
            child: InputDecorator(
              decoration: FrappeTheme.inputDecoration('Attribute'),
              child: Text(
                filter.extras['attributeName'] ?? 'Select...',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 2. Attribute Value
        Expanded(
          child: InkWell(
            onTap: () {
              if (filter.extras['attributeName'] == null) {
                GlobalSnackbar.info(message: 'Select an Attribute Name first');
                return;
              }
              _showSelectionSheet(
                context: context,
                title: "Select Value",
                items: itemController.currentAttributeValues, // These update based on previous selection
                isLoading: itemController.isLoadingAttributeValues.value,
                onSelected: (val) => controller.updateValue(index, val),
              );
            },
            child: InputDecorator(
              decoration: FrappeTheme.inputDecoration('Value'),
              child: Text(
                filter.value.isEmpty ? 'Select...' : filter.value,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStandardInputs(BuildContext context, int index, FrappeFilter filter) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: () => _showSelectionSheet(
              context: context,
              title: "Operator",
              items: controller.availableOperators,
              onSelected: (op) => controller.updateOperator(index, op),
            ),
            child: InputDecorator(
              decoration: FrappeTheme.inputDecoration('Op').copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              ),
              child: Text(filter.operator, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _buildValueInputField(context, index, filter),
        ),
      ],
    );
  }

  Widget _buildValueInputField(BuildContext context, int index, FrappeFilter filter) {
    if (filter.config.fieldtype == 'Link') {
      return InkWell(
        onTap: () {
          // Use data from itemController for specific links to save API calls, or fallback
          List<String> options = [];
          bool loading = false;

          if (filter.config.doctype == 'Item Group') {
            options = itemController.itemGroups;
            loading = itemController.isLoadingGroups.value;
          } else if (filter.config.doctype == 'Item') {
            options = itemController.templateItems;
            loading = itemController.isLoadingTemplates.value;
          }

          _showSelectionSheet(
            context: context,
            title: "Select ${filter.label}",
            items: options,
            isLoading: loading,
            onSelected: (val) => controller.updateValue(index, val),
          );
        },
        child: InputDecorator(
          decoration: FrappeTheme.inputDecoration('Value'),
          child: Text(
              filter.value.isEmpty ? 'Select...' : filter.value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis
          ),
        ),
      );
    }

    // Standard Text Field
    return SizedBox(
      height: 48,
      child: TextFormField(
        initialValue: filter.value,
        style: const TextStyle(fontSize: 13),
        decoration: FrappeTheme.inputDecoration('Value'),
        onChanged: (val) => controller.updateValue(index, val),
      ),
    );
  }

  // --- Stateless Selection Helper (Uses GetX for search state) ---
  void _showSelectionSheet({
    required BuildContext context,
    required String title,
    required List<String> items,
    required Function(String) onSelected,
    bool isLoading = false,
  }) {
    final RxString searchQuery = ''.obs; // Local ephemeral state

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(FrappeTheme.radius * 1.5)),
        ),
        child: Column(
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: FrappeTheme.textBody)),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              decoration: FrappeTheme.inputDecoration('Search...').copyWith(prefixIcon: const Icon(Icons.search)),
              onChanged: (val) => searchQuery.value = val,
            ),
            const SizedBox(height: 12),

            // Reactive List
            Expanded(
              child: Obx(() {
                if (isLoading) return const Center(child: CircularProgressIndicator());

                final query = searchQuery.value.toLowerCase();
                final filtered = query.isEmpty
                    ? items
                    : items.where((i) => i.toLowerCase().contains(query)).toList();

                if (filtered.isEmpty) return const Center(child: Text("No items found", style: TextStyle(color: FrappeTheme.textLabel)));

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    return ListTile(
                      title: Text(item, style: const TextStyle(color: FrappeTheme.textBody)),
                      onTap: () {
                        onSelected(item);
                        Get.back();
                      },
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}