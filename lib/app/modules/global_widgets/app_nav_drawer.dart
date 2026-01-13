import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';
import 'package:multimax/theme/frappe_theme.dart'; // Implements Espresso Design System

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();
    final AuthenticationController authController = Get.find<AuthenticationController>();
    final _AppNavDrawerController drawerController = Get.put(_AppNavDrawerController());
    final String currentRoute = Get.currentRoute;

    // Reusable Skeleton Instance
    const skeleton = _SkeletonDrawerItem();

    return SafeArea(
      child: Drawer(
        elevation: 0,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(FrappeTheme.radius),
            bottomRight: Radius.circular(FrappeTheme.radius),
          ),
        ),
        child: Column(
          children: [
            // 1. User Header (Frappe Blue Card Style)
            Obx(() {
              final user = authController.currentUser.value;
              return Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FrappeTheme.primary,
                  borderRadius: BorderRadius.circular(FrappeTheme.radius),
                  boxShadow: [
                    BoxShadow(
                      color: FrappeTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: UserAccountsDrawerHeader(
                  margin: EdgeInsets.zero,
                  decoration: const BoxDecoration(
                    color: Colors.transparent, // Handled by Container
                  ),
                  accountName: Text(
                    user?.name ?? 'Guest',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  accountEmail: Text(
                      user?.email ?? 'Not logged in',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)
                  ),
                  currentAccountPicture: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Text(
                      user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'G',
                      style: const TextStyle(
                        fontSize: 24.0,
                        fontWeight: FontWeight.bold,
                        color: FrappeTheme.primary,
                      ),
                    ),
                  ),
                  onDetailsPressed: () {
                    drawerController.toggleUserMenu();
                  },
                  arrowColor: Colors.white,
                ),
              );
            }),

            // 2. Scrollable Menu Items
            Expanded(
              child: Obx(() {
                if (drawerController.isUserMenuOpen.value) {
                  // --- USER MENU ---
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    children: [
                      _DrawerItem(
                        icon: Icons.person_outline_rounded,
                        title: 'My Profile',
                        isSelected: currentRoute == AppRoutes.PROFILE,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.PROFILE);
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.settings_outlined,
                        title: 'Session Defaults',
                        isSelected: false,
                        onTap: () {
                          Get.back();
                          homeController.openSessionDefaults();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.info_outline_rounded,
                        title: 'About',
                        isSelected: currentRoute == AppRoutes.ABOUT,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.ABOUT);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Divider(height: 1, color: Colors.grey.shade200),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FrappeTheme.radius)),
                        leading: Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 22),
                        title: Text('Logout', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600, fontSize: 14)),
                        onTap: () {
                          Get.back();
                          authController.logoutUser();
                        },
                      ),
                    ],
                  );
                } else {
                  // --- MAIN MODULE MENU ---
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
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
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
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
                          DocTypeGuard(doctype: 'Item', loading: skeleton, child: _DrawerItem(title: 'Item Master', icon: Icons.category_outlined, isSelected: currentRoute == AppRoutes.ITEM, onTap: homeController.goToItem)),
                          DocTypeGuard(doctype: 'Batch', loading: skeleton, child: _DrawerItem(title: 'Batch', icon: Icons.qr_code_scanner_rounded, isSelected: currentRoute == AppRoutes.BATCH, onTap: homeController.goToBatch)),
                          DocTypeGuard(doctype: 'Material Request', loading: skeleton, child: _DrawerItem(
                              title: 'Material Request',
                              icon: Icons.playlist_add_check_rounded,
                              isSelected: currentRoute == AppRoutes.MATERIAL_REQUEST,
                              onTap: () { Get.back(); Get.toNamed(AppRoutes.MATERIAL_REQUEST); }
                          )),
                          DocTypeGuard(doctype: 'Stock Entry', loading: skeleton, child: _DrawerItem(title: 'Stock Entry', icon: Icons.compare_arrows_rounded, isSelected: currentRoute == AppRoutes.STOCK_ENTRY, onTap: homeController.goToStockEntry)),
                          DocTypeGuard(doctype: 'Delivery Note', loading: skeleton, child: _DrawerItem(title: 'Delivery Note', icon: Icons.local_shipping_outlined, isSelected: currentRoute == AppRoutes.DELIVERY_NOTE, onTap: homeController.goToDeliveryNote)),
                          DocTypeGuard(doctype: 'Packing Slip', loading: skeleton, child: _DrawerItem(title: 'Packing Slip', icon: Icons.assignment_return_outlined, isSelected: currentRoute == AppRoutes.PACKING_SLIP, onTap: homeController.goToPackingSlip)),

                          // --- STOCK REPORTS SUBSECTION ---
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text("REPORTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: FrappeTheme.textLabel, letterSpacing: 1.2)),
                          ),
                          _DrawerItem(
                              title: 'Batch-Wise Balance',
                              icon: Icons.view_list_rounded,
                              isSelected: currentRoute == AppRoutes.BATCH_WISE_BALANCE_REPORT,
                              onTap: () { Get.back(); Get.toNamed(AppRoutes.BATCH_WISE_BALANCE_REPORT); }
                          ),
                          _DrawerItem(
                              title: 'Stock Balance',
                              icon: Icons.bar_chart_rounded,
                              isSelected: currentRoute == AppRoutes.STOCK_BALANCE_REPORT,
                              onTap: () { Get.back(); Get.toNamed(AppRoutes.STOCK_BALANCE_REPORT); }
                          ),
                          _DrawerItem(
                              title: 'Stock Ledger',
                              icon: Icons.history_edu_rounded,
                              isSelected: currentRoute == AppRoutes.STOCK_LEDGER_REPORT,
                              onTap: () { Get.back(); Get.toNamed(AppRoutes.STOCK_LEDGER_REPORT); }
                          ),
                        ],
                      ),

                      // --- BUYING MODULE ---
                      _ModuleGroup(
                        title: 'Buying',
                        icon: Icons.shopping_bag_outlined,
                        initiallyExpanded: [AppRoutes.PURCHASE_ORDER, AppRoutes.PURCHASE_RECEIPT].contains(currentRoute),
                        children: [
                          DocTypeGuard(doctype: 'Purchase Order', loading: skeleton, child: _DrawerItem(
                            title: 'Purchase Order',
                            icon: Icons.description_outlined,
                            isSelected: currentRoute == AppRoutes.PURCHASE_ORDER,
                            onTap: () { Get.back(); Get.toNamed(AppRoutes.PURCHASE_ORDER); },
                          )),
                          DocTypeGuard(doctype: 'Purchase Receipt', loading: skeleton, child: _DrawerItem(
                            title: 'Purchase Receipt',
                            icon: Icons.receipt_long_outlined,
                            isSelected: currentRoute == AppRoutes.PURCHASE_RECEIPT,
                            onTap: homeController.goToPurchaseReceipt,
                          )),
                        ],
                      ),

                      // --- MANUFACTURING MODULE ---
                      _ModuleGroup(
                        title: 'Manufacturing',
                        icon: Icons.precision_manufacturing_outlined,
                        initiallyExpanded: [AppRoutes.BOM, AppRoutes.WORK_ORDER, AppRoutes.JOB_CARD].contains(currentRoute),
                        children: [
                          DocTypeGuard(doctype: 'BOM', loading: skeleton, child: _DrawerItem(
                            title: 'Bill of Materials',
                            icon: Icons.account_tree_outlined,
                            isSelected: currentRoute == AppRoutes.BOM,
                            onTap: () { Get.back(); Get.toNamed(AppRoutes.BOM); },
                          )),
                          DocTypeGuard(doctype: 'Work Order', loading: skeleton, child: _DrawerItem(title: 'Work Order', icon: Icons.assignment_outlined, isSelected: currentRoute == AppRoutes.WORK_ORDER, onTap: homeController.goToWorkOrder)),
                          DocTypeGuard(doctype: 'Job Card', loading: skeleton, child: _DrawerItem(title: 'Job Card', icon: Icons.assignment_ind_outlined, isSelected: currentRoute == AppRoutes.JOB_CARD, onTap: homeController.goToJobCard)),
                        ],
                      ),

                      // --- POS MODULE ---
                      _ModuleGroup(
                        title: 'Selling',
                        icon: Icons.storefront_outlined,
                        initiallyExpanded: [AppRoutes.POS_UPLOAD].contains(currentRoute),
                        children: [
                          DocTypeGuard(doctype: 'POS Upload', loading: skeleton, child: _DrawerItem(title: 'POS Upload', icon: Icons.cloud_upload_outlined, isSelected: currentRoute == AppRoutes.POS_UPLOAD, onTap: homeController.goToPosUpload)),
                        ],
                      ),

                      const SizedBox(height: 24),
                    ],
                  );
                }
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppNavDrawerController extends GetxController {
  final isUserMenuOpen = false.obs;
  void toggleUserMenu() => isUserMenuOpen.toggle();
}

