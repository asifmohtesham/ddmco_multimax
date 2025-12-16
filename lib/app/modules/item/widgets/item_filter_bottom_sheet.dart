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

  late TextEditingController itemGroupController;
  late TextEditingController variantOfController;

  // Local state for adding a new attribute filter
  late TextEditingController attributeNameController;
  late TextEditingController attributeValueController;

  // Reactive State
  final showImagesOnly = false.obs;
  final itemGroup = ''.obs;
  final variantOf = ''.obs;
  final attributeName = ''.obs;

  // Local list to manage filters before applying
  final RxList<Map<String, String>> localAttributeFilters = <Map<String, String>>[].obs;

  @override
  void initState() {
    super.initState();
    itemGroupController = TextEditingController(text: _extractFilterValue('item_group'));
    variantOfController = TextEditingController(text: _extractFilterValue('variant_of'));

    itemGroup.value = itemGroupController.text;
    variantOf.value = variantOfController.text;
    showImagesOnly.value = controller.showImagesOnly.value;

    localAttributeFilters.assignAll(
        controller.attributeFilters.map((e) => Map<String, String>.from(e)).toList()
    );

    attributeNameController = TextEditingController();
    attributeValueController = TextEditingController();
  }

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    if (val is List && val.isNotEmpty && val[0] == '=') {
      return val[1].toString();
    }
    if (val is String) return val;
    return '';
  }

  @override
  void dispose() {
    itemGroupController.dispose();
    variantOfController.dispose();
    attributeNameController.dispose();
    attributeValueController.dispose();
    super.dispose();
  }

  int get _activeCount {
    int count = 0;
    if (showImagesOnly.value) count++;
    if (itemGroup.value.isNotEmpty) count++;
    if (variantOf.value.isNotEmpty) count++;
    count += localAttributeFilters.length;
    return count;
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

  void _addAttributeFilter() {
    final name = attributeNameController.text;
    final value = attributeValueController.text;

    if (name.isNotEmpty && value.isNotEmpty) {
      final exists = localAttributeFilters.any((e) => e['name'] == name && e['value'] == value);
      if (!exists) {
        localAttributeFilters.add({'name': name, 'value': value});
        attributeNameController.clear();
        attributeValueController.clear();
        attributeName.value = '';
      } else {
        GlobalSnackbar.info(message: 'Filter already added');
      }
    }
  }

  void _applyFilters() {
    final filters = <String, dynamic>{};

    if (itemGroupController.text.isNotEmpty) {
      filters['item_group'] = ['like', '%${itemGroupController.text}%'];
    }

    if (variantOfController.text.isNotEmpty) {
      filters['variant_of'] = variantOfController.text;
    }

    controller.setImagesOnly(showImagesOnly.value);
    controller.applyFilters(filters, localAttributeFilters.toList());
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
      title: 'Filter Items',
      activeFilterCount: _activeCount,
      sortOptions: const [
        SortOption('Item Name', 'item_name'),
        SortOption('Item Code', 'item_code'),
        SortOption('Modified', 'modified'),
        SortOption('Item Group', 'item_group'),
      ],
      currentSortField: controller.sortField.value,
      currentSortOrder: controller.sortOrder.value,
      onSortChanged: (field, order) => controller.setSort(field, order),
      onApply: _applyFilters,
      onClear: () {
        itemGroupController.clear();
        variantOfController.clear();
        localAttributeFilters.clear();
        itemGroup.value = '';
        variantOf.value = '';
        showImagesOnly.value = false;
        controller.clearFilters();
      },
      filterWidgets: [
        SwitchListTile(
          title: const Text('Show Images Only'),
          subtitle: const Text('Hide items without a product image'),
          value: showImagesOnly.value,
          onChanged: (val) => showImagesOnly.value = val,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: itemGroupController,
          readOnly: true,
          onTap: () => _showSelectionSheet(
            context: context,
            title: "Select Item Group",
            items: controller.itemGroups,
            isLoading: controller.isLoadingGroups.value,
            onSelected: (val) {
              itemGroupController.text = val;
              itemGroup.value = val;
            },
          ),
          decoration: const InputDecoration(
            labelText: 'Item Group',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.category),
            suffixIcon: Icon(Icons.arrow_drop_down),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: variantOfController,
          readOnly: true,
          onTap: () => _showSelectionSheet(
            context: context,
            title: "Select Template Item",
            items: controller.templateItems,
            isLoading: controller.isLoadingTemplates.value,
            onSelected: (val) {
              variantOfController.text = val;
              variantOf.value = val;
            },
          ),
          decoration: const InputDecoration(
            labelText: 'Variant Of (Template)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.copy),
            suffixIcon: Icon(Icons.arrow_drop_down),
            isDense: true,
          ),
        ),

        const SizedBox(height: 24),

        const Text('Filter By Attributes', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        Obx(() {
          if (localAttributeFilters.isEmpty) return const SizedBox.shrink();
          return Wrap(
            spacing: 8.0,
            children: localAttributeFilters.map((filter) {
              return Chip(
                label: Text('${filter['name']}: ${filter['value']}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  localAttributeFilters.remove(filter);
                },
                backgroundColor: Colors.blue.shade50,
                side: BorderSide(color: Colors.blue.shade200),
              );
            }).toList(),
          );
        }),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
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
                          onSelected: (val) => attributeValueController.text = val,
                        ) : null,
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addAttributeFilter,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Attribute Filter'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ));
  }
}