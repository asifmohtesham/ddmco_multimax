import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class ItemFilterBottomSheet extends StatefulWidget {
  const ItemFilterBottomSheet({super.key});

  @override
  State<ItemFilterBottomSheet> createState() => _ItemFilterBottomSheetState();
}

class _ItemFilterBottomSheetState extends State<ItemFilterBottomSheet> {
  final ItemController controller = Get.find();

  // Local State
  final RxList<FilterRow> localFilters = <FilterRow>[].obs;
  final RxList<Map<String, String>> localAttributeFilters = <Map<String, String>>[].obs;
  final showImagesOnly = false.obs;

  // Attribute Filter Controllers
  late TextEditingController attributeNameController;
  late TextEditingController attributeValueController;
  final attributeName = ''.obs;

  @override
  void initState() {
    super.initState();
    // 1. Initialize Standard Filters
    if (controller.activeFilters.isEmpty) {
      // Start with one empty row if none exist
      localFilters.add(controller.availableFields[1].clone()); // Default to Item Name
    } else {
      localFilters.assignAll(controller.activeFilters.map((e) => e.clone()).toList());
    }

    // 2. Initialize Attribute Filters
    localAttributeFilters.assignAll(
        controller.attributeFilters.map((e) => Map<String, String>.from(e)).toList()
    );
    showImagesOnly.value = controller.showImagesOnly.value;

    attributeNameController = TextEditingController();
    attributeValueController = TextEditingController();
  }

  @override
  void dispose() {
    attributeNameController.dispose();
    attributeValueController.dispose();
    super.dispose();
  }

  // --- Searchable Selection Sheet ---
  void _showSelectionSheet({
    required BuildContext context,
    required String title,
    required List<String> items,
    required Function(String) onSelected,
    bool isLoading = false,
  }) {
    final searchController = TextEditingController();
    final RxList<String> filteredItems = RxList<String>(items);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      if (val.isEmpty) {
                        filteredItems.assignAll(items);
                      } else {
                        filteredItems.assignAll(items.where(
                                (item) => item.toLowerCase().contains(val.toLowerCase())
                        ).toList());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() {
                      if (isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (filteredItems.isEmpty) {
                        return const Center(child: Text("No items found"));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: filteredItems.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return ListTile(
                            title: Text(item),
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
            );
          },
        );
      },
    );
  }

  // --- Filter Row Logic ---
  void _addFilterRow() {
    localFilters.add(controller.availableFields[0].clone());
  }

  void _removeFilterRow(int index) {
    localFilters.removeAt(index);
  }

  void _updateFilterField(int index, String fieldName) {
    final template = controller.availableFields.firstWhere((e) => e.field == fieldName);
    localFilters[index] = template.clone();
  }

  void _updateFilterOperator(int index, String op) {
    localFilters[index].operator = op;
    localFilters.refresh();
  }

  void _updateFilterValue(int index, String val) {
    localFilters[index].value = val;
    localFilters.refresh(); // Trigger UI update if needed
  }

  // --- Attribute Logic ---
  void _addAttributeFilter() {
    final name = attributeNameController.text;
    final value = attributeValueController.text;
    if (name.isNotEmpty && value.isNotEmpty) {
      if (!localAttributeFilters.any((e) => e['name'] == name && e['value'] == value)) {
        localAttributeFilters.add({'name': name, 'value': value});
        attributeNameController.clear();
        attributeValueController.clear();
        attributeName.value = '';
      }
    }
  }

