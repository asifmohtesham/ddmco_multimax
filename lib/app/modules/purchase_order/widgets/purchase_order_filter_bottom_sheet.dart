import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';

class PurchaseOrderFilterBottomSheet extends StatefulWidget {
  const PurchaseOrderFilterBottomSheet({super.key});

  @override
  State<PurchaseOrderFilterBottomSheet> createState() => _PurchaseOrderFilterBottomSheetState();
}

class _PurchaseOrderFilterBottomSheetState extends State<PurchaseOrderFilterBottomSheet> {
  final PurchaseOrderController controller = Get.find();
  late TextEditingController supplierController;

  @override
  void initState() {
    super.initState();
    // Safely extract the string value from the filter
    supplierController = TextEditingController(text: _extractFilterValue('supplier'));
  }

  @override
  void dispose() {
    supplierController.dispose();
    super.dispose();
  }

  String _extractFilterValue(String key) {
    final val = controller.activeFilters[key];
    // Check if it's the list format ['like', '%value%']
    if (val is List && val.isNotEmpty && val[0] == 'like') {
      return val[1].toString().replaceAll('%', '');
    }
    // Handle direct string if ever stored that way
    if (val is String) return val;
    return '';
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
                Text('Filter Purchase Orders', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Get.back(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),
            TextFormField(
              controller: supplierController,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final filters = <String, dynamic>{};
                if (supplierController.text.isNotEmpty) {
                  filters['supplier'] = ['like', '%${supplierController.text}%'];
                }
                controller.applyFilters(filters);
                Get.back();
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Apply Filters'),
            ),
            TextButton(
              onPressed: () {
                controller.clearFilters();
                Get.back();
              },
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}