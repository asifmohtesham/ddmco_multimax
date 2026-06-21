import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/services/permission_service.dart';

// ---------------------------------------------------------------------------
// Route extraction helper
// ---------------------------------------------------------------------------

List<String> _extractRoutes(List<Widget> widgets) {
  final routes = <String>[];
  for (final widget in widgets) {
    if (widget is _DrawerItem) {
      routes.add(widget.route);
    } else if (widget is DocTypeGuard) {
      routes.addAll(_extractRoutes([widget.child]));
    } else if (widget is _GuardedSection) {
      routes.addAll(_extractRoutes(widget.children));
    } else if (widget is Padding) {
      routes.addAll(_extractRoutes([?widget.child]));
    } else if (widget is Column) {
      routes.addAll(_extractRoutes(widget.children));
    }
    // _NavSubheading is purely decorative — no routes to extract.
  }
  return routes;
}

// ---------------------------------------------------------------------------
// AppNavDrawerController
// ---------------------------------------------------------------------------

class AppNavDrawerController extends GetxController {
  final isUserMenuOpen  = false.obs;
  final expandedGroups  = <String, bool>{}.obs;

  void toggleUserMenu() => isUserMenuOpen.toggle();

  bool isGroupExpanded(String title, {required bool defaultValue}) =>
      expandedGroups[title] ?? defaultValue;

  void setGroupExpanded(String title, bool value) =>
      expandedGroups[title] = value;
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
    final drawerController = Get.isRegistered<AppNavDrawerController>()
        ? Get.find<AppNavDrawerController>()
        : Get.put(AppNavDrawerController());

    final String currentRoute = Get.currentRoute;
    const skeleton = _SkeletonDrawerItem();

