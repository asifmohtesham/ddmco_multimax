import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/item/item_controller.dart';

class ItemFilterBottomSheet extends StatefulWidget {
  const ItemFilterBottomSheet({super.key});

  @override
  State<ItemFilterBottomSheet> createState() => _ItemFilterBottomSheetState();
}

class _ItemFilterBottomSheetState extends State<ItemFilterBottomSheet> {
  final ItemController controller = Get.find();

  late TextEditingController itemGroupController;
  late TextEditingController attributeController;
  late bool showImagesOnly;

  @override
  void initState() {
    super.initState();
    itemGroupController = TextEditingController(text: _extractFilterValue('item_group'));
    // We use description to filter by attributes (e.g., Color, Size usually appear in description/name)
    attributeController = TextEditingController(text: _extractFilterValue('description'));
    showImagesOnly = controller.showImagesOnly.value;
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
    attributeController.dispose();
    super.dispose();
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
                  const Text('Filter By Attributes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: attributeController,
                    decoration: const InputDecoration(
                      labelText: 'Attribute / Keywords',
                      hintText: 'e.g., Red, Large, Cotton',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.style),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: itemGroupController,
                    decoration: const InputDecoration(
                      labelText: 'Item Group',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
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

                if (attributeController.text.isNotEmpty) {
                  // Searching in description covers most attribute cases in standard ERPNext
                  filters['description'] = ['like', '%${attributeController.text}%'];
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