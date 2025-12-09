import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    final AuthenticationController authController = Get.find<AuthenticationController>();

    return SafeArea(
      child: Drawer(
        child: Column(
          children: [
            // 1. User Header
            Obx(() {
              final user = authController.currentUser.value;
              return UserAccountsDrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  image: DecorationImage(
                    image: const AssetImage('lib/assets/images/logo.jpg'),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Theme.of(context).primaryColor.withValues(alpha:0.9), BlendMode.multiply),
                  ),
                ),
                accountName: Text(
                  user?.name ?? 'Guest',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                accountEmail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.email ?? 'Not logged in'),
                    if (user?.designation != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          user!.designation!,
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ]
                  ],
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'G',
                    style: TextStyle(
                      fontSize: 32.0,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                onDetailsPressed: () {
                  Get.back();
                  Get.toNamed(AppRoutes.PROFILE);
                },
              );
            }),

            // 2. Scrollable Menu Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                children: [
                  _DrawerItem(
                    icon: Icons.dashboard_outlined,
                    title: 'Dashboard',
                    isSelected: homeController.selectedDrawerIndex.value == 0,
                    onTap: homeController.goToHome,
                  ),
                  _DrawerItem(
                    icon: Icons.check_circle_outline,
                    title: 'To Do',
                    isSelected: homeController.selectedDrawerIndex.value == 6,
                    onTap: homeController.goToToDo,
                  ),

                  const Divider(indent: 16, endIndent: 16),

                  // --- STOCK MODULE ---
                  _ModuleGroup(
                    title: 'Stock',
                    icon: Icons.inventory_2_outlined,
                    // Roles that can access at least one stock feature
                    roles: const ['Stock Manager', 'Stock User', 'Item Manager', 'Sales User'],
                    children: [
                      _DrawerItem(
                        title: 'Item Master',
                        icon: Icons.category_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 7,
                        onTap: homeController.goToItem,
                        roles: const ['Stock Manager', 'Item Manager'],
                      ),
                      _DrawerItem(
                        title: 'Stock Entry',
                        icon: Icons.compare_arrows_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 1,
                        onTap: homeController.goToStockEntry,
                        roles: const ['Stock Manager', 'Stock User'],
                      ),
                      _DrawerItem(
                        title: 'Delivery Note',
                        icon: Icons.local_shipping_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 2,
                        onTap: homeController.goToDeliveryNote,
                        roles: const ['Stock Manager', 'Stock User', 'Sales User'],
                      ),
                      _DrawerItem(
                        title: 'Packing Slip',
                        icon: Icons.assignment_return_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 3,
                        onTap: homeController.goToPackingSlip,
                        roles: const ['Stock Manager', 'Stock User'],
                      ),
                    ],
                  ),

                  // --- BUYING MODULE ---
                  _ModuleGroup(
                    title: 'Buying',
                    icon: Icons.shopping_bag_outlined,
                    roles: const ['Stock Manager', 'Purchase User'],
                    children: [
                      _DrawerItem(
                        title: 'Purchase Order',
                        icon: Icons.description_outlined,
                        isSelected: false, // Index logic to be added in controller if needed
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.PURCHASE_ORDER);
                        },
                      ),
                      _DrawerItem(
                        title: 'Purchase Receipt',
                        icon: Icons.receipt_long_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 4,
                        onTap: homeController.goToPurchaseReceipt,
                      ),
                    ],
                  ),

                  // --- MANUFACTURING MODULE ---
                  _ModuleGroup(
                    title: 'Manufacturing',
                    icon: Icons.precision_manufacturing_outlined,
                    roles: const ['Manufacturing Manager', 'Production Manager', 'System Manager'],
                    children: [
                      _DrawerItem(
                        title: 'Bill of Materials',
                        icon: Icons.account_tree_outlined,
                        isSelected: false,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.BOM);
                        },
                      ),
                      _DrawerItem(
                        title: 'Work Order',
                        icon: Icons.assignment_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 8, // Assuming added
                        onTap: homeController.goToWorkOrder,
                      ),
                      _DrawerItem(
                        title: 'Job Card',
                        icon: Icons.assignment_ind_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 9, // Assuming added
                        onTap: homeController.goToJobCard,
                      ),
                    ],
                  ),

                  // --- RETAIL MODULE ---
                  _ModuleGroup(
                    title: 'Selling',
                    icon: Icons.storefront_outlined,
                    roles: const ['Sales User', 'Accounts User', 'Stock Manager'],
                    children: [
                      _DrawerItem(
                        title: 'POS Upload',
                        icon: Icons.cloud_upload_outlined,
                        isSelected: homeController.selectedDrawerIndex.value == 5,
                        onTap: homeController.goToPosUpload,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Footer
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () {
                Get.back();
                authController.logoutUser();
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Version 1.0.0+1',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Helper Widgets for Cleaner Code ---

class _ModuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> roles;
  final List<Widget> children;

  const _ModuleGroup({
    required this.title,
    required this.icon,
    required this.roles,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      roles: roles,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: Colors.grey.shade700),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          childrenPadding: const EdgeInsets.only(left: 16),
          children: children,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final List<String>? roles;

  const _DrawerItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.roles,
  });

  @override
  Widget build(BuildContext context) {
    final item = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).primaryColor.withValues(alpha:0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
        leading: Icon(
          icon,
          size: 22,
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade600,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).primaryColor : Colors.black87,
          ),
        ),
        onTap: onTap,
      ),
    );

    if (roles != null) {
      return RoleGuard(roles: roles!, child: item);
    }
    return item;
  }
}