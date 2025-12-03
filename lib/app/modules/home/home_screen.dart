import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/app_bottom_bar.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.fetchDashboardData(),
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: controller.fetchDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Obx(() {
                if (controller.isLoadingStats.value) {
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                }
                return GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.4,
                  children: [
                    DashboardStatCard(
                      title: 'Delivery Notes',
                      count: controller.draftDeliveryNotesCount.value,
                      icon: Icons.local_shipping_outlined,
                      color: Colors.blue,
                      label: 'Draft',
                      onTap: controller.goToDeliveryNote,
                    ),
                    DashboardStatCard(
                      title: 'Packing Slips',
                      count: controller.draftPackingSlipsCount.value,
                      icon: Icons.inventory_2_outlined,
                      color: Colors.orange,
                      label: 'Draft',
                      onTap: controller.goToPackingSlip,
                    ),
                    DashboardStatCard(
                      title: 'POS Uploads',
                      count: controller.pendingPosUploadsCount.value,
                      icon: Icons.receipt_long_outlined,
                      color: Colors.purple,
                      label: 'Pending',
                      onTap: controller.goToPosUpload,
                    ),
                    DashboardStatCard(
                      title: 'ToDos',
                      count: controller.openTodosCount.value,
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                      label: 'Open',
                      onTap: controller.goToToDo,
                    ),
                  ],
                );
              }),
              const SizedBox(height: 24),
              const Text('Quick Actions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ActionCard(
                      icon: Icons.add_circle_outline,
                      title: 'New Delivery Note',
                      onTap: controller.goToDeliveryNote, // Goes to list, user can tap FAB. Or deep link? Sticking to list.
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ActionCard(
                      icon: Icons.qr_code_scanner,
                      title: 'Scan Item',
                      onTap: () => Get.snackbar('Coming Soon', 'Global scanner not implemented'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomBar(),
    );
  }
}

class DashboardStatCard extends StatelessWidget {
  final String title;
  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const DashboardStatCard({
    super.key,
    required this.title,
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  Text(
                    '$count',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('$label Items', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const ActionCard({super.key, required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Column(
            children: [
              Icon(icon, size: 32, color: Colors.grey[800]),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
