import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/frappe_filter_sheet_controller.dart';
import '../models/frappe_filter.dart'; // Ensure this model is accessible
import '../app/modules/global_widgets/global_filter_bottom_sheet.dart';
import '../theme/frappe_theme.dart';

class FrappeFilterBottomSheet extends GetView<FrappeFilterSheetController> {
  const FrappeFilterBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter ${controller.listController.doctype}',
      activeFilterCount: controller.localFilters.length,

      // Sorting uses the parent controller directly
      sortOptions: const [
        SortOption('Modified', 'modified'),
        SortOption('ID', 'name'),
        SortOption('Status', 'docstatus'),
      ],
      currentSortField: controller.listController.sortField.value,
      currentSortOrder: controller.listController.sortOrder.value,
      onSortChanged: controller.listController.setSort,

      onApply: controller.apply,
      onClear: controller.clear,

      filterWidgets: [
        ...controller.localFilters.asMap().entries.map((entry) {
          return _buildFilterRow(context, entry.key, entry.value);
        }),

        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.addFilterRow,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Condition'),
          style: OutlinedButton.styleFrom(
            foregroundColor: FrappeTheme.primary,
            side: const BorderSide(color: FrappeTheme.primary),
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    ));
  }

  Widget _buildFilterRow(BuildContext context, int index, FrappeFilter filter) {
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
          // Row 1: Field Selector & Remove
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _showSelectionSheet(
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

          // Row 2: Operator & Value
          Row(
            children: [
              // Operator
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () => _showSelectionSheet(
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

              // Value Input
              Expanded(
                flex: 4,
                child: _buildValueInput(filter, index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValueInput(FrappeFilter filter, int index) {
    // 1. Link Field
    if (filter.config.fieldtype == 'Link' && filter.config.doctype != null) {
      return InkWell(
        onTap: () => _showSearchableSelection(
            title: "Select ${filter.config.label}",
            doctype: filter.config.doctype!,
            onSelected: (val) => controller.updateValue(index, val)
        ),
        child: InputDecorator(
          decoration: FrappeTheme.inputDecoration('Value'),
          child: Text(
              filter.value.isEmpty ? 'Select...' : filter.value,
              style: TextStyle(color: filter.value.isEmpty ? Colors.grey : Colors.black),
              maxLines: 1,
              overflow: TextOverflow.ellipsis
          ),
        ),
      );
    }

    // 2. Select Field
    if (filter.config.fieldtype == 'Select' && filter.config.options != null) {
      return InkWell(
        onTap: () => _showSelectionSheet(
            title: "Select ${filter.config.label}",
            items: filter.config.options!,
            onSelected: (val) => controller.updateValue(index, val)
        ),
        child: InputDecorator(
          decoration: FrappeTheme.inputDecoration('Value'),
          child: Text(filter.value.isEmpty ? 'Select...' : filter.value),
        ),
      );
    }

    // 3. Standard Text Input
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

  // --- UI Helpers ---

  void _showSelectionSheet({
    required String title,
    required List<String> items,
    required Function(String) onSelected,
  }) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(items[i]),
                  onTap: () {
                    onSelected(items[i]);
                    Get.back();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchableSelection({
    required String title,
    required String doctype,
    required Function(String) onSelected
  }) {
    final textCtrl = TextEditingController();
    final RxList<String> results = <String>[].obs;

    // Initial fetch
    controller.searchLink(doctype, '').then((v) => results.assignAll(v));

    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: textCtrl,
              decoration: FrappeTheme.inputDecoration('Search...').copyWith(prefixIcon: const Icon(Icons.search)),
              onChanged: (val) {
                Future.delayed(const Duration(milliseconds: 300), () async {
                  final res = await controller.searchLink(doctype, val);
                  results.assignAll(res);
                });
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Obx(() => ListView.builder(
                itemCount: results.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(results[i]),
                  onTap: () {
                    onSelected(results[i]);
                    Get.back();
                  },
                ),
              )),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}