class _SkeletonDrawerItem extends StatelessWidget {
  const _SkeletonDrawerItem();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(FrappeTheme.radius),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6))),
            const SizedBox(width: 16),
            Container(width: 100, height: 10, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
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
        leading: Icon(icon, color: FrappeTheme.textLabel, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: FrappeTheme.textBody)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: FrappeTheme.primary,
        textColor: FrappeTheme.primary,
        collapsedIconColor: FrappeTheme.textLabel,
        shape: const Border(), // Removes borders
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), // Tighter spacing
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FrappeTheme.radius),
          splashColor: FrappeTheme.primary.withValues(alpha: 0.1),
          highlightColor: FrappeTheme.primary.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected ? FrappeTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(FrappeTheme.radius),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: 0, vertical: -2), // Compact
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FrappeTheme.radius)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              leading: Icon(
                  icon,
                  size: 20, // Smaller icons for elegance
                  color: isSelected ? FrappeTheme.primary : FrappeTheme.textLabel
              ),
              title: Text(
                  title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? FrappeTheme.primary : FrappeTheme.textBody,
                      letterSpacing: 0.2
                  )
              ),
              trailing: isSelected
                  ? Container(width: 6, height: 6, decoration: const BoxDecoration(color: FrappeTheme.primary, shape: BoxShape.circle))
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}