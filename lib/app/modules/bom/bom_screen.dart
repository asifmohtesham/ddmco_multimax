import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class BomScreen extends GetView<BomController> {
  const BomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(title: ('Bill of Materials')),
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            _buildHeaderSummary(),
            Expanded(child: _buildSimpleList()),
          ],
        );
      }),
    );
  }

  Widget _buildHeaderSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildKpi('Total BOMs', '${controller.totalBoms}', Colors.blue),
          _buildKpi('Active', '${(controller.activeRate * 100).toInt()}%', Colors.green),
          _buildKpi('Avg Cost', NumberFormat.compactSimpleCurrency().format(controller.averageCost), Colors.orange),
        ],
      ),
    );
  }

  Widget _buildKpi(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSimpleList() {
    if (controller.boms.isEmpty) return const Center(child: Text("No BOMs found"));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: controller.boms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final bom = controller.boms[index];
        final bool isActive = bom.isActive == 1;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isActive ? Colors.transparent : Colors.grey.shade200),
            boxShadow: [
              if (isActive) BoxShadow(color: Colors.blue.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isActive ? Colors.blue.shade100 : Colors.grey.shade100,
              child: Icon(Icons.layers, color: isActive ? Colors.blue.shade700 : Colors.grey),
            ),
            title: Text(bom.itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(bom.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${FormattingHelper.getCurrencySymbol(bom.currency)} ${NumberFormat("#,##0").format(bom.totalCost)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(fontSize: 10, color: isActive ? Colors.green.shade700 : Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}