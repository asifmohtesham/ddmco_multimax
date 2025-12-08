import 'dart:ui'; // Added
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/bom/bom_controller.dart';
import 'package:ddmco_multimax/app/data/models/bom_model.dart';
import 'package:ddmco_multimax/app/data/utils/formatting_helper.dart';
import 'package:intl/intl.dart';

class BomScreen extends GetView<BomController> {
  const BomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bill of Materials'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'List'),
              Tab(text: 'Dashboard'),
            ],
          ),
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            children: [
              _buildListView(context),
              _buildDashboardView(context),
            ],
          );
        }),
      ),
    );
  }

  // --- Tab 1: List View ---
  Widget _buildListView(BuildContext context) {
    if (controller.boms.isEmpty) {
      return const Center(child: Text('No BOMs found.'));
    }
    return ListView.builder(
      itemCount: controller.boms.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final bom = controller.boms[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text(bom.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                    bom.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey,
                      fontFeatures: [FontFeature.slashedZero()], // Added
                    )
                ),
                const SizedBox(height: 4),
                Text(
                  'Cost: ${FormattingHelper.getCurrencySymbol(bom.currency)} ${NumberFormat("#,##0.00").format(bom.totalCost)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bom.isActive == 1 ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: bom.isActive == 1 ? Colors.green.shade200 : Colors.grey.shade300),
              ),
              child: Text(
                bom.isActive == 1 ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: bom.isActive == 1 ? Colors.green.shade700 : Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Tab 2: Dashboard View ---
  Widget _buildDashboardView(BuildContext context) {
    final bool isEmpty = controller.boms.isEmpty;

    final int totalBoms = isEmpty ? 142 : controller.totalBoms;
    final double activeRate = isEmpty ? 0.88 : controller.activeRate;
    final double avgCost = isEmpty ? 1250.50 : controller.averageCost;

    final List<dynamic> topList = isEmpty
        ? [
      {'itemName': 'Industrial Pump Assy', 'totalCost': 5400.0, 'code': 'BOM-001'},
      {'itemName': 'Conveyor Belt Motor', 'totalCost': 3200.0, 'code': 'BOM-023'},
      {'itemName': 'Control Panel Unit', 'totalCost': 1850.0, 'code': 'BOM-089'},
    ]
        : controller.topCostBoms;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Sample Data Visualization',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        Text(
                          'Add Bill of Materials to see detailed analysis and meaningful insights here.',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const Text(
              'Manufacturing Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Total BOMs',
                  value: totalBoms.toString(),
                  icon: Icons.assignment,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'Avg Cost',
                  value: '\$${NumberFormat.compact().format(avgCost)}',
                  icon: Icons.attach_money,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('BOM Status Distribution', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('${(activeRate * 100).toStringAsFixed(1)}% Active', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: activeRate,
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Active', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('Inactive', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text('Highest Value Components', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topList.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = topList[index];
                final String name = isEmpty ? item['itemName'] : item.itemName;
                final String code = isEmpty ? item['code'] : item.name;
                final double cost = isEmpty ? item['totalCost'] : item.totalCost;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade50,
                    child: Text('${index + 1}', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontFeatures: [FontFeature.slashedZero()], // Added
                      )
                  ),
                  trailing: Text(
                    '\$${NumberFormat("#,##0.00").format(cost)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}