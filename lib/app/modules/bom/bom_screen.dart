import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/bom/bom_controller.dart';
import 'package:ddmco_multimax/app/data/models/bom_model.dart';
import 'package:ddmco_multimax/app/data/utils/formatting_helper.dart';

class BomScreen extends GetView<BomController> {
  const BomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill of Materials')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.boms.isEmpty) {
          return const Center(child: Text('No BOMs found.'));
        }
        return ListView.builder(
          itemCount: controller.boms.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final bom = controller.boms[index];
            return Card(
              child: ListTile(
                title: Text(bom.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bom.name, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    Text('Cost: ${FormattingHelper.getCurrencySymbol(bom.currency)} ${bom.totalCost.toStringAsFixed(2)}'),
                  ],
                ),
                trailing: Chip(
                  label: Text(bom.isActive == 1 ? 'Active' : 'Inactive'),
                  backgroundColor: bom.isActive == 1 ? Colors.green.shade50 : Colors.grey.shade100,
                  labelStyle: TextStyle(color: bom.isActive == 1 ? Colors.green : Colors.grey),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}