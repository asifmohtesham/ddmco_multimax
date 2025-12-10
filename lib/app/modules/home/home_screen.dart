import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/home/widgets/performance_timeline_card.dart';

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
            tooltip: 'Refresh Data',
            onPressed: () {
              controller.fetchDashboardData();
              controller.fetchPerformanceData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () {
              Get.snackbar('Notifications', 'No new notifications');
            },
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: Column(
        children: [
          // Scrollable Content Area
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await controller.fetchDashboardData();
                await controller.fetchPerformanceData();
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // Bottom padding for FAB
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. User Context Card (Improvised Header)
                    _buildUserContextCard(context),

                    const SizedBox(height: 16),

                    // 2. Performance Timeline (Visually grouped with context)
                    Obx(() => PerformanceTimelineCard(
                      isWeekly: controller.isWeeklyView.value,
                      onToggleView: controller.toggleTimelineView,
                      data: controller.timelineData,
                      isLoading: controller.isLoadingTimeline.value,
                      // Pass dates dynamically based on view type
                      selectedDate: controller.isWeeklyView.value
                          ? null // Range takes precedence in weekly view
                          : controller.selectedDailyDate.value,
                      selectedRange: controller.isWeeklyView.value
                          ? controller.selectedWeeklyRange.value
                          : null,
                      onDateChanged: controller.onDailyDateChanged,
                      onRangeChanged: controller.onWeeklyRangeChanged,
                    )),

                    const SizedBox(height: 24),

                    // 3. KPI Speedometers
                    const Text('Daily Goals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                    Obx(() {
                      if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
                        return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: SpeedometerKpiCard(
                              title: 'Work Orders',
                              actual: controller.activeWorkOrdersCount.value,
                              target: controller.targetWorkOrders,
                              icon: Icons.assignment_outlined,
                              onTap: controller.goToWorkOrder,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SpeedometerKpiCard(
                              title: 'Job Cards',
                              actual: controller.activeJobCardsCount.value,
                              target: controller.targetJobCards,
                              icon: Icons.assignment_ind_outlined,
                              onTap: controller.goToJobCard,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          // 4. Pinned Bottom Scan Field (Consistent with Forms)
          Obx(() => BarcodeInputWidget(
            onScan: controller.onScan,
            controller: controller.barcodeController,
            isLoading: controller.isScanning.value,
            hintText: 'Scan Item / Batch / Rack',
            activeRoute: AppRoutes.HOME,
          )),
        ],
      ),
      // Floating Action Button Positioned above the Bottom Input
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60.0),
        child: FloatingActionButton.extended(
          onPressed: controller.goToDeliveryNote,
          icon: const Icon(Icons.add),
          label: const Text('New Delivery Note'),
        ),
      ),
    );
  }

  Widget _buildUserContextCard(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: () => _showUserSearchModal(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Obx(() {
                final selectedUser = controller.selectedFilterUser.value;
                final userName = selectedUser?.name ?? 'Select User';
                return CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                );
              }),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Showing data for',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Obx(() {
                      final selectedUser = controller.selectedFilterUser.value;
                      return Row(
                        children: [
                          Flexible(
                            child: Text(
                              selectedUser?.name ?? 'Select User',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.blueGrey),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserSearchModal(BuildContext context) {
    final TextEditingController searchController = TextEditingController();
    final RxList<User> filteredUsers = RxList<User>(controller.userList);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text("Select User", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search users...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (val) {
                      filteredUsers.assignAll(controller.userList.where((user) {
                        final name = user.name.toLowerCase();
                        final email = user.email.toLowerCase();
                        return name.contains(val.toLowerCase()) || email.contains(val.toLowerCase());
                      }).toList());
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Obx(() => ListView.separated(
                      controller: scrollController,
                      itemCount: filteredUsers.length,
                      separatorBuilder: (c, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        final isSelected = user.email == controller.selectedFilterUser.value?.email;
                        return ListTile(
                          leading: CircleAvatar(child: Text(user.name.isNotEmpty ? user.name[0] : 'U')),
                          title: Text(user.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(user.email),
                          trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) : null,
                          onTap: () => controller.onUserFilterChanged(user),
                        );
                      },
                    )),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class SpeedometerKpiCard extends StatelessWidget {
  final String title;
  final int actual;
  final int target;
  final IconData icon;
  final VoidCallback onTap;

  const SpeedometerKpiCard({
    super.key,
    required this.title,
    required this.actual,
    required this.target,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double percent = (target > 0) ? (actual / target).clamp(0.0, 1.0) : 0.0;

    const LinearGradient progressGradient = LinearGradient(
      colors: [Colors.redAccent, Colors.amber, Colors.green],
      stops: [0.0, 0.5, 1.0],
      tileMode: TileMode.clamp,
    );

    Color textColor = percent < 0.4 ? Colors.redAccent : (percent < 0.8 ? Colors.amber.shade800 : Colors.green);

    return Card(
      elevation: 2,
      shadowColor: textColor.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: Colors.grey[700]),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CircularPercentIndicator(
                radius: 60.0,
                lineWidth: 12.0,
                percent: percent,
                animation: true,
                arcType: ArcType.HALF,
                startAngle: 270,
                circularStrokeCap: CircularStrokeCap.round,
                linearGradient: progressGradient,
                backgroundColor: Colors.grey.shade200,
                center: Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("$actual", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24.0, color: textColor)),
                      const Text("Actual", style: TextStyle(fontSize: 10.0, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: Text("Target: $target", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.0, color: Colors.grey.shade700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}