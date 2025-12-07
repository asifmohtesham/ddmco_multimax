import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/work_order/work_order_controller.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class WorkOrderScreen extends GetView<WorkOrderController> {
  const WorkOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Work Orders')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.workOrders.isEmpty) {
          return const Center(child: Text('No Work Orders found.'));
        }
        return ListView.builder(
          itemCount: controller.workOrders.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final wo = controller.workOrders[index];
            final percent = (wo.qty > 0) ? (wo.producedQty / wo.qty).clamp(0.0, 1.0) : 0.0;

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(wo.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                        StatusPill(status: wo.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(wo.itemName, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Start: ${wo.plannedStartDate}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Produced: ${wo.producedQty} / ${wo.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${(percent * 100).toInt()}%', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearPercentIndicator(
                      lineHeight: 6.0,
                      percent: percent,
                      backgroundColor: Colors.grey.shade200,
                      progressColor: Colors.blue,
                      barRadius: const Radius.circular(3),
                      padding: EdgeInsets.zero,
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
}