  void _applyFilters() {
    controller.setImagesOnly(showImagesOnly.value);
    // Filter out rows with empty values to avoid bad queries
    final validFilters = localFilters.where((f) => f.value.isNotEmpty).toList();
    controller.applyFilters(validFilters, localAttributeFilters.toList());
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Items',
      activeFilterCount: localFilters.length + localAttributeFilters.length + (showImagesOnly.value ? 1 : 0),
      sortOptions: const [
        SortOption('Modified', 'modified'),
        SortOption('Item Name', 'item_name'),
        SortOption('Item Code', 'item_code'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        localFilters.clear();
        localAttributeFilters.clear();
        showImagesOnly.value = false;
        controller.clearFilters();
      },
      filterWidgets: [
        SwitchListTile(
          title: const Text('Show Images Only'),
          value: showImagesOnly.value,
          onChanged: (val) => showImagesOnly.value = val,
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),
        const SizedBox(height: 8),

        // --- DYNAMIC FILTER ROWS ---
        const Text("Filter Options", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),

        ...localFilters.asMap().entries.map((entry) {
          final index = entry.key;
          final filter = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // FIELD SELECTOR
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: () => _showSelectionSheet(
                          context: context,
                          title: "Select Field",
                          items: controller.availableFields.map((e) => e.label).toList(),
                          onSelected: (label) {
                            final field = controller.availableFields.firstWhere((e) => e.label == label).field;
                            _updateFilterField(index, field);
                          },
                        ),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Field',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
                          ),
                          child: Text(filter.label, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // OPERATOR SELECTOR
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () => _showSelectionSheet(
                          context: context,
                          title: "Operator",
                          items: controller.availableOperators,
                          onSelected: (op) => _updateFilterOperator(index, op),
                        ),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Operator',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down, size: 20),
                          ),
                          child: Text(filter.operator),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _removeFilterRow(index),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // VALUE INPUT
                if (filter.fieldType == 'Link')
                  InkWell(
                    onTap: () {
                      List<String> options = [];
                      bool loading = false;
                      if (filter.doctype == 'Item Group') {
                        options = controller.itemGroups;
                        loading = controller.isLoadingGroups.value;
                      } else if (filter.doctype == 'Item') {
                        options = controller.templateItems;
                        loading = controller.isLoadingTemplates.value;
                      }

                      _showSelectionSheet(
                        context: context,
                        title: "Select ${filter.label}",
                        items: options,
                        isLoading: loading,
                        onSelected: (val) => _updateFilterValue(index, val),
                      );
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Value',
                        isDense: true,
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(filter.value.isEmpty ? 'Select...' : filter.value),
                    ),
                  )
                else
                  TextFormField(
                    initialValue: filter.value,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => filter.value = val, // Direct mutation works as activeFilters read on apply
                  ),
              ],
            ),
          );
        }),

        OutlinedButton.icon(
          onPressed: _addFilterRow,
          icon: const Icon(Icons.add),
          label: const Text('Add Filter Condition'),
        ),

        const Divider(height: 32),

        // --- ATTRIBUTES SECTION ---
        const Text('Filter By Attributes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),

        if (localAttributeFilters.isNotEmpty)
          Wrap(
            spacing: 8.0,
            children: localAttributeFilters.map((filter) {
              return Chip(
                label: Text('${filter['name']}: ${filter['value']}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => localAttributeFilters.remove(filter),
                backgroundColor: Colors.blue.shade50,
                side: BorderSide(color: Colors.blue.shade200),
              );
            }).toList(),
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: attributeNameController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Attribute',
                  hintText: 'Color...',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  isDense: true,
                ),
                onTap: () => _showSelectionSheet(
                    context: context,
                    title: "Select Attribute",
                    items: controller.itemAttributes,
                    isLoading: controller.isLoadingAttributes.value,
                    onSelected: (val) {
                      attributeNameController.text = val;
                      attributeName.value = val;
                      attributeValueController.clear();
                      controller.fetchAttributeValues(val);
                    }
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Obx(() {
                final enabled = attributeName.value.isNotEmpty;
                return TextFormField(
                  controller: attributeValueController,
                  readOnly: true,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: 'Value',
                    hintText: 'Red...',
                    border: const OutlineInputBorder(),
                    suffixIcon: controller.isLoadingAttributeValues.value
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)))
                        : const Icon(Icons.arrow_drop_down),
                    fillColor: enabled ? Colors.white : Colors.grey.shade100,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    isDense: true,
                  ),
                  onTap: enabled ? () => _showSelectionSheet(
                    context: context,
                    title: "Select Value",
                    items: controller.currentAttributeValues,
                    onSelected: (val) {
                      attributeValueController.text = val;
                      _addAttributeFilter();
                    },
                  ) : null,
                );
              }),
            ),
          ],
        ),
      ],
    ));
  }
}