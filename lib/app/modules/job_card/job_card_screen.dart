import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/job_card/job_card_controller.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';

class JobCardScreen extends GetView<JobCardController> {
  const JobCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job Cards')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.jobCards.isEmpty) {
          return const Center(child: Text('No Job Cards found.'));
        }
        return ListView.builder(
          itemCount: controller.jobCards.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final jc = controller.jobCards[index];
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(jc.operation, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${jc.name} • ${jc.workOrder}'),
                    if(jc.workstation != null) Text('Station: ${jc.workstation}'),
                    const SizedBox(height: 4),
                    Text('Qty: ${jc.totalCompletedQty} / ${jc.forQuantity}'),
                  ],
                ),
                trailing: StatusPill(status: jc.status),
              ),
            );
          },
        );
      }),
    );
  }
}