import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/item/item_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

class ItemFilterBottomSheet extends StatefulWidget {
  const ItemFilterBottomSheet({super.key});

  @override
  State<ItemFilterBottomSheet> createState() => _ItemFilterBottomSheetState();
}

class _ItemFilterBottomSheetState extends State<ItemFilterBottomSheet> {
  final ItemController controller = Get.find();

  final RxList<FilterRow> localFilters = <FilterRow>[].obs;
  final showImagesOnly = false.obs;

  @override
  void initState() {
    super.initState();
    if (controller.activeFilters.isEmpty) {
      localFilters.add(controller.availableFields[1].clone());
    } else {
      localFilters.assignAll(controller.activeFilters.map((e) => e.clone()).toList());
    }
    showImagesOnly.value = controller.showImagesOnly.value;
  }

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
        final cs = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)))),
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

  void _addFilterRow() {
    localFilters.add(controller.availableFields[0].clone());
  }

  void _removeFilterRow(int index) {
    localFilters.removeAt(index);
  }

  void _updateFilterField(int index, String fieldLabel) {
    final template = controller.availableFields.firstWhere((e) => e.label == fieldLabel);
    localFilters[index] = template.clone();
  }

  void _applyFilters() {
    controller.setImagesOnly(showImagesOnly.value);
    final validFilters = localFilters.where((f) => f.value.isNotEmpty).toList();
    controller.applyFilters(validFilters);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Items',
      activeFilterCount: localFilters.length + (showImagesOnly.value ? 1 : 0),
      sortOptions: const [
        SortOption('Modified', 'modified'),
        SortOption('Status', 'docstatus'),
        SortOption('Item Code', 'item_code'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        localFilters.clear();
        showImagesOnly.value = false;
        controller.clearFilters();
      },
      filterWidgets: [
        ...localFilters.asMap().entries.map((entry) {
          final index = entry.key;
          final filter = entry.value;
          final isAttribute = filter.fieldType == 'Attribute';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => _showSelectionSheet(
                        context: context,
                        title: "Select Field",
                        items: controller.availableFields.map((e) => e.label).toList(),
                        onSelected: (label) => _updateFilterField(index, label),
                      ),
                      child: Row(
                        children: [
                          Text(filter.label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.primary)),
                          Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _removeFilterRow(index),
                      child: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (isAttribute) ...[
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showSelectionSheet(
                            context: context,
                            title: "Select Attribute",
                            items: controller.itemAttributes,
                            isLoading: controller.isLoadingAttributes.value,
                            onSelected: (val) {
                              filter.attributeName = val;
                              filter.value = '';
                              controller.fetchAttributeValues(val);
                              localFilters.refresh();
                            },
                          ),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Attribute Name', isDense: true, border: OutlineInputBorder()),
                            child: Text(filter.attributeName.isEmpty ? 'Select...' : filter.attributeName),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (filter.attributeName.isEmpty) {
                              GlobalSnackbar.info(message: 'Select an Attribute Name first');
                              return;
                            }
                            _showSelectionSheet(
                              context: context,
                              title: "Select Value",
                              items: controller.currentAttributeValues,
                              isLoading: controller.isLoadingAttributeValues.value,
                              onSelected: (val) {
                                filter.value = val;
                                localFilters.refresh();
                              },
                            );
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Value', isDense: true, border: OutlineInputBorder()),
                            child: Text(filter.value.isEmpty ? 'Select...' : filter.value),
                          ),
                        ),
                      ),
                    ],
                  )
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          onTap: () => _showSelectionSheet(
                            context: context,
                            title: "Operator",
                            items: controller.availableOperators,
                            onSelected: (op) {
                              filter.operator = op;
                              localFilters.refresh();
                            },
                          ),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Operator', isDense: true, border: OutlineInputBorder()),
                            child: Text(filter.operator),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: _buildValueInput(context, filter, index),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),

        OutlinedButton.icon(
          onPressed: _addFilterRow,
          icon: const Icon(Icons.add),
          label: const Text('Add Filter Condition'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    ));
  }

  Widget _buildValueInput(BuildContext context, FilterRow filter, int index) {
    if (filter.fieldType == 'Link') {
      return InkWell(
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
            onSelected: (val) {
              filter.value = val;
              localFilters.refresh();
            },
          );
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Value', isDense: true, border: OutlineInputBorder()),
          child: Text(filter.value.isEmpty ? 'Select...' : filter.value, overflow: TextOverflow.ellipsis),
        ),
      );
    } else {
      return TextFormField(
        initialValue: filter.value,
        decoration: const InputDecoration(labelText: 'Value', isDense: true, border: OutlineInputBorder()),
        onChanged: (val) => filter.value = val,
      );
    }
  }
}
