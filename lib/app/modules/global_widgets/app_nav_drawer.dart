import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

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
  final expandedGroups  = <String, bool>{}.obs;

  /// Module groups, laid out by the user's Frappe workspaces. Starts as (and
  /// falls back to) the built-in layout until [loadFor] succeeds.
  final groups = buildWorkspaceMenu(const [], const {}).obs;
  String? _loadedFor;
  DateTime? _loadedAt;
  AppLifecycleListener? _lifecycle;

  /// Workspace edits made in Desk show up on the next resume after this.
  static const _staleAfter = Duration(minutes: 30);

  @override
  void onInit() {
    super.onInit();
    _lifecycle = AppLifecycleListener(onResume: () {
      final user = _loadedFor, at = _loadedAt;
      if (user == null || at == null) return;
      if (DateTime.now().difference(at) < _staleAfter) return;
      _loadedFor = null;
      loadFor(user);
    });
  }

  @override
  void onClose() {
    _lifecycle?.dispose();
    super.onClose();
  }

  static AppNavDrawerController get instance =>
      Get.isRegistered<AppNavDrawerController>()
          ? Get.find<AppNavDrawerController>()
          : Get.put(AppNavDrawerController(), permanent: true);

  /// Loads [user]'s workspaces once (sidebar + each page's links, both
  /// permission-filtered by Frappe). Failure keeps the current menu and
  /// retries on the next call.
  Future<void> loadFor(String? user) async {
    if (user == null || user == _loadedFor) return;
    _loadedFor = user;
    final storage =
        Get.isRegistered<StorageService>() ? Get.find<StorageService>() : null;
    // Last session's layout first, so the drawer never reshuffles on start
    // (or offline); the fetch below refreshes it.
    groups.value = menuFromJson(storage?.getNavMenu(user)) ??
        buildWorkspaceMenu(const [], const {});
    try {
      final api = Get.find<ApiProvider>();
      final res = await api
          .callMethod('frappe.desk.desktop.get_workspace_sidebar_items');
      final pages = [
        for (final p in (res.data['message']?['pages'] as List? ?? const []))
          Map<String, dynamic>.from(p as Map)
      ].where((p) => p['is_hidden'] != 1).toList();
      final desktop = <String, Map<String, dynamic>>{};
      final modules = <String, String>{};
      await Future.wait([
        ...pages.map((p) async {
          try {
            final r = await api.callMethod('frappe.desk.desktop.get_desktop_page',
                params: {
                  'page': jsonEncode(
                      {'name': p['name'], 'title': p['title'], 'public': p['public']})
                });
            final m = r.data['message'];
            if (m is Map) desktop[p['name'] as String] = Map<String, dynamic>.from(m);
          } catch (_) {
            // One broken workspace mustn't blank the rest; its screens fall
            // back to their default group.
          }
        }),
        // Each screen's module picks its native workspace. DocType records
        // are System-Manager-only, so DocTypes go through getdoctype (shared
        // with the permission checks); Report is readable by every Desk User,
        // so one list call. Unknown module → first workspace that lists it.
        ...kNavCatalog.where((l) => l.showInDrawer && l.linkType == 'DocType').map((l) async {
          final m = await Get.find<PermissionService>().moduleOf(l.linkTo);
          if (m != null) modules[l.key] = m;
        }),
        () async {
          try {
            final byName = {
              for (final l in kNavCatalog.where((l) => l.showInDrawer && l.linkType == 'Report'))
                l.linkTo: l.key
            };
            final r = await api.callMethod('frappe.client.get_list', params: {
              'doctype': 'Report',
              'fields': jsonEncode(['name', 'module']),
              'filters': jsonEncode([
                ['name', 'in', byName.keys.toList()]
              ]),
              'limit_page_length': 0,
            });
            for (final row in (r.data['message'] as List? ?? const [])) {
              final key = byName[row['name']];
              if (key != null && row['module'] is String) {
                modules[key] = row['module'] as String;
              }
            }
          } catch (_) {}
        }(),
      ]);
      if (_loadedFor == user) {
        groups.value = buildWorkspaceMenu(pages, desktop, modules);
        _loadedAt = DateTime.now();
        await storage?.saveNavMenu(user, menuToJson(groups));
      }
    } catch (e) {
      if (_loadedFor == user) _loadedFor = null;
      debugPrint('AppNavDrawer: workspace load failed — $e');
    }
  }

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
    final authController   = Get.find<AuthenticationController>();
    final drawerController = AppNavDrawerController.instance;
    // Retry path (e.g. offline at login); a no-op once loaded for this user.
    WidgetsBinding.instance.addPostFrameCallback((_) => drawerController
        .loadFor(authController.currentUser.value?.email));

    final String currentRoute = Get.currentRoute;
    final s = context.scheme;
    const skeleton = _SkeletonDrawerItem();

    return SafeArea(
      child: Drawer(
        elevation: 0,
        backgroundColor: s.fg,
        child: Column(
          children: [
            // ── Account card → User Area ───────────────────────────────────
            Obx(() {
              final user = authController.currentUser.value;
              final name = user?.name ?? 'Guest';
              final initials = name.isNotEmpty ? name[0].toUpperCase() : 'G';
              final hasImage = user?.image?.isNotEmpty == true;
              final sub = (user?.designation?.isNotEmpty == true)
                  ? user!.designation!
                  : (user?.email ?? 'Not logged in');

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Material(
                  color: s.fg,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.toNamed(AppRoutes.USER_AREA);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: s.border),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(
                        children: [
                          AppAvatar(
                            size: 52,
                            initials: initials,
                            image: hasImage ? NetworkImage(user!.image!) : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: s.text),
                                ),
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(fontSize: 12, color: s.textMuted),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Account & settings',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: s.primary)),
                                    const SizedBox(width: 3),
                                    Icon(Icons.chevron_right,
                                        size: 13, color: s.primary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            Divider(height: 1, color: s.border, indent: 16, endIndent: 16),

            // ── Scrollable menu ────────────────────────────────────────────────────────
            Expanded(
              child: Obx(() {
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
                        height: 1, color: s.border),
                  ),

                  for (final g in drawerController.groups)
                    _ModuleGroup(
                      title: g.title,
                      icon: g.icon,
                      currentRoute: currentRoute,
                      drawerController: drawerController,
                      guardEntries: [for (final l in g.links) l.guard],
                      children: [
                        for (final sec in g.sections)
                          _GuardedSection(
                            entries: [for (final l in sec.links) l.guard],
                            children: [
                              if (sec.label != null) _NavSubheading(sec.label!),
                              for (final l in sec.links)
                                DocTypeGuard(
                                  doctype: l.guard.doctype,
                                  permType: l.guard.permType,
                                  loading: skeleton,
                                  child: _DrawerItem(
                                    title: l.title,
                                    icon: l.icon,
                                    route: l.route,
                                    currentRoute: currentRoute,
                                  ),
                                ),
                            ],
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
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final shimmerColor = Color.lerp(
            s.subtle,
            s.border,
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
    final s = context.scheme;
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
          leading: Icon(icon, color: s.textMuted, size: 22),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: s.text,
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

/// A section that hides its [children] when every entry in [entries] is
/// confirmed inaccessible. The [children] are stored as
/// a plain list so [_extractRoutes] can discover routes inside them.
class _GuardedSection extends StatelessWidget {
  final List<PermEntry> entries;
  final List<Widget> children;

  const _GuardedSection({
    required this.entries,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<PermissionService>();
    return Obx(() {
      final anyAccessible = entries.any(
        (e) => svc.hasAccess(e.doctype, permType: e.permType) != false,
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
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
      child: Row(
        children: [
          // Card label as Frappe Desk shows it (e.g. "Serial No and Batch"),
          // not upper-cased.
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: s.border,
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

  const _DrawerItem({
    required this.title,
    required this.icon,
    required this.route,
    required this.currentRoute,
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
    final s = context.scheme;
    final isSelected =
        route.isNotEmpty && currentRoute.startsWith(route);

    final theme        = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _defaultTap(context),
          borderRadius: BorderRadius.circular(16),
          splashColor:    primaryColor.withValues(alpha: 0.1),
          highlightColor: primaryColor.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
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
                    : s.textMuted,
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
                      : s.text,
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
