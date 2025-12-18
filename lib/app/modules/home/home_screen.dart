import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/home/widgets/performance_timeline_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Dashboard", style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
              GlobalSnackbar.info(title: 'Notifications', message: 'No new notifications');
            },
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await controller.fetchDashboardData();
                await controller.fetchPerformanceData();
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUserContextCard(context),
                    const SizedBox(height: 24),

                    // 1. Quick Access Grid (Revamped from Bottom Sheet)
                    Text('Quick Access', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildQuickAccessGrid(context),

                    const SizedBox(height: 24),

                    // 2. Timeline
                    Obx(() => PerformanceTimelineCard(
                      viewMode: controller.timelineViewMode.value,
                      onToggleView: controller.toggleTimelineView,
                      data: controller.timelineData,
                      isLoading: controller.isLoadingTimeline.value,
                      selectedDate: controller.timelineViewMode.value != 'Weekly'
                          ? controller.selectedDailyDate.value
                          : null,
                      selectedRange: controller.timelineViewMode.value == 'Weekly'
                          ? controller.selectedWeeklyRange.value
                          : null,
                      onDateChanged: controller.onDailyDateChanged,
                      onRangeChanged: controller.onWeeklyRangeChanged,
                    )),

                    const SizedBox(height: 24),

                    // 3. KPIs
                    Text('Daily Goals', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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

          // Persistent Scan Input
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Obx(() => BarcodeInputWidget(
              onScan: controller.onScan,
              controller: controller.barcodeController,
              isLoading: controller.isScanning.value,
              hintText: 'Scan Item / Batch / Rack',
              activeRoute: AppRoutes.HOME,
            )),
          ),
        ],
      ),
      // Dedicated Scan Button
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () => controller.barcodeController.clear(), // Focus scan logic
      //   backgroundColor: theme.primaryColor,
      //   child: const Icon(Icons.qr_code_scanner, size: 28),
      // ),
    );
  }

  // New: Grid for immediate access to modules
  Widget _buildQuickAccessGrid(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = (constraints.maxWidth - 24) / 3; // 3 items per row
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildQuickActionItem(context, 'Stock\nEntry', Icons.compare_arrows_outlined, Colors.orange, itemWidth,
                      () => Get.toNamed(AppRoutes.STOCK_ENTRY, arguments: {'openCreate': true})),
              _buildQuickActionItem(context, 'Delivery\nNote', Icons.local_shipping_outlined, Colors.blue, itemWidth,
                      () => Get.toNamed(AppRoutes.DELIVERY_NOTE, arguments: {'openCreate': true})),
              _buildQuickActionItem(context, 'Receipt\nEntry', Icons.receipt_long_outlined, Colors.green, itemWidth,
                      () => Get.toNamed(AppRoutes.PURCHASE_RECEIPT, arguments: {'openCreate': true})),
              _buildQuickActionItem(context, 'Packing\nSlip', Icons.assignment_return_outlined, Colors.purple, itemWidth,
                      () => Get.toNamed(AppRoutes.PACKING_SLIP, arguments: {'openCreate': true})),
              _buildQuickActionItem(context, 'Fulfilment\nPOS', Icons.shopping_bag_outlined, Colors.deepPurple, itemWidth,
                      () => _showFulfillmentSelectionSheet(context)),
              _buildQuickActionItem(context, 'More\nActions', Icons.grid_view, Colors.grey, itemWidth,
                      () => { GlobalSnackbar.info(message: 'Stay tuned for more features') }), // Placeholder for expanded menu
            ],
          );
        }
    );
  }

  Widget _buildQuickActionItem(BuildContext context, String title, IconData icon, Color color, double width, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... (Keep existing _showFulfillmentSelectionSheet, _buildUserContextCard, _showUserSearchModal, SpeedometerKpiCard)
  // [Code truncated for brevity as logic remains similar, focus is on new UI structure]

  void _showFulfillmentSelectionSheet(BuildContext context) {
    controller.fetchFulfillmentPosUploads();
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Select POS Upload', style: Theme.of(context).textTheme.titleLarge),
                        IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      onChanged: controller.filterFulfillmentList,
                      decoration: const InputDecoration(
                        hintText: 'Search uploads...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Obx(() {
                      if (controller.isFetchingFulfillmentList.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (controller.fulfillmentPosUploads.isEmpty) {
                        return const Center(child: Text('No Pending/In Progress Uploads found.'));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: controller.fulfillmentPosUploads.length,
                        separatorBuilder: (c, i) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final pos = controller.fulfillmentPosUploads[index];
                          return ListTile(
                            title: Text(pos.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pos.customer),
                                Text(FormattingHelper.getRelativeTime(pos.modified), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: pos.status == 'Pending' ? Colors.orange.shade50 : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: pos.status == 'Pending' ? Colors.orange.shade200 : Colors.blue.shade200),
                              ),
                              child: Text(pos.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: pos.status == 'Pending' ? Colors.orange.shade800 : Colors.blue.shade800)),
                            ),
                            onTap: () => controller.handleFulfillmentSelection(pos),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
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