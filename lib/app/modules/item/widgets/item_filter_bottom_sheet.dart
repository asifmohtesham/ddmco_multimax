import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/item/item_controller.dart';

class ItemFilterBottomSheet extends StatefulWidget {
  const ItemFilterBottomSheet({super.key});

  @override
  State<ItemFilterBottomSheet> createState() => _ItemFilterBottomSheetState();
}

class _ItemFilterBottomSheetState extends State<ItemFilterBottomSheet> {
  final ItemController controller = Get.find();

  late TextEditingController itemGroupController;
  late TextEditingController attributeNameController;
  late TextEditingController attributeValueController;
  late bool showImagesOnly;

  @override
  void initState() {
    super.initState();
    itemGroupController = TextEditingController(text: _extractFilterValue('item_group'));

    // Extract stored attribute filters (using internal keys)
    attributeNameController = TextEditingController(text: controller.activeFilters['_attribute_name']);
    attributeValueController = TextEditingController(text: controller.activeFilters['_attribute_value']);

    showImagesOnly = controller.showImagesOnly.value;

    // Pre-load values if an attribute was already selected
    if (attributeNameController.text.isNotEmpty) {
      controller.fetchAttributeValues(attributeNameController.text);
    }
  }

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    if (val is String) return val;
    return '';
  }

  @override
  void dispose() {
    itemGroupController.dispose();
    attributeNameController.dispose();
    attributeValueController.dispose();
    super.dispose();
  }

  // Generic Picker for Group, Attribute Name, and Attribute Value
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filter Items', style: Theme.of(context).textTheme.titleLarge),
                TextButton(
                  onPressed: () {
                    controller.clearFilters();
                    Get.back();
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  SwitchListTile(
                    title: const Text('Show Images Only'),
                    subtitle: const Text('Hide items without a product image'),
                    value: showImagesOnly,
                    onChanged: (val) {
                      setState(() {
                        showImagesOnly = val;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),

                  // Item Group
                  TextFormField(
                    controller: itemGroupController,
                    readOnly: true,
                    onTap: () => _showSelectionSheet(
                      context: context,
                      title: "Select Item Group",
                      items: controller.itemGroups,
                      isLoading: controller.isLoadingGroups.value,
                      onSelected: (val) => setState(() => itemGroupController.text = val),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Item Group',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // New Attribute Filters
                  const Text('Filter By Attributes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: attributeNameController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Attribute',
                            hintText: 'Color, Size...',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          onTap: () => _showSelectionSheet(
                              context: context,
                              title: "Select Attribute",
                              items: controller.itemAttributes,
                              isLoading: controller.isLoadingAttributes.value,
                              onSelected: (val) {
                                setState(() {
                                  attributeNameController.text = val;
                                  attributeValueController.clear(); // Reset value on attribute change
                                });
                                controller.fetchAttributeValues(val);
                              }
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Obx(() {
                          final enabled = attributeNameController.text.isNotEmpty;
                          return TextFormField(
                            controller: attributeValueController,
                            readOnly: true,
                            enabled: enabled,
                            decoration: InputDecoration(
                              labelText: 'Value',
                              hintText: 'Red, Large...',
                              border: const OutlineInputBorder(),
                              suffixIcon: controller.isLoadingAttributeValues.value
                                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : const Icon(Icons.arrow_drop_down),
                              fillColor: enabled ? null : Colors.grey.shade100,
                              filled: !enabled,
                            ),
                            onTap: enabled ? () => _showSelectionSheet(
                              context: context,
                              title: "Select Value",
                              items: controller.currentAttributeValues,
                              onSelected: (val) => setState(() => attributeValueController.text = val),
                            ) : null,
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final filters = <String, dynamic>{};

                if (itemGroupController.text.isNotEmpty) {
                  filters['item_group'] = ['like', '%${itemGroupController.text}%'];
                }

                // Store both name and value for UI restoration, though controller might only use value for querying
                if (attributeNameController.text.isNotEmpty) {
                  filters['_attribute_name'] = attributeNameController.text;
                }

                if (attributeValueController.text.isNotEmpty) {
                  filters['_attribute_value'] = attributeValueController.text;
                }

                controller.setImagesOnly(showImagesOnly);
                controller.applyFilters(filters);
                Get.back();
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Apply Filters'),
            ),
          ],
        ),
      ),
    );
  }
}