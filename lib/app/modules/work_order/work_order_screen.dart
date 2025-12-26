import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/work_order/work_order_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class WorkOrderScreen extends GetView<WorkOrderController> {
  const WorkOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: MainAppBar(title: 'Production Orders',),
      drawer: const AppNavDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {}, // Trigger creation logic
        label: const Text('New Order'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blue.shade800,
      ),
      body: Obx(() {
        if (controller.isLoading.value) return const Center(child: CircularProgressIndicator());
        if (controller.workOrders.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: controller.workOrders.length,
          itemBuilder: (context, index) {
            final wo = controller.workOrders[index];
            final double percent = (wo.qty > 0) ? (wo.producedQty / wo.qty).clamp(0.0, 1.0) : 0.0;
            final bool isCompleted = wo.status == 'Completed';

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StatusPill(status: wo.status),
                        Text(wo.name, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      wo.itemName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Produced', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(height: 4),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(text: '${wo.producedQty.toInt()}', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 16)),
                                    TextSpan(text: ' / ${wo.qty.toInt()}', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if(!isCompleted)
                          CircularProgressIndicator(
                            value: percent,
                            backgroundColor: Colors.grey.shade100,
                            color: Colors.blue,
                            strokeWidth: 4,
                          ),
                        if(isCompleted)
                          const Icon(Icons.check_circle, color: Colors.green, size: 32)
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade100,
                        color: isCompleted ? Colors.green : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.precision_manufacturing_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No Active Orders', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}