/// Manufacturing Module - Single Import File
/// 
/// Import this file to access all manufacturing features:
/// ```dart
/// import 'package:multimax/app/modules/manufacturing/manufacturing_module.dart';
/// ```

library manufacturing_module;

// Export all models
export 'models/bom_model.dart';
export 'models/work_order_model.dart';
export 'models/job_card_model.dart';

// Export all controllers
export 'bom/bom_controller.dart';
export 'work_order/work_order_controller.dart';
export 'job_card/job_card_controller.dart';

// Export all screens
export 'bom/bom_screen.dart';
export 'work_order/work_order_screen.dart';
export 'job_card/job_card_screen.dart';

// Export routes
export 'package:multimax/app/routes/manufacturing_routes.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Manufacturing Module Helper Class
/// 
/// Provides pre-built navigation widgets and utilities
class ManufacturingModule {
  // Route constants
  static const String bomRoute = '/manufacturing/bom';
  static const String workOrdersRoute = '/manufacturing/work-orders';
  static const String jobCardsRoute = '/manufacturing/job-cards';

  /// Navigate to Job Cards screen
  static void goToJobCards() => Get.toNamed(jobCardsRoute);

  /// Navigate to Work Orders screen
  static void goToWorkOrders() => Get.toNamed(workOrdersRoute);

  /// Navigate to BOM screen
  static void goToBom() => Get.toNamed(bomRoute);

  /// Drawer Menu Tile
  /// 
  /// Usage:
  /// ```dart
  /// Drawer(
  ///   child: ListView(
  ///     children: [
  ///       ManufacturingModule.drawerTile(),
  ///     ],
  ///   ),
  /// )
  /// ```
  static Widget drawerTile({List<String>? userRoles}) {
    // Check if user has manufacturing access
    final hasAccess = userRoles?.any((role) => 
      ['Manufacturing Manager', 'Manufacturing User', 'Supervisor', 'Labourer']
        .contains(role)
    ) ?? true;

    if (!hasAccess) return const SizedBox.shrink();

    return ExpansionTile(
      leading: const Icon(Icons.factory, size: 28, color: Colors.blue),
      title: const Text(
        'Manufacturing',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      children: [
        ListTile(
          leading: const Icon(Icons.assignment, color: Colors.blue),
          title: const Text('Job Cards'),
          subtitle: const Text('Track production tasks'),
          onTap: () {
            Get.back(); // Close drawer
            goToJobCards();
          },
        ),
        ListTile(
          leading: const Icon(Icons.work, color: Colors.orange),
          title: const Text('Work Orders'),
          subtitle: const Text('Manage production orders'),
          onTap: () {
            Get.back();
            goToWorkOrders();
          },
        ),
        ListTile(
          leading: const Icon(Icons.description, color: Colors.green),
          title: const Text('Bill of Materials'),
          subtitle: const Text('View product recipes'),
          onTap: () {
            Get.back();
            goToBom();
          },
        ),
      ],
    );
  }

  /// Dashboard Cards
  /// 
  /// Usage:
  /// ```dart
  /// GridView.count(
  ///   crossAxisCount: 2,
  ///   children: ManufacturingModule.dashboardCards(),
  /// )
  /// ```
  static List<Widget> dashboardCards({List<String>? userRoles}) {
    final isLabourer = userRoles?.contains('Labourer') ?? false;
    final hasFullAccess = userRoles?.any((role) => 
      ['Manufacturing Manager', 'Manufacturing User', 'Supervisor'].contains(role)
    ) ?? true;

    return [
      // Job Cards - visible to all
      _DashboardCard(
        icon: Icons.assignment,
        title: 'Job Cards',
        subtitle: '${isLabourer ? "My" : "All"} Tasks',
        color: Colors.blue,
        onTap: goToJobCards,
      ),

      // Work Orders - visible to all
      if (hasFullAccess || isLabourer)
        _DashboardCard(
          icon: Icons.work,
          title: 'Work Orders',
          subtitle: 'Production Orders',
          color: Colors.orange,
          onTap: goToWorkOrders,
        ),

      // BOM - only for managers/users
      if (hasFullAccess)
        _DashboardCard(
          icon: Icons.description,
          title: 'BOMs',
          subtitle: 'Product Recipes',
          color: Colors.green,
          onTap: goToBom,
        ),
    ];
  }

  /// Bottom Navigation Bar Item
  /// 
  /// Usage:
  /// ```dart
  /// BottomNavigationBar(
  ///   items: [
  ///     // ... other items
  ///     ManufacturingModule.bottomNavItem(),
  ///   ],
  /// )
  /// ```
  static BottomNavigationBarItem bottomNavItem() {
    return const BottomNavigationBarItem(
      icon: Icon(Icons.factory),
      activeIcon: Icon(Icons.factory, size: 32),
      label: 'Production',
      tooltip: 'Manufacturing',
    );
  }

  /// Floating Action Button
  /// 
  /// Quick access to Job Cards (for labourers)
  /// 
  /// Usage:
  /// ```dart
  /// Scaffold(
  ///   floatingActionButton: ManufacturingModule.fab(),
  /// )
  /// ```
  static Widget fab({bool showForLabourers = true}) {
    if (!showForLabourers) return const SizedBox.shrink();

    return FloatingActionButton.extended(
      onPressed: goToJobCards,
      icon: const Icon(Icons.assignment),
      label: const Text('My Jobs'),
      backgroundColor: Colors.blue,
    );
  }
}

/// Internal Dashboard Card Widget
class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.8),
                color,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}