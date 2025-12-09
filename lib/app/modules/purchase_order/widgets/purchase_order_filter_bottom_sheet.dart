import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_controller.dart';

class PurchaseOrderFilterBottomSheet extends StatelessWidget {
  const PurchaseOrderFilterBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final PurchaseOrderController controller = Get.find();
    final supplierController = TextEditingController(text: controller.activeFilters['supplier']);

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
            Text('Filter Purchase Orders', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: supplierController,
              decoration: const InputDecoration(labelText: 'Supplier', border: OutlineInputBorder()),
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
              child: const Text('Apply'),
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