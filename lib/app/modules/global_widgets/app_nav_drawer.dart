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
        elevation: 0, // Remove default elevation for cleaner look
        backgroundColor: Colors.white,
        child: Column(
          children: [
            // 1. User Header
            Obx(() {
              final user = authController.currentUser.value;
              return UserAccountsDrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  // Optional: Add a subtle pattern or gradient here if desired
                  image: const DecorationImage(
                    image: AssetImage('lib/assets/images/logo.jpg'),
                    fit: BoxFit.cover,
                    opacity: 0.15, // Dim background image for better text contrast
                  ),
                ),
                accountName: Text(
                  user?.name ?? 'Guest',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                accountEmail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.email ?? 'Not logged in', style: const TextStyle(color: Colors.white70)),
                    if (user?.designation != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24, width: 0.5),
                        ),
                        child: Text(
                          user!.designation!,
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ]
                  ],
                ),
                currentAccountPicture: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: CircleAvatar(
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
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                children: [
                  _DrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    isSelected: homeController.selectedDrawerIndex.value == 0,
                    onTap: homeController.goToHome,
                  ),
                  _DrawerItem(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'To Do',
                    isSelected: homeController.selectedDrawerIndex.value == 6,
                    onTap: homeController.goToToDo,
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(height: 1, color: Colors.grey.shade200),
                  ),

                  // --- STOCK MODULE ---
                  _ModuleGroup(
                    title: 'Stock',
                    icon: Icons.inventory_2_rounded,
                    roles: const ['Stock Manager', 'Stock User', 'Item Manager', 'Sales User'],
                    children: [
                      _DrawerItem(
                        title: 'Item Master',
                        icon: Icons.category_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 7,
                        onTap: homeController.goToItem,
                        roles: const ['Stock Manager', 'Item Manager'],
                      ),
                      _DrawerItem(
                        title: 'Stock Entry',
                        icon: Icons.compare_arrows_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 1,
                        onTap: homeController.goToStockEntry,
                        roles: const ['Stock Manager', 'Stock User'],
                      ),
                      _DrawerItem(
                        title: 'Delivery Note',
                        icon: Icons.local_shipping_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 2,
                        onTap: homeController.goToDeliveryNote,
                        roles: const ['Stock Manager', 'Stock User', 'Sales User'],
                      ),
                      _DrawerItem(
                        title: 'Packing Slip',
                        icon: Icons.assignment_return_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 3,
                        onTap: homeController.goToPackingSlip,
                        roles: const ['Stock Manager', 'Stock User'],
                      ),
                    ],
                  ),

                  // --- BUYING MODULE ---
                  _ModuleGroup(
                    title: 'Buying',
                    icon: Icons.shopping_bag_rounded,
                    roles: const ['Stock Manager', 'Purchase User'],
                    children: [
                      _DrawerItem(
                        title: 'Purchase Order',
                        icon: Icons.description_rounded,
                        isSelected: false,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.PURCHASE_ORDER);
                        },
                      ),
                      _DrawerItem(
                        title: 'Purchase Receipt',
                        icon: Icons.receipt_long_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 4,
                        onTap: homeController.goToPurchaseReceipt,
                      ),
                    ],
                  ),

                  // --- MANUFACTURING MODULE ---
                  _ModuleGroup(
                    title: 'Manufacturing',
                    icon: Icons.precision_manufacturing_rounded,
                    roles: const ['Manufacturing Manager', 'Production Manager', 'System Manager'],
                    children: [
                      _DrawerItem(
                        title: 'Bill of Materials',
                        icon: Icons.account_tree_rounded,
                        isSelected: false,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.BOM);
                        },
                      ),
                      _DrawerItem(
                        title: 'Work Order',
                        icon: Icons.assignment_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 8,
                        onTap: homeController.goToWorkOrder,
                      ),
                      _DrawerItem(
                        title: 'Job Card',
                        icon: Icons.assignment_ind_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 9,
                        onTap: homeController.goToJobCard,
                      ),
                    ],
                  ),

                  // --- RETAIL MODULE ---
                  _ModuleGroup(
                    title: 'Selling',
                    icon: Icons.storefront_rounded,
                    roles: const ['Sales User', 'Accounts User', 'Stock Manager'],
                    children: [
                      _DrawerItem(
                        title: 'POS Upload',
                        icon: Icons.cloud_upload_rounded,
                        isSelected: homeController.selectedDrawerIndex.value == 5,
                        onTap: homeController.goToPosUpload,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Footer
            Divider(height: 1, color: Colors.grey.shade200),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 22),
              title: Text('Logout', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600)),
              onTap: () {
                Get.back();
                authController.logoutUser();
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Version 1.0.0+1',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.w500),
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
          leading: Icon(icon, color: Colors.grey.shade700, size: 22),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          iconColor: Theme.of(context).primaryColor,
          textColor: Theme.of(context).primaryColor,
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
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    final item = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16), // Rounded Pill Shape
          splashColor: primaryColor.withValues(alpha: 0.1),
          highlightColor: primaryColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              // Subtle border for active items for better definition
              border: isSelected
                  ? Border.all(color: primaryColor.withValues(alpha: 0.15), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              leading: Icon(
                icon,
                size: 24,
                color: isSelected ? primaryColor : Colors.grey.shade600,
              ),
              title: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? primaryColor : Colors.grey.shade800,
                  letterSpacing: 0.2, // Improved readability
                ),
              ),
              // Optional: Add a small indicator for selected items
              trailing: isSelected
                  ? Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              )
                  : null,
            ),
          ),
        ),
      ),
    );

    if (roles != null) {
      return RoleGuard(roles: roles!, child: item);
    }
    return item;
  }
}