    return SafeArea(
      child: Drawer(
        elevation: 0,
        backgroundColor: Colors.white,
        child: Column(
          children: [
            // ── User header ──────────────────────────────────────────────────────────────
            Obx(() {
              final user   = authController.currentUser.value;
              final letter = (user?.name.isNotEmpty == true)
                  ? user!.name[0].toUpperCase()
                  : 'G';

              final parts = [
                if (user?.designation?.isNotEmpty == true) user!.designation!,
                if (user?.department?.isNotEmpty  == true) user!.department!,
              ];
              final subtitle = parts.isNotEmpty
                  ? parts.join(' · ')
                  : user?.email ?? 'Not logged in';

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
                // AFTER — add employeeId row
                accountEmail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user?.email ?? 'Not logged in',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    if (parts.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    if (user?.employeeId?.isNotEmpty == true)
                      Text(
                        'Employee: ${user!.employeeId}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                  ],
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: (user?.image?.isNotEmpty == true)
                      ? NetworkImage(user!.image!)
                      : null,
                  child: (user?.image?.isNotEmpty == true)
                      ? null
                      : Text(
                          letter,
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

            // ── Scrollable menu ────────────────────────────────────────────────────────
            Expanded(
              child: Obx(() {
                if (drawerController.isUserMenuOpen.value) {
                  // ---- USER MENU ----
                  final userMenuItems = <Widget>[
                    _DrawerItem(
                      icon: Icons.person_outline_rounded,
                      title: 'My Profile',
                      route: AppRoutes.PROFILE,
                      currentRoute: currentRoute,
                    ),
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
                    Obx(() {
                      final tc = Get.isRegistered<ThemeController>()
                          ? Get.find<ThemeController>()
                          : Get.put(ThemeController());
                      final mode = tc.themeMode.value;
                      final (icon, label) = switch (mode) {
                        ThemeMode.system => (Icons.brightness_auto_outlined, 'Theme: System'),
                        ThemeMode.light => (Icons.light_mode_outlined, 'Theme: Light'),
                        ThemeMode.dark => (Icons.dark_mode_outlined, 'Theme: Dark'),
                      };
                      return _DrawerItem(
                        icon: icon,
                        title: label,
                        route: '',
                        currentRoute: currentRoute,
                        onTap: (_) => tc.cycleThemeMode(),
                      );
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Divider(height: 1),
                    ),
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
                          HapticFeedback.lightImpact();
                          Navigator.of(ctx).pop();
                          Get.find<AuthenticationController>().logoutUser();
                        },
                      );
                    }),
                  ];
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    itemCount: userMenuItems.length,
                    itemBuilder: (_, i) => userMenuItems[i],
                  );
                }

                // ---- MAIN MODULE MENU ----
                final moduleMenuItems = <Widget>[
                  _DrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    route: AppRoutes.HOME,
                    currentRoute: currentRoute,
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
                    drawerController: drawerController,
                    guardEntries: kStockPermissions,
                    children: [
                      DocTypeGuard(
                        doctype: 'Item',
                        loading: skeleton,
                        child: _DrawerItem(
                          title: 'Item',
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
                      // ── Stock > Reports ──────────────────────────────────────
                      _GuardedSection(
                        doctypes: ['Batch', 'Item', 'Stock Entry'],
                        permType: 'report',
                        children: [
                          const _NavSubheading('Reports'),
                          DocTypeGuard(
                            doctype: 'Batch',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'Batch-Wise Balance History',
                              icon: Icons.history_toggle_off_rounded,
                              route: AppRoutes.BATCH_WISE_BALANCE,
                              currentRoute: currentRoute,
                            ),
                          ),
                          DocTypeGuard(
                            doctype: 'Item',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title:        'Item Variant Details',
                              icon:         Icons.style_outlined,
                              route:        AppRoutes.ITEM_VARIANT_DETAILS,
                              currentRoute: currentRoute,
                            ),
                          ),
                          DocTypeGuard(
                            doctype: 'Stock Entry',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title:        'Stock Balance',
                              icon:         Icons.account_balance_wallet_outlined,
                              route:        AppRoutes.STOCK_BALANCE,
                              currentRoute: currentRoute,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ---- BUYING ----
                  _ModuleGroup(
                    title: 'Buying',
                    icon: Icons.shopping_bag_rounded,
                    currentRoute: currentRoute,
                    drawerController: drawerController,
                    guardEntries: kBuyingPermissions,
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
                    drawerController: drawerController,
                    guardEntries: kManufacturingPermissions,
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
                      // ── Manufacturing > Reports ─────────────────────────────
                      _GuardedSection(
                        doctypes: ['BOM', 'Job Card'],
                        permType: 'report',
                        children: [
                          const _NavSubheading('Reports'),
                          DocTypeGuard(
                            doctype: 'BOM',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'BOM Search',
                              icon: Icons.manage_search_rounded,
                              route: AppRoutes.BOM_SEARCH,
                              currentRoute: currentRoute,
                            ),
                          ),
                          DocTypeGuard(
                            doctype: 'Job Card',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'Job Card Summary',
                              icon: Icons.summarize_outlined,
                              route: AppRoutes.JOB_CARD_SUMMARY,
                              currentRoute: currentRoute,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ---- SELLING ----
                  _ModuleGroup(
                    title: 'Selling',
                    icon: Icons.storefront_rounded,
                    currentRoute: currentRoute,
                    drawerController: drawerController,
                    guardEntries: kSellingPermissions,
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
                ];
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  itemCount: moduleMenuItems.length,
                  itemBuilder: (_, i) => moduleMenuItems[i],
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
// _SkeletonDrawerItem  — animated shimmer loading placeholder
// ---------------------------------------------------------------------------

class _SkeletonDrawerItem extends StatefulWidget {
  const _SkeletonDrawerItem();

  @override
  State<_SkeletonDrawerItem> createState() => _SkeletonDrawerItemState();
}

class _SkeletonDrawerItemState extends State<_SkeletonDrawerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final Animation<double>    _anim;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _shimmer, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final shimmerColor = Color.lerp(
            Colors.grey.shade100,
            Colors.grey.shade300,
            _anim.value,
          )!;
          return Container(
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
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ModuleGroup
// ---------------------------------------------------------------------------

class _ModuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final String currentRoute;
  final AppNavDrawerController drawerController;

  /// Every `(doctype, permType)` guarded within this group.
  /// The group hides itself when none are accessible.
  final List<PermEntry> guardEntries;

  const _ModuleGroup({
    required this.title,
    required this.icon,
    required this.children,
    required this.currentRoute,
    required this.drawerController,
    required this.guardEntries,
  });

  bool get _hasActiveChild {
    final routes = _extractRoutes(children);
    return routes.any(
      (r) => r.isNotEmpty && currentRoute.startsWith(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PermissionService>();

    return Obx(() {
      // Visible when at least one entry is accessible (true) or still
      // loading (null). Hides only when every entry is confirmed false.
      final anyAccessible = guardEntries.any(
        (e) => service.hasAccess(e.doctype, permType: e.permType) != false,
      );
      if (!anyAccessible) return const SizedBox.shrink();

      final initialExpanded =
          drawerController.isGroupExpanded(title, defaultValue: _hasActiveChild);

      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initialExpanded,
          onExpansionChanged: (v) =>
              drawerController.setGroupExpanded(title, v),
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
          iconColor:  Theme.of(context).primaryColor,
          textColor:  Theme.of(context).primaryColor,
          children: children,
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// _GuardedSection
// ---------------------------------------------------------------------------

/// A section that hides its [children] when every [doctype]+[permType]
/// combination is confirmed inaccessible. The [children] are stored as
/// a plain list so [_extractRoutes] can discover routes inside them.
class _GuardedSection extends StatelessWidget {
  final List<String> doctypes;
  final String permType;
  final List<Widget> children;

  const _GuardedSection({
    required this.doctypes,
    required this.permType,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<PermissionService>();
    return Obx(() {
      final anyAccessible = doctypes.any(
        (d) => svc.hasAccess(d, permType: permType) != false,
      );
      if (!anyAccessible) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    });
  }
}

// ---------------------------------------------------------------------------
// _NavSubheading — flat category label used inside _ModuleGroup children
// ---------------------------------------------------------------------------

/// A non-interactive label + hairline divider used to visually group
/// items inside a [_ModuleGroup] without adding another expand/collapse
/// interaction level.
///
/// Example:
/// ```dart
/// const _NavSubheading('Reports'),
/// _DrawerItem(title: 'Batch-Wise Balance History', ...),
/// ```
class _NavSubheading extends StatelessWidget {
  final String label;
  const _NavSubheading(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DrawerItem
// ---------------------------------------------------------------------------

class _DrawerItem extends StatelessWidget {
  final String   title;
  final IconData icon;
  final String   route;
  final String   currentRoute;

  final void Function(BuildContext ctx)? onTap;

  const _DrawerItem({
    required this.title,
    required this.icon,
    required this.route,
    required this.currentRoute,
    this.onTap,
  });

  void _defaultTap(BuildContext ctx) {
    HapticFeedback.lightImpact();
    Navigator.of(ctx).pop();
    if (route.isNotEmpty && Get.currentRoute != route) {
      Get.toNamed(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelected =
        route.isNotEmpty && currentRoute.startsWith(route);

    final theme        = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => (onTap ?? _defaultTap)(context),
          borderRadius: BorderRadius.circular(16),
          splashColor:    primaryColor.withValues(alpha: 0.1),
          highlightColor: primaryColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border(
                left: BorderSide(
                  color: isSelected ? primaryColor : Colors.transparent,
                  width: 3,
                ),
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
            ),
          ),
        ),
      ),
    );
  }
}
