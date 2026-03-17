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
// found, regardless of nesting depth.  _ModuleGroup never needs a manually
// maintained route list — it discovers its children's routes at build time.

List<String> _extractRoutes(List<Widget> widgets) {
  final routes = <String>[];
  for (final widget in widgets) {
    if (widget is _DrawerItem) {
      routes.add(widget.route);
    } else if (widget is DocTypeGuard) {
      routes.addAll(_extractRoutes([widget.child]));
    } else if (widget is Padding) {
      routes.addAll(_extractRoutes([?widget.child]));
    } else if (widget is Column) {
      routes.addAll(_extractRoutes(widget.children));
    }
  }
  return routes;
}

// ---------------------------------------------------------------------------
// AppNavDrawerController  (drawer UI state only)
// ---------------------------------------------------------------------------
// Package-private (no leading _) so it can be registered in a Binding.
// AppNavDrawer uses Get.find() with a fallback put() so it works whether
// or not the host Binding pre-registers it.

class AppNavDrawerController extends GetxController {
  final isUserMenuOpen = false.obs;
  void toggleUserMenu() => isUserMenuOpen.toggle();
}

// ---------------------------------------------------------------------------
// AppNavDrawer
// ---------------------------------------------------------------------------

class AppNavDrawer extends StatelessWidget {
  const AppNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final homeController   = Get.find<HomeController>();
    final authController   = Get.find<AuthenticationController>();
    // Register once; subsequent builds re-use the existing instance.
    final drawerController = Get.isRegistered<AppNavDrawerController>()
        ? Get.find<AppNavDrawerController>()
        : Get.put(AppNavDrawerController());

    // Read once at build time.  The drawer is rebuilt from scratch each
    // time it opens so this is always current.
    final String currentRoute = Get.currentRoute;

    const skeleton = _SkeletonDrawerItem();

    return SafeArea(
      child: Drawer(
        elevation: 0,
        backgroundColor: Colors.white,
        child: Column(
          children: [
            // ── User header ─────────────────────────────────────────────────
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

            // ── Scrollable menu (reactive switch) ────────────────────────────
            Expanded(
              child: Obx(() {
                if (drawerController.isUserMenuOpen.value) {
                  // ---- USER MENU ----
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    children: [
                      // onTap omitted — default tap closes drawer + navigates
                      _DrawerItem(
                        icon: Icons.person_outline_rounded,
                        title: 'My Profile',
                        route: AppRoutes.PROFILE,
                        currentRoute: currentRoute,
                      ),
                      // Session Defaults has no route; needs a custom onTap
                      _DrawerItem(
                        icon: Icons.settings,
                        title: 'Session Defaults',
                        route: '',
                        currentRoute: currentRoute,
                        onTap: (ctx) {
                          Navigator.of(ctx).pop();
                          homeController.openSessionDefaults();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.info_outline,
                        title: 'About',
                        route: AppRoutes.ABOUT,
                        currentRoute: currentRoute,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Divider(height: 1),
                      ),
                      // Logout keeps a custom tile (destructive styling)
                      Builder(builder: (ctx) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          leading: Icon(Icons.logout_rounded,
                              color: Colors.red.shade400, size: 22),
                          title: Text('Logout',
                              style: TextStyle(
                                  color: Colors.red.shade600,
                                  fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            authController.logoutUser();
                          },
                        );
                      }),
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
                      currentRoute: currentRoute,
                      onTap: (ctx) {
                        Navigator.of(ctx).pop();
                        homeController.goToHome();
                      },
                    ),

                    DocTypeGuard(
                      doctype: 'ToDo',
                      loading: skeleton,
                      child: _DrawerItem(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'To Do',
                        route: AppRoutes.TODO,
                        currentRoute: currentRoute,
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
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Batch',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Batch',
                            icon: Icons.qr_code_scanner_rounded,
                            route: AppRoutes.BATCH,
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Material Request',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Material Request',
                            icon: Icons.playlist_add_check_rounded,
                            route: AppRoutes.MATERIAL_REQUEST,
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Stock Entry',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Stock Entry',
                            icon: Icons.compare_arrows_rounded,
                            route: AppRoutes.STOCK_ENTRY,
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Delivery Note',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Delivery Note',
                            icon: Icons.local_shipping_rounded,
                            route: AppRoutes.DELIVERY_NOTE,
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Packing Slip',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Packing Slip',
                            icon: Icons.assignment_return_rounded,
                            route: AppRoutes.PACKING_SLIP,
                            currentRoute: currentRoute,
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
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Purchase Receipt',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Purchase Receipt',
                            icon: Icons.receipt_long_rounded,
                            route: AppRoutes.PURCHASE_RECEIPT,
                            currentRoute: currentRoute,
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
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Work Order',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Work Order',
                            icon: Icons.assignment_rounded,
                            route: AppRoutes.WORK_ORDER,
                            currentRoute: currentRoute,
                          ),
                        ),
                        DocTypeGuard(
                          doctype: 'Job Card',
                          loading: skeleton,
                          child: _DrawerItem(
                            title: 'Job Card',
                            icon: Icons.assignment_ind_rounded,
                            route: AppRoutes.JOB_CARD,
                            currentRoute: currentRoute,
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
                            currentRoute: currentRoute,
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
// currentRoute via startsWith.  No manual route list required.

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
        leading: Icon(icon, color: Colors.grey.shade700, size: 22),
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
// [route]        — canonical list-screen route. Pass '' for items with no
//                  associated route (should never appear highlighted).
// [currentRoute] — passed in from build() so selection is determined from
//                  a single source of truth, not a silent non-reactive read.
// [onTap]        — optional override. The default behaviour is:
//                    Navigator.of(context).pop()  (closes drawer safely)
//                    Get.toNamed(route)            (navigates)
//                  Override only when additional side-effects are needed
//                  (e.g. Session Defaults, Dashboard).
//                  Signature is (BuildContext ctx) so callers can use
//                  the widget's own safe context for Navigator.of().

class _DrawerItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final String route;
  final String currentRoute;

  /// Optional tap override.  Receives the widget's [BuildContext] so
  /// Navigator.of(ctx).pop() is always available without Get.context.
  final void Function(BuildContext ctx)? onTap;

  const _DrawerItem({
    required this.title,
    required this.icon,
    required this.route,
    required this.currentRoute,
    this.onTap,
  });

  void _defaultTap(BuildContext ctx) {
    Navigator.of(ctx).pop();
    if (route.isNotEmpty) Get.toNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final isSelected =
        route.isNotEmpty && currentRoute.startsWith(route);

    final theme        = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => (onTap ?? _defaultTap)(context),
          borderRadius: BorderRadius.circular(16),
          splashColor:    primaryColor.withValues(alpha: 0.1),
          highlightColor: primaryColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                width: 1,
              ),
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
