import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

class JobCardScreen extends GetView<JobCardController> {
  const JobCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: MainAppBar(title: 'My Tasks',),
      drawer: const AppNavDrawer(),
      body: Obx(() {
        if (controller.isLoading.value) return const Center(child: CircularProgressIndicator());

        return Column(
          children: [
            _buildShopFloorStats(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: controller.jobCards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final jc = controller.jobCards[index];
                  final bool isOpen = jc.status == 'Open' || jc.status == 'Work In Progress';

                  return Material(
                    color: Colors.white,
                    elevation: isOpen ? 2 : 0,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {}, // Navigate to detail
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              height: 50, width: 50,
                              decoration: BoxDecoration(
                                color: _getStatusColor(jc.status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.build, color: _getStatusColor(jc.status)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(jc.operation, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${jc.workstation ?? "Unassigned"} • ${jc.totalCompletedQty.toInt()}/${jc.forQuantity.toInt()} units',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            if (isOpen)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade600,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('START', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildShopFloorStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStatItem('Pending', '${controller.openCards}', Colors.orange),
          _buildStatItem('Completed', '${controller.completedCards}', Colors.green),
          _buildStatItem('Total', '${controller.totalCards}', Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Open': return Colors.orange;
      case 'Work In Progress': return Colors.blue;
      case 'Completed': return Colors.green;
      default: return Colors.grey;
    }
  }
}