import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_bottom_bar.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart'; // Added Import

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthenticationController authController = Get.find<AuthenticationController>();

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
              // 1. Welcome Section (Compact)
              Obx(() {
                final user = authController.currentUser.value;
                final name = user?.name ?? 'User';
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Welcome,',
                            style: TextStyle(fontSize: 14, color: Colors.grey[600])
                        ),
                        Text(
                            name,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                    CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Text(name.isNotEmpty ? name[0] : 'U', style: TextStyle(color: Theme.of(context).primaryColor))
                    )
                  ],
                );
              }),
              const SizedBox(height: 16),

              // 2. Barcode Input (Consistent UX)
              Obx(() => BarcodeInputWidget(
                onScan: controller.onScan,
                controller: controller.barcodeController,
                isLoading: controller.isScanning.value,
                hintText: 'Scan Item / Batch',
              )),

              const SizedBox(height: 16),

              // 3. Overview Grid (Compact)
              const Text('Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Obx(() {
                if (controller.isLoadingStats.value) {
                  return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                }
                return GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.6, // Shorter cards for compactness
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

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      // 4. FAB for the main creation action (saving space from body)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.goToDeliveryNote,
        icon: const Icon(Icons.add),
        label: const Text('New Delivery Note'),
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
      shadowColor: color.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                color.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle)
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}