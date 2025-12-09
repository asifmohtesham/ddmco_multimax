import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_bottom_bar.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:percent_indicator/circular_percent_indicator.dart'; // Required package

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
              // 1. Welcome Section
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
                        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        child: Text(name.isNotEmpty ? name[0] : 'U', style: TextStyle(color: Theme.of(context).primaryColor))
                    )
                  ],
                );
              }),
              const SizedBox(height: 16),

              // 2. Barcode Input
              Obx(() => BarcodeInputWidget(
                onScan: controller.onScan,
                controller: controller.barcodeController,
                isLoading: controller.isScanning.value,
                hintText: 'Scan Item / Batch',
              )),

              const SizedBox(height: 24),

              // 3. User KPI Gauges (Work Order & Job Cards)
              const Text('Production KPIs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              Obx(() {
                if (controller.isLoadingStats.value) {
                  return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                }

                return Row(
                  children: [
                    Expanded(
                      child: UserKpiGauge(
                        title: 'Work Orders',
                        actual: controller.activeWorkOrdersCount.value,
                        target: controller.targetWorkOrders,
                        color: Colors.blue,
                        icon: Icons.assignment_outlined,
                        onTap: controller.goToWorkOrder,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: UserKpiGauge(
                        title: 'Job Cards',
                        actual: controller.activeJobCardsCount.value,
                        target: controller.targetJobCards,
                        color: Colors.orange,
                        icon: Icons.assignment_ind_outlined,
                        onTap: controller.goToJobCard,
                      ),
                    ),
                  ],
                );
              }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.goToDeliveryNote,
        icon: const Icon(Icons.add),
        label: const Text('New Delivery Note'),
      ),
      bottomNavigationBar: const AppBottomBar(),
    );
  }
}

class UserKpiGauge extends StatelessWidget {
  final String title;
  final int actual;
  final int target;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const UserKpiGauge({
    super.key,
    required this.title,
    required this.actual,
    required this.target,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double percent = (target > 0) ? (actual / target).clamp(0.0, 1.0) : 0.0;

    return Card(
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: Colors.grey[700]),
                  const SizedBox(width: 6),
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              CircularPercentIndicator(
                radius: 45.0,
                lineWidth: 9.0,
                percent: percent,
                animation: true,
                center: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$actual",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.0, color: color),
                    ),
                    const Text("Actual", style: TextStyle(fontSize: 10.0, color: Colors.grey)),
                  ],
                ),
                footer: Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(
                    "Target: $target",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0, color: Colors.grey),
                  ),
                ),
                circularStrokeCap: CircularStrokeCap.round,
                progressColor: color,
                backgroundColor: color.withValues(alpha: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}