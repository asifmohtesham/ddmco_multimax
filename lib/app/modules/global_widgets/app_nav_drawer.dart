import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';

// ---------------------------------------------------------------------------
// Route extraction helper
// ---------------------------------------------------------------------------
// Recursively walks a widget subtree and returns every _DrawerItem.route
// found, regardless of nesting depth.  This means _ModuleGroup never needs
// a manually maintained route list — it discovers its own children’s routes
// at build time.

List<String> _extractRoutes(List<Widget> widgets) {
  final routes = <String>[];
  for (final widget in widgets) {
    if (widget is _DrawerItem) {
      routes.add(widget.route);
    } else if (widget is DocTypeGuard) {
      // DocTypeGuard exposes its child; recurse into it.
      routes.addAll(_extractRoutes([widget.child]));
    } else if (widget is Padding) {
      routes.addAll(_extractRoutes([?widget.child]));
    } else if (widget is Column) {
      routes.addAll(_extractRoutes(widget.children));
    }
    // Any future transparent wrapper just falls through silently.
  }
  return routes;
}

// ---------------------------------------------------------------------------
// AppNavDrawer
// ---------------------------------------------------------------------------

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeController homeController =
        Get.find<HomeController>();
    final AuthenticationController authController =
        Get.find<AuthenticationController>();
    final _AppNavDrawerController drawerController =
        Get.put(_AppNavDrawerController());

    // Read once at build time; the drawer is rebuilt from scratch each
    // time it opens, so this is always current.
    final String currentRoute = Get.currentRoute;

    const skeleton = _SkeletonDrawerItem();

    return SafeArea(
      child: Drawer(
        elevation: 0,
        backgroundColor: Colors.white,
        child: Column(
          children: [
            // ── User header ──────────────────────────────────────────────────
            Obx(() {
              final user = authController.currentUser.value;
              return UserAccountsDrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                ),
                accountName: Text(
                  user?.name ?? 'Guest',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                accountEmail: Text(
                  user?.email ?? 'Not logged in',
                  style: const TextStyle(color: Colors.white70),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    user?.name.isNotEmpty == true
                        ? user!.name[0].toUpperCase()
                        : 'G',
                    style: TextStyle(
                      fontSize: 32.0,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                onDetailsPressed: drawerController.toggleUserMenu,
                arrowColor: Colors.white,
              );
            }),

            // ── Scrollable menu (reactive switch) ─────────────────────────────
            Expanded(
              child: Obx(() {
                if (drawerController.isUserMenuOpen.value) {
                  // ---- USER MENU ----
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    children: [
                      _DrawerItem(
                        icon: Icons.person_outline_rounded,
                        title: 'My Profile',
                        route: AppRoutes.PROFILE,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.PROFILE);
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.settings,
                        title: 'Session Defaults',
                        route: '', // no route; never highlighted
                        onTap: () {
                          Get.back();
                          homeController.openSessionDefaults();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.info_outline,
                        title: 'About',
                        route: AppRoutes.ABOUT,
                        onTap: () {
                          Get.back();
                          Get.toNamed(AppRoutes.ABOUT);
                        },
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Divider(height: 1),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        leading: Icon(Icons.logout_rounded,
                            color: Colors.red.shade400, size: 22),
                        title: Text('Logout',
                            style: TextStyle(
                                color: Colors.red.shade600,
                                fontWeight: FontWeight.w600)),
                        onTap: () {
                          Get.back();
                          authController.logoutUser();
                        },
                      ),
                    ],
                  );
                }

                // ---- MAIN MODULE MENU ----
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  children: [
                    _DrawerItem(
                      icon: Icons.dashboard_rounded,
                      title: 'Dashboard',
                      route: AppRoutes.HOME,
                      onTap: homeController.goToHome,
                    ),

                    DocTypeGuard(
                      doctype: 'ToDo',
                      loading: skeleton,
                      child: _DrawerItem(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'To Do',
                        route: AppRoutes.TODO,
                        onTap: homeController.goToToDo,
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Divider(
                          height: 1, color: Colors.grey.shade200),
                    ),

                    // ---- STOCK ----
                    _ModuleGroup(
                      title: 'Stock',
                      icon: Icons.inventory_2_rounded,
                      currentRoute: currentRoute,
                      children: [
                        DocTypeGuard(
                          doctype: 'Item',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Item Master',
                            icon: Icons.category_rounded,
                            route: AppRoutes.ITEM,
                            onTap: homeController.goToItem,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Batch',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Batch',
                            icon: Icons.qr_code_scanner_rounded,
                            route: AppRoutes.BATCH,
                            onTap: homeController.goToBatch,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Material Request',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Material Request',
                            icon: Icons.playlist_add_check_rounded,
                            route: AppRoutes.MATERIAL_REQUEST,
                            onTap: () {
                              Get.back();
                              Get.toNamed(AppRoutes.MATERIAL_REQUEST);
                            },
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Stock Entry',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Stock Entry',
                            icon: Icons.compare_arrows_rounded,
                            route: AppRoutes.STOCK_ENTRY,
                            onTap: homeController.goToStockEntry,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Delivery Note',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Delivery Note',
                            icon: Icons.local_shipping_rounded,
                            route: AppRoutes.DELIVERY_NOTE,
                            onTap: homeController.goToDeliveryNote,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Packing Slip',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Packing Slip',
                            icon: Icons.assignment_return_rounded,
                            route: AppRoutes.PACKING_SLIP,
                            onTap: homeController.goToPackingSlip,
                          ),
                        ),
                      ],
                    ),

                    // ---- BUYING ----
                    _ModuleGroup(
                      title: 'Buying',
                      icon: Icons.shopping_bag_rounded,
                      currentRoute: currentRoute,
                      children: [
                        DocTypeGuard(
                          doctype: 'Purchase Order',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Purchase Order',
                            icon: Icons.description_rounded,
                            route: AppRoutes.PURCHASE_ORDER,
                            onTap: () {
                              Get.back();
                              Get.toNamed(AppRoutes.PURCHASE_ORDER);
                            },
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Purchase Receipt',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Purchase Receipt',
                            icon: Icons.receipt_long_rounded,
                            route: AppRoutes.PURCHASE_RECEIPT,
                            onTap: homeController.goToPurchaseReceipt,
                          ),
                        ),
                      ],
                    ),

                    // ---- MANUFACTURING ----
                    _ModuleGroup(
                      title: 'Manufacturing',
                      icon: Icons.precision_manufacturing_rounded,
                      currentRoute: currentRoute,
                      children: [
                        DocTypeGuard(
                          doctype: 'BOM',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Bill of Materials',
                            icon: Icons.account_tree_rounded,
                            route: AppRoutes.BOM,
                            onTap: () {
                              Get.back();
                              Get.toNamed(AppRoutes.BOM);
                            },
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Work Order',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Work Order',
                            icon: Icons.assignment_rounded,
                            route: AppRoutes.WORK_ORDER,
                            onTap: homeController.goToWorkOrder,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Job Card',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Job Card',
                            icon: Icons.assignment_ind_rounded,
                            route: AppRoutes.JOB_CARD,
                            onTap: homeController.goToJobCard,
                          ),
                        ),
                      ],
                    ),

                    // ---- SELLING ----
                    _ModuleGroup(
                      title: 'Selling',
                      icon: Icons.storefront_rounded,
                      currentRoute: currentRoute,
                      children: [
                        DocTypeGuard(
                          doctype: 'POS Upload',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'POS Upload',
                            icon: Icons.cloud_upload_rounded,
                            route: AppRoutes.POS_UPLOAD,
                            onTap: homeController.goToPosUpload,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal GetX controller  (drawer UI state only)
// ---------------------------------------------------------------------------

class _AppNavDrawerController extends GetxController {
  final isUserMenuOpen = false.obs;
  void toggleUserMenu() => isUserMenuOpen.toggle();
}

// ---------------------------------------------------------------------------
// _SkeletonDrawerItem
// ---------------------------------------------------------------------------

class _SkeletonDrawerItem extends StatelessWidget {
  const _SkeletonDrawerItem();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 48,
        decoration:
            BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 120,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ModuleGroup
// ---------------------------------------------------------------------------
// Automatically determines whether to expand by walking its children
// subtree for _DrawerItem.route values and testing each against
// currentRoute via startsWith.  No manual route list required — adding
// a new _DrawerItem to a group is sufficient for it to participate.

class _ModuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final String currentRoute;

  const _ModuleGroup({
    required this.title,
    required this.icon,
    required this.children,
    required this.currentRoute,
  });

  /// Returns true when [currentRoute] starts with any route registered
  /// inside the children subtree.
  bool get _hasActiveChild {
    final routes = _extractRoutes(children);
    return routes.any(
      (r) => r.isNotEmpty && currentRoute.startsWith(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _hasActiveChild,
        leading:
            Icon(icon, color: Colors.grey.shade700, size: 22),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: Theme.of(context).primaryColor,
        textColor: Theme.of(context).primaryColor,
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DrawerItem
// ---------------------------------------------------------------------------
// [route] is the canonical list-screen route for this item (e.g.
// AppRoutes.DELIVERY_NOTE).  isSelected is derived via startsWith so
// that both /delivery-note and /delivery-note/form highlight the item.
// Pass route: '' for items that have no route (Session Defaults, etc.).

class _DrawerItem extends StatelessWidget {
  final String title;
  final IconData icon;

  /// The canonical route prefix for this item.  Pass '' if the item
  /// has no associated route and should never appear highlighted.
  final String route;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.title,
    required this.icon,
    required this.route,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Derive selection from the live route so form screens also
    // highlight the parent list item.
    final currentRoute = Get.currentRoute;
    final isSelected =
        route.isNotEmpty && currentRoute.startsWith(route);

    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: isSelected
                  ? Border.all(
                      color: primaryColor.withValues(alpha: 0.15),
                      width: 1)
                  : Border.all(
                      color: Colors.transparent, width: 1),
            ),
            child: ListTile(
              dense: true,
              visualDensity:
                  const VisualDensity(horizontal: 0, vertical: -1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 0),
              leading: Icon(
                icon,
                size: 24,
                color: isSelected
                    ? primaryColor
                    : Colors.grey.shade600,
              ),
              title: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected
                      ? primaryColor
                      : Colors.grey.shade800,
                  letterSpacing: 0.2,
                ),
              ),
              trailing: isSelected
                  ? Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
