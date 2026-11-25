import 'dart:convert';
import 'package:dio/dio.dart' as dio;

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

  /// Module groups for DocTypes and Reports. Starts with the catalog until
  /// [loadFor] restores or refreshes the menu.
  final groups = buildWorkspaceMenu(const []).obs;
  final _reportAccess = Rxn<({String user, Set<String> names})>();
  String? _loadedFor;
  String? _layoutFor;
  DateTime? _loadedAt;
  Object? _activeLoad;
  AppLifecycleListener? _lifecycle;

  /// Server navigation and module edits show up on the next resume after this.
  static const _staleAfter = Duration(minutes: 30);

  @override
  void onInit() {
    super.onInit();
    _lifecycle = AppLifecycleListener(onResume: () {
      final user = _loadedFor, at = _loadedAt;
      if (user == null || at == null) return;
      if (DateTime.now().difference(at) < _staleAfter) return;
      loadFor(user, refresh: true);
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

  /// The endpoints that list the user's workspace pages as `{pages: [...]}`:
  /// Frappe v15's name first, then the one v16 renamed it to.
  static const workspaceMethods = [
    'frappe.desk.desktop.get_workspace_sidebar_items',
    'frappe.desk.desktop.get_workspaces',
  ];

  /// Server whose workspace endpoints are known not to answer, so later
  /// loads go straight to Desk's boot data instead of failing twice first.
  String? _bootOnlyServer;

  /// The user's workspace pages.
  ///
  /// Frappe 16.56 whitelists neither endpoint (the first is gone, the second
  /// answers 403), but Desk's boot data carries the same rows — [desk] is
  /// that boot data, already being fetched for report visibility. Throws
  /// when no source yields pages, so the caller keeps the current menu.
  Future<List<Map<String, dynamic>>> _fetchPages(
      ApiProvider api, Future<DeskBoot> desk) async {
    if (_bootOnlyServer != api.baseUrl) {
      for (final method in workspaceMethods) {
        try {
          final res = await api.callMethod(method);
          return workspacePagesOf(res.data['message']?['pages']);
        } on dio.DioException catch (e) {
          // Only a server that answered "no such method / not allowed" has
          // ruled the endpoint out; a timeout says nothing about it.
          if (e.response == null) rethrow;
        }
      }
    }
    final pages = (await desk).pages;
    if (pages.isEmpty) {
      throw StateError('No workspace source answered');
    }
    _bootOnlyServer = api.baseUrl;
    return pages;
  }

  /// The workspace page fallback and exact-name report allowlist from Desk.
  Future<DeskBoot> _fetchDeskBoot(ApiProvider api) async {
    try {
      final html = await api.getDeskHtml();
      return (html == null ? null : deskBootFromHtml(html)) ?? const DeskBoot();
    } catch (_) {
      return const DeskBoot();
    }
  }

  /// Loads modules and Desk navigation for the Frappe User document named
  /// [user]. A workspace failure keeps the cached group order, applies any
  /// fresh modules, and retries on the next call.
  Future<void> loadFor(String? user, {bool refresh = false}) async {
    if (user == null ||
        (user == _loadedFor && (!refresh || _activeLoad != null))) {
      return;
    }
    final load = _activeLoad = Object();
    _loadedFor = user;
    _reportAccess.value = null;
    final storage =
        Get.isRegistered<StorageService>() ? Get.find<StorageService>() : null;
    final cachedMenu = storage?.getNavMenu(user);
    final repeatLoad = _layoutFor == user;
    if (!repeatLoad) {
      groups.value = menuFromJson(cachedMenu) ??
          buildWorkspaceMenu(const []);
      _layoutFor = user;
    }
    final modules = <String, String>{};
    var layoutBuilt = false;
    try {
      final api = Get.find<ApiProvider>();
      // Boot supplies the report allowlist and, on Frappe 16.56, the pages.
      final deskBoot = _fetchDeskBoot(api).then((boot) {
        final names = boot.allowedReports;
        if (_activeLoad == load && boot.userId == user && names != null) {
          _reportAccess.value = (user: user, names: names);
        }
        return boot;
      });
      var pages = const <Map<String, dynamic>>[];
      await Future.wait<void>([
        _fetchPages(api, deskBoot).then((result) {
          pages = result;
        }),
        deskBoot.then<void>((_) {}),
        _fetchDocTypeModules(refresh: repeatLoad).then(modules.addAll),
        _fetchReportModules(api).then(modules.addAll),
      ]);
      if (_activeLoad == load) {
        groups.value = buildWorkspaceMenu(pages, modules);
        layoutBuilt = true;
        _loadedAt = DateTime.now();
        await storage?.saveNavMenu(user, menuToJson(groups, modules));
      }
    } catch (e) {
      if (_activeLoad == load && !layoutBuilt) {
        groups.value = menuFromJson(cachedMenu, modules) ??
            buildWorkspaceMenu(const [], modules);
      }
      if (_activeLoad == load) _loadedFor = null;
      debugPrint('AppNavDrawer: workspace load failed — $e');
    } finally {
      if (_activeLoad == load) _activeLoad = null;
    }
  }

  /// Frappe v15 and v16 grant Desk User read access to Report records.
  /// These rows supply placement metadata. Report visibility comes from Desk
  /// and the existing permission guards.
  Future<Map<String, String>> _fetchReportModules(ApiProvider api) async {
    final byName = {
      for (final link in kNavCatalog)
        if (link.showInDrawer && link.linkType == 'Report') link.linkTo: link.key,
    };
    try {
      final response = await api.callMethod('frappe.client.get_list', params: {
        'doctype': 'Report',
        'fields': jsonEncode(['name', 'module']),
        'filters': jsonEncode([
          ['name', 'in', byName.keys.toList()],
        ]),
        'limit_page_length': 0,
      });
      final rows = response.data['message'];
      return {
        if (rows is List)
          for (final row in rows)
            if (row is Map &&
                byName.containsKey(row['name']) &&
                row['module'] is String)
              byName[row['name']]!: row['module'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _fetchDocTypeModules({
    required bool refresh,
  }) async {
    if (!Get.isRegistered<PermissionService>()) return {};
    final permissions = Get.find<PermissionService>();
    final links = kNavCatalog.where(
      (l) => l.showInDrawer && l.linkType == 'DocType',
    );
    final entries = await Future.wait(
      links.map((link) async => (
        link.key,
        await permissions.moduleOf(link.linkTo, refresh: refresh),
      )),
    );
    return {for (final (key, module) in entries) if (module != null) key: module};
  }

  void clearSession() {
    _activeLoad = null;
    _loadedFor = null;
    _layoutFor = null;
    _loadedAt = null;
    _reportAccess.value = null;
  }

  List<NavGroup> visibleGroupsFor(String? user) {
    final access = _reportAccess.value;
    return filterWorkspaceReports(
      groups,
      access?.user == user ? access?.names : null,
    );
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
        .loadFor(authController.currentUser.value?.id));

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

                  for (final g in drawerController.visibleGroupsFor(
                      authController.currentUser.value?.id))
                    _ModuleGroup(
                      key: ValueKey(g.title),
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
    super.key,
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
