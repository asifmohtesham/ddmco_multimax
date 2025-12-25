import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    final AuthenticationController authController = Get.find<AuthenticationController>();
    final String currentRoute = Get.currentRoute;

    // Reusable Skeleton Instance
    const skeleton = _SkeletonDrawerItem();

    return SafeArea(
      child: Drawer(
        elevation: 0,
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
                ),
                accountName: Text(
                  user?.name ?? 'Guest',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                accountEmail: Text(user?.email ?? 'Not logged in', style: const TextStyle(color: Colors.white70)),
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
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                children: [
                  _DrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    isSelected: currentRoute == AppRoutes.HOME,
                    onTap: homeController.goToHome,
                  ),

                  DocTypeGuard(
                    doctype: 'ToDo',
                    loading: skeleton,
                    child: _DrawerItem(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'To Do',
                      isSelected: currentRoute == AppRoutes.TODO,
                      onTap: homeController.goToToDo,
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(height: 1, color: Colors.grey.shade200),
                  ),

                  // --- STOCK MODULE ---
                  _ModuleGroup(
                    title: 'Stock',
                    icon: Icons.inventory_2_rounded,
                    initiallyExpanded: [
                      AppRoutes.ITEM,
                      AppRoutes.BATCH,
                      AppRoutes.STOCK_ENTRY,
                      AppRoutes.MATERIAL_REQUEST
                    ].contains(currentRoute),
                    children: [
                      DocTypeGuard(doctype: 'Item', loading: skeleton, child: _DrawerItem(title: 'Item Master', icon: Icons.category_rounded, isSelected: currentRoute == AppRoutes.ITEM, onTap: homeController.goToItem)),
                      DocTypeGuard(doctype: 'Batch', loading: skeleton, child: _DrawerItem(title: 'Batch', icon: Icons.qr_code_scanner_rounded, isSelected: currentRoute == AppRoutes.BATCH, onTap: homeController.goToBatch)),
                      DocTypeGuard(doctype: 'Material Request', loading: skeleton, child: _DrawerItem(
                          title: 'Material Request',
                          icon: Icons.playlist_add_check_rounded,
                          isSelected: currentRoute == AppRoutes.MATERIAL_REQUEST,
                          onTap: () { Get.back(); Get.toNamed(AppRoutes.MATERIAL_REQUEST); }
                      )),
                      DocTypeGuard(doctype: 'Stock Entry', loading: skeleton, child: _DrawerItem(title: 'Stock Entry', icon: Icons.compare_arrows_rounded, isSelected: currentRoute == AppRoutes.STOCK_ENTRY, onTap: homeController.goToStockEntry)),
                      DocTypeGuard(doctype: 'Delivery Note', loading: skeleton, child: _DrawerItem(title: 'Delivery Note', icon: Icons.local_shipping_rounded, isSelected: currentRoute == AppRoutes.DELIVERY_NOTE, onTap: homeController.goToDeliveryNote)),
                      DocTypeGuard(doctype: 'Packing Slip', loading: skeleton, child: _DrawerItem(title: 'Packing Slip', icon: Icons.assignment_return_rounded, isSelected: currentRoute == AppRoutes.PACKING_SLIP, onTap: homeController.goToPackingSlip)),
                    ],
                  ),

                  // --- BUYING MODULE ---
                  _ModuleGroup(
                    title: 'Buying',
                    icon: Icons.shopping_bag_rounded,
                    initiallyExpanded: [AppRoutes.PURCHASE_ORDER, AppRoutes.PURCHASE_RECEIPT].contains(currentRoute),
                    children: [
                      DocTypeGuard(doctype: 'Purchase Order', loading: skeleton, child: _DrawerItem(
                        title: 'Purchase Order',
                        icon: Icons.description_rounded,
                        isSelected: currentRoute == AppRoutes.PURCHASE_ORDER,
                        onTap: () { Get.back(); Get.toNamed(AppRoutes.PURCHASE_ORDER); },
                      )),
                      DocTypeGuard(doctype: 'Purchase Receipt', loading: skeleton, child: _DrawerItem(
                        title: 'Purchase Receipt',
                        icon: Icons.receipt_long_rounded,
                        isSelected: currentRoute == AppRoutes.PURCHASE_RECEIPT,
                        onTap: homeController.goToPurchaseReceipt,
                      )),
                    ],
                  ),

                  // --- MANUFACTURING MODULE ---
                  _ModuleGroup(
                    title: 'Manufacturing',
                    icon: Icons.precision_manufacturing_rounded,
                    initiallyExpanded: [AppRoutes.BOM, AppRoutes.WORK_ORDER, AppRoutes.JOB_CARD].contains(currentRoute),
                    children: [
                      DocTypeGuard(doctype: 'BOM', loading: skeleton, child: _DrawerItem(
                        title: 'Bill of Materials',
                        icon: Icons.account_tree_rounded,
                        isSelected: currentRoute == AppRoutes.BOM,
                        onTap: () { Get.back(); Get.toNamed(AppRoutes.BOM); },
                      )),
                      DocTypeGuard(doctype: 'Work Order', loading: skeleton, child: _DrawerItem(title: 'Work Order', icon: Icons.assignment_rounded, isSelected: currentRoute == AppRoutes.WORK_ORDER, onTap: homeController.goToWorkOrder)),
                      DocTypeGuard(doctype: 'Job Card', loading: skeleton, child: _DrawerItem(title: 'Job Card', icon: Icons.assignment_ind_rounded, isSelected: currentRoute == AppRoutes.JOB_CARD, onTap: homeController.goToJobCard)),
                    ],
                  ),

                  // --- RETAIL MODULE ---
                  _ModuleGroup(
                    title: 'Selling',
                    icon: Icons.storefront_rounded,
                    initiallyExpanded: [AppRoutes.POS_UPLOAD].contains(currentRoute),
                    children: [
                      DocTypeGuard(doctype: 'POS Upload', loading: skeleton, child: _DrawerItem(title: 'POS Upload', icon: Icons.cloud_upload_rounded, isSelected: currentRoute == AppRoutes.POS_UPLOAD, onTap: homeController.goToPosUpload)),
                    ],
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Get.back(); // Close drawer
                Get.toNamed(AppRoutes.ABOUT);
              },
            ),

            // ... (Rest of existing footer code)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(height: 1),
            ),
            _DrawerItem(
              icon: Icons.settings,
              title: 'Settings & Defaults',
              isSelected: false,
              onTap: () {
                Get.back();
                homeController.openSessionDefaults();
              },
            ),

            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 22),
              title: Text('Logout', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600)),
              onTap: () {
                Get.back();
                authController.logoutUser();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ... (Rest of existing helper classes: _SkeletonDrawerItem, _ModuleGroup, _DrawerItem)
class _SkeletonDrawerItem extends StatelessWidget {
  const _SkeletonDrawerItem();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(width: 24, height: 24, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 16),
            Container(width: 120, height: 12, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4))),
          ],
        ),
      ),
    );
  }
}

class _ModuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _ModuleGroup({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: Colors.grey.shade700, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: Theme.of(context).primaryColor,
        textColor: Theme.of(context).primaryColor,
        children: children,
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: primaryColor.withValues(alpha: 0.1),
          highlightColor: primaryColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: isSelected ? Border.all(color: primaryColor.withValues(alpha: 0.15), width: 1) : Border.all(color: Colors.transparent, width: 1),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              leading: Icon(icon, size: 24, color: isSelected ? primaryColor : Colors.grey.shade600),
              title: Text(title, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? primaryColor : Colors.grey.shade800, letterSpacing: 0.2)),
              trailing: isSelected ? Container(width: 6, height: 6, decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle)) : null,
            ),
          ),
        ),
      ),
    );
  }
}