/// Manufacturing Module Integration Examples
/// 
/// This file shows different ways to integrate the manufacturing module
/// into your app. Copy the relevant code to your app.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/manufacturing_module.dart';

/// Example 1: Add to Drawer Menu
/// 
/// Copy this into your main drawer/sidebar
class ExampleDrawer extends StatelessWidget {
  const ExampleDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text(
              'Menu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),

          // Your existing menu items
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () => Get.toNamed('/home'),
          ),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Inventory'),
            onTap: () => Get.toNamed('/inventory'),
          ),

          const Divider(),

          // Add Manufacturing Module
          ManufacturingModule.drawerTile(
            // Optional: Pass user roles for permission check
            userRoles: ['Manufacturing Manager', 'Supervisor'],
          ),

          const Divider(),

          // Other menu items...
        ],
      ),
    );
  }
}

/// Example 2: Dashboard with Cards
/// 
/// Copy this into your home/dashboard screen
class ExampleDashboard extends StatelessWidget {
  const ExampleDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        children: [
          // Your existing dashboard cards
          _buildCard(
            icon: Icons.dashboard,
            title: 'Overview',
            color: Colors.purple,
            onTap: () => Get.toNamed('/overview'),
          ),
          _buildCard(
            icon: Icons.shopping_cart,
            title: 'Sales',
            color: Colors.teal,
            onTap: () => Get.toNamed('/sales'),
          ),

          // Add Manufacturing Cards
          ...ManufacturingModule.dashboardCards(
            userRoles: ['Supervisor'], // Pass current user's roles
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Example 3: Bottom Navigation Bar
/// 
/// Copy this if you use bottom navigation
class ExampleBottomNav extends StatefulWidget {
  const ExampleBottomNav({super.key});

  @override
  State<ExampleBottomNav> createState() => _ExampleBottomNavState();
}

class _ExampleBottomNavState extends State<ExampleBottomNav> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const Center(child: Text('Home')),
    const Center(child: Text('Inventory')),
    const Center(child: Text('Reports')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 3) {
            // Navigate to manufacturing instead of showing in bottom nav
            ManufacturingModule.goToJobCards();
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'Inventory',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          ManufacturingModule.bottomNavItem(),
        ],
      ),
    );
  }
}

/// Example 4: Floating Action Button
/// 
/// For quick access to Job Cards (good for labourers)
class ExampleFAB extends StatelessWidget {
  const ExampleFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Production Floor')),
      body: const Center(child: Text('Main content')),
      floatingActionButton: ManufacturingModule.fab(
        showForLabourers: true, // Set based on user role
      ),
    );
  }
}

/// Example 5: Direct Navigation from Button
/// 
/// Navigate directly to specific screens
class ExampleDirectNav extends StatelessWidget {
  const ExampleDirectNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: ManufacturingModule.goToJobCards,
          child: const Text('Open Job Cards'),
        ),
        ElevatedButton(
          onPressed: ManufacturingModule.goToWorkOrders,
          child: const Text('Open Work Orders'),
        ),
        ElevatedButton(
          onPressed: ManufacturingModule.goToBom,
          child: const Text('Open BOM'),
        ),
      ],
    );
  }
}

/// Example 6: Role-Based Menu
/// 
/// Show different options based on user role
class ExampleRoleBasedMenu extends StatelessWidget {
  final List<String> userRoles;

  const ExampleRoleBasedMenu({super.key, required this.userRoles});

  @override
  Widget build(BuildContext context) {
    final isLabourer = userRoles.contains('Labourer');
    final isSupervisor = userRoles.contains('Supervisor');
    final isManager = userRoles.contains('Manufacturing Manager');

    return Column(
      children: [
        // Labourers: Only Job Cards
        if (isLabourer)
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('My Job Cards'),
            onTap: ManufacturingModule.goToJobCards,
          ),

        // Supervisors: Job Cards + Work Orders
        if (isSupervisor) ..[
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('Job Cards'),
            onTap: ManufacturingModule.goToJobCards,
          ),
          ListTile(
            leading: const Icon(Icons.work),
            title: const Text('Work Orders'),
            onTap: ManufacturingModule.goToWorkOrders,
          ),
        ],

        // Managers: Full Access
        if (isManager) ..[
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('Job Cards'),
            onTap: ManufacturingModule.goToJobCards,
          ),
          ListTile(
            leading: const Icon(Icons.work),
            title: const Text('Work Orders'),
            onTap: ManufacturingModule.goToWorkOrders,
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Bill of Materials'),
            onTap: ManufacturingModule.goToBom,
          ),
        ],
      ],
    );
  }
}

/// Example 7: Add Routes to Main App
/// 
/// In your main.dart or app_pages.dart:
/// 
/// ```dart
/// import 'package:multimax/app/routes/manufacturing_routes.dart';
/// 
/// GetMaterialApp(
///   initialRoute: '/home',
///   getPages: [
///     // Your existing routes
///     GetPage(name: '/home', page: () => HomePage()),
///     GetPage(name: '/inventory', page: () => InventoryPage()),
///     
///     // Add manufacturing routes
///     ...ManufacturingRoutes.routes,
///   ],
/// )
/// ```
