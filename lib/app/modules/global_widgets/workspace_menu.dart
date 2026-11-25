import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Default navigation argument builder: `{'name': id, 'mode': 'view'}`.
Map<String, dynamic> _defaultArgsFor(String id) => {'name': id, 'mode': 'view'};

/// A screen the app can open, keyed by what a Frappe Workspace links to
/// (`DocType` / `Report` + name). Each screen uses its server module or
/// [group], with [section] as its subheading.
///
/// This is the **single source of truth** for both drawer navigation and
/// search routing. Adding a DocType here (with a [formRoute]) automatically
/// registers it for Awesome Bar / Dashboard global search — no second list
/// to maintain.
class NavLink {
  final String linkType; // 'DocType' | 'Report'
  final String linkTo;
  final String title;
  final IconData icon;
  final String route;
  final PermEntry guard;

  /// Fallback drawer group. Match the server's `module` value.
  final String group;
  final String? section;

  // ── Search / routing fields (defaults cover ~65 % of entries) ──

  /// Form route to navigate to on tap from search results.
  /// `null` for Reports or DocTypes without a dedicated form screen
  /// (e.g. Attendance). Entries without a [formRoute] are excluded from
  /// the global search target registry.
  final String? formRoute;

  /// Decorative tint for the search-result icon.
  final Color color;

  /// Plural label shown as the search-result group header, e.g.
  /// 'Delivery Notes'. Auto-derived as `'${title}s'` when `null`.
  final String? searchLabel;

  /// Builds the `Get.arguments` map for opening document [id] on the form.
  /// Defaults to `{'name': id, 'mode': 'view'}`.
  final Map<String, dynamic> Function(String id) argsFor;

  /// Whether to offer this doctype in cross-doctype search results (Dashboard
  /// fan-out, Awesome Bar "List" matches, ToDo reference-type picker).
  /// Set to `false` for doctypes whose `name` is a meaningless hash.
  final bool discoverable;

  /// Whether this entry appears in the navigation drawer. Set to `false`
  /// for screens reachable only via search or deep links (e.g. ToDo).
  final bool showInDrawer;

  const NavLink(
    this.linkType,
    this.linkTo,
    this.title,
    this.icon,
    this.route,
    this.guard,
    this.group, [
    this.section,
    this.formRoute,
    this.color = Colors.blueGrey,
    this.searchLabel,
    this.argsFor = _defaultArgsFor,
    this.discoverable = true,
    this.showInDrawer = true,
  ]);

  String get key => '${linkType.toLowerCase()}:$linkTo';
}


class NavSection {
  final String? label; // null = top of group, no subheading
  final List<NavLink> links;
  NavSection(this.label, this.links);
}

class NavGroup {
  final String title;
  final IconData icon;
  final List<NavSection> sections;
  NavGroup(this.title, this.icon, this.sections);

  List<NavLink> get links => [for (final s in sections) ...s.links];
}

PermEntry _r(String d) => (doctype: d, permType: 'read');
PermEntry _rep(String d) => (doctype: d, permType: 'report');

// Non-default argsFor builders used by specific doctypes.
Map<String, dynamic> _itemArgs(String id) => {'itemCode': id};
Map<String, dynamic> _nameOnly(String id) => {'name': id};
Map<String, dynamic> _nameEdit(String id) => {'name': id, 'mode': 'edit'};
Map<String, dynamic> _batchArgs(String id) => {'name': id, 'mode': 'edit'};

/// Every app screen — drawer destinations AND search-only screens.
/// Without a workspace or cached layout, groups follow their first drawer entry.
/// Search targets are derived automatically in catalog order.
///
/// To add a new DocType to both the drawer AND search, provide a [formRoute].
/// To add a search-only screen (not shown in the drawer), set
/// `showInDrawer: false`.
final List<NavLink> kNavCatalog = [
  // ── Stock ──
  NavLink('DocType', 'Item', 'Item', Icons.category_rounded, AppRoutes.ITEM, _r('Item'), 'Stock',
      null, AppRoutes.ITEM_FORM, Colors.blueGrey, 'Items', _itemArgs),
  NavLink('DocType', 'Batch', 'Batch', Icons.qr_code_scanner_rounded, AppRoutes.BATCH, _r('Batch'), 'Stock',
      null, AppRoutes.BATCH_FORM, Colors.amber, 'Batches', _batchArgs),
  NavLink('DocType', 'Material Request', 'Material Request', Icons.playlist_add_check_rounded, AppRoutes.MATERIAL_REQUEST, _r('Material Request'), 'Stock',
      null, AppRoutes.MATERIAL_REQUEST_FORM, Colors.pink),
  NavLink('DocType', 'Stock Entry', 'Stock Entry', Icons.compare_arrows_rounded, AppRoutes.STOCK_ENTRY, _r('Stock Entry'), 'Stock',
      null, AppRoutes.STOCK_ENTRY_FORM, Colors.orange, 'Stock Entries'),
  NavLink('DocType', 'Delivery Note', 'Delivery Note', Icons.local_shipping_rounded, AppRoutes.DELIVERY_NOTE, _r('Delivery Note'), 'Stock',
      null, AppRoutes.DELIVERY_NOTE_FORM, Colors.blue),
  NavLink('DocType', 'Packing Slip', 'Packing Slip', Icons.assignment_return_rounded, AppRoutes.PACKING_SLIP, _r('Packing Slip'), 'Stock',
      null, AppRoutes.PACKING_SLIP_FORM, Colors.purple),
  NavLink('Report', 'Batch-Wise Balance History', 'Batch-Wise Balance History', Icons.history_toggle_off_rounded, AppRoutes.BATCH_WISE_BALANCE, _rep('Batch'), 'Stock', 'Reports'),
  NavLink('Report', 'Item Variant Details', 'Item Variant Details', Icons.style_outlined, AppRoutes.ITEM_VARIANT_DETAILS, _rep('Item'), 'Stock', 'Reports'),
  NavLink('Report', 'Stock Balance', 'Stock Balance', Icons.account_balance_wallet_outlined, AppRoutes.STOCK_BALANCE, _rep('Stock Entry'), 'Stock', 'Reports'),
  NavLink('Report', 'Stock Ageing - Custom', 'Stock Ageing', Icons.hourglass_bottom_rounded, AppRoutes.STOCK_AGEING, _rep('Item'), 'Stock', 'Reports'),
  NavLink('DocType', 'Landed Cost Voucher', 'Landed Cost Voucher', Icons.flight_land_rounded, AppRoutes.LANDED_COST_VOUCHER, _r('Landed Cost Voucher'), 'Stock',
      'Tools', AppRoutes.LANDED_COST_VOUCHER_FORM, Colors.brown),
  // ── Purchasing ──
  NavLink('DocType', 'Purchase Order', 'Purchase Order', Icons.description_rounded, AppRoutes.PURCHASE_ORDER, _r('Purchase Order'), 'Buying',
      null, AppRoutes.PURCHASE_ORDER_FORM, Colors.brown),
  NavLink('DocType', 'Purchase Receipt', 'Purchase Receipt', Icons.receipt_long_rounded, AppRoutes.PURCHASE_RECEIPT, _r('Purchase Receipt'), 'Stock',
      null, AppRoutes.PURCHASE_RECEIPT_FORM, Colors.green),
  NavLink('Report', 'Suppliers by Item', 'Suppliers by Item', Icons.local_shipping_outlined, AppRoutes.SUPPLIERS_BY_ITEM, kSuppliersByItemPermission, 'Buying', 'Reports'),

  // ── Manufacturing ──
  NavLink('DocType', 'BOM', 'Bill of Materials', Icons.account_tree_rounded, AppRoutes.BOM, _r('BOM'), 'Manufacturing',
      null, AppRoutes.BOM_FORM, Colors.teal, 'BOMs', _nameOnly),
  NavLink('DocType', 'Work Order', 'Work Order', Icons.assignment_rounded, AppRoutes.WORK_ORDER, _r('Work Order'), 'Manufacturing',
      null, AppRoutes.WORK_ORDER_FORM, Colors.indigo),
  NavLink('DocType', 'Job Card', 'Job Card', Icons.assignment_ind_rounded, AppRoutes.JOB_CARD, _r('Job Card'), 'Manufacturing',
      null, AppRoutes.JOB_CARD_FORM, Colors.deepOrange, null, _nameOnly),
  NavLink('Report', 'BOM Search', 'BOM Search', Icons.manage_search_rounded, AppRoutes.BOM_SEARCH, _rep('BOM'), 'Stock', 'Reports'),
  NavLink('Report', 'Job Card Summary', 'Job Card Summary', Icons.summarize_outlined, AppRoutes.JOB_CARD_SUMMARY, _rep('Job Card'), 'Manufacturing', 'Reports'),
  NavLink('Report', 'BOM Stock with Customer Code', 'BOM Stock with Customer Code', Icons.inventory_2_outlined, AppRoutes.BOM_STOCK_CUSTOMER_CODE, _rep('BOM'), 'Manufacturing', 'Reports'),

  // ── Sales and pricing ──
  NavLink('DocType', 'POS Upload', 'POS Upload', Icons.cloud_upload_rounded, AppRoutes.POS_UPLOAD, _r('POS Upload'), 'Selling',
      null, AppRoutes.POS_UPLOAD_FORM, Colors.deepPurple),
  NavLink('DocType', 'Sales Order', 'Sales Order', Icons.request_quote_rounded, AppRoutes.SALES_ORDER, _r('Sales Order'), 'Selling',
      null, AppRoutes.SALES_ORDER_FORM, Colors.teal),
  NavLink('DocType', 'Item Price', 'Item Price', Icons.sell_outlined, AppRoutes.ITEM_PRICE, _r('Item Price'), 'Stock',
      'Pricing', AppRoutes.ITEM_PRICE_FORM, Colors.indigo, null, _nameEdit, false),
  NavLink('DocType', 'Pricing Rule', 'Pricing Rule', Icons.discount_outlined, AppRoutes.PRICING_RULE, _r('Pricing Rule'), 'Accounts',
      'Pricing', AppRoutes.PRICING_RULE_FORM, Colors.deepOrange, null, _nameEdit),
  NavLink('Report', 'POS and Delivery Note Item Rate', 'POS & DN Item Rate', Icons.price_change_outlined, AppRoutes.POS_DN_ITEM_RATE, _rep('POS Upload'), 'Stock', 'Reports'),

  // ── HR ──
  NavLink('DocType', 'Attendance', 'Attendance', Icons.how_to_reg_rounded, AppRoutes.ATTENDANCE, _r('Attendance'), 'HR'),
  NavLink('Report', 'Monthly Attendance Sheet', 'Monthly Attendance Sheet', Icons.calendar_month_rounded, AppRoutes.MONTHLY_ATTENDANCE_SHEET, _rep('Attendance'), 'HR', 'Reports'),
  NavLink('Report', 'Shift Attendance', 'Shift Attendance', Icons.schedule_rounded, AppRoutes.SHIFT_ATTENDANCE, _rep('Attendance'), 'HR', 'Reports'),
  NavLink('Report', 'Employee Hours Utilization Based On Timesheet', 'Employee Hours Utilisation', Icons.timelapse_rounded, AppRoutes.EMPLOYEE_HOURS_UTILIZATION, _rep('Timesheet'), 'HR', 'Reports'),

  // ── Desk (search-only catalog entries) ──
  NavLink('DocType', 'ToDo', 'ToDo', Icons.check_circle_outline, AppRoutes.TODO, _r('ToDo'), 'Desk',
      null, AppRoutes.TODO_FORM, Colors.cyan, 'ToDos', _defaultArgsFor, true, false),
];

const Map<String, IconData> _groupIcons = {
  'Stock': Icons.inventory_2_rounded,
  'Buying': Icons.shopping_bag_rounded,
  'Manufacturing': Icons.precision_manufacturing_rounded,
  'Selling': Icons.storefront_rounded,
  'Accounts': Icons.account_balance_rounded,
  'HR': Icons.badge_rounded,
  'Desk': Icons.desktop_windows_rounded,
};

IconData _groupIcon(String title) =>
    _groupIcons[title] ?? Icons.workspaces_outlined;

/// The parts of Desk's boot data (`frappe.boot`) used for group order and
/// visibility.
class DeskBoot {
  /// `workspaces.pages`: the session user's workspace pages, the same rows
  /// `get_workspace_sidebar_items` / `get_workspaces` return. Frappe 16.56
  /// whitelists neither, so there this is the only source. Empty when the
  /// boot object carries none (v15).
  final List<Map<String, dynamic>> pages;

  /// `user.name`: who the boot data was rendered for.
  final String? userId;

  /// `user.roles`: the session user's roles. The only place a user who is
  /// not a System Manager can read them on v16 (`get_roles` is gone and the
  /// User `roles` table is permlevel 1).
  final List<String> roles;

  /// Report names that Desk allows for [userId]. Null means Desk did not
  /// supply a usable permission map. An empty map explicitly permits none.
  final Set<String>? allowedReports;

  const DeskBoot({
    this.pages = const [],
    this.userId,
    this.roles = const [],
    this.allowedReports,
  });
}

final _deskBootStart = RegExp(r'frappe\.boot\s*=\s*');

/// The JSON text of the `{…}` object starting at [start], or `null`.
String? _objectAt(String src, int start) {
  if (start >= src.length || src[start] != '{') return null;
  var depth = 0;
  var inString = false;
  for (var i = start; i < src.length; i++) {
    final c = src[i];
    if (inString) {
      if (c == '\\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}' && --depth == 0) {
      return src.substring(start, i + 1);
    }
  }
  return null;
}

/// The boot object Desk embeds in its page: v15 writes
/// `frappe.boot = JSON.parse("…")`, v16 `frappe.boot = {…}`.
dynamic _bootFromHtml(String html) {
  final m = _deskBootStart.firstMatch(html);
  if (m == null) return null;
  const parse = 'JSON.parse(';
  if (html.startsWith(parse, m.end)) {
    final lit = RegExp(r'"(?:[^"\\]|\\.)*"').matchAsPrefix(html, m.end + parse.length);
    return lit == null ? null : jsonDecode(jsonDecode(lit.group(0)!) as String);
  }
  final obj = _objectAt(html, m.end);
  return obj == null ? null : jsonDecode(obj);
}

/// Workspace page rows from a `pages` list, whatever served it (the
/// workspace endpoints or Desk's boot data). Anything that is not a row is
/// dropped; a missing or malformed list yields none.
List<Map<String, dynamic>> workspacePagesOf(dynamic pages) => [
      if (pages is List)
        for (final p in pages)
          if (p is Map) Map<String, dynamic>.from(p),
    ];

Set<String>? _reportNames(dynamic reports) {
  if (reports is! Map) return null;
  final names = <String>{};
  for (final e in reports.entries) {
    final name = e.key;
    if (name is! String || name.isEmpty || e.value is! Map) return null;
    names.add(name);
  }
  return names;
}

/// [DeskBoot] from the page Desk serves (`/app` on v15, `/desk` on v16).
/// `null` when the page carries no boot data (e.g. a login page).
DeskBoot? deskBootFromHtml(String html) {
  try {
    final boot = _bootFromHtml(html);
    if (boot is! Map) return null;
    final user = boot['user'];
    final workspaces = boot['workspaces'];
    return DeskBoot(
      pages: workspacePagesOf(workspaces is Map ? workspaces['pages'] : null),
      userId: user is Map && user['name'] is String ? user['name'] as String : null,
      roles: [
        if (user is Map && user['roles'] is List)
          for (final r in user['roles'] as List)
            if (r is String && r.isNotEmpty) r,
      ],
      // Newer Desk builds put the same name-keyed map at the top level.
      allowedReports: _reportNames(boot['allowed_reports']) ??
          _reportNames(user is Map ? user['all_reports'] : null),
    );
  } catch (_) {
    return null;
  }
}

/// Places each screen under its server module or catalog fallback. The
/// workspace pages supply the order for matching group titles, folding child
/// workspaces into their top-level parent.
List<NavGroup> buildWorkspaceMenu(
  List<Map<String, dynamic>> pages, [
  Map<String, String> modules = const {},
]) {
  final visible = pages.where((p) => p['is_hidden'] != 1);
  final byName = {for (final p in visible) p['name'] as String: p};

  String rootTitle(Map<String, dynamic> page) {
    final seen = <String>{};
    var current = page;
    while (true) {
      final parent = current['parent_page'] as String?;
      if (parent == null || parent.isEmpty) break;
      final next = byName[parent];
      if (next == null || !seen.add(parent)) break;
      current = next;
    }
    return (current['title'] ?? current['name']) as String;
  }

  return _placeLinks(visible.map(rootTitle), modules);
}

List<NavGroup> _placeLinks(
  Iterable<String> groupTitles,
  Map<String, String> modules,
) {
  final groups = <String, Map<String?, List<NavLink>>>{
    for (final title in groupTitles) title: {null: []},
  };
  final seen = <String>{};
  for (final type in const ['DocType', 'Report']) {
    for (final link in kNavCatalog) {
      if (link.linkType != type || !link.showInDrawer || !seen.add(link.key)) {
        continue;
      }
      final module = modules[link.key];
      final group = module == null || module.trim().isEmpty ? link.group : module;
      groups
          .putIfAbsent(group, () => {null: []})
          .putIfAbsent(link.section, () => [])
          .add(link);
    }
  }
  return [
    for (final e in groups.entries)
      if (e.value.values.any((links) => links.isNotEmpty))
        NavGroup(e.key, _groupIcon(e.key), [
          for (final s in e.value.entries)
            if (s.value.isNotEmpty) NavSection(s.key, s.value),
        ]),
  ];
}

/// Applies Desk's per-report permissions to the layout for the current session.
List<NavGroup> filterWorkspaceReports(
    List<NavGroup> menu, Set<String>? allowedReports) {
  if (allowedReports == null) return menu;
  final visible = <NavGroup>[];
  for (final group in menu) {
    final sections = <NavSection>[];
    for (final section in group.sections) {
      final links = [
        for (final link in section.links)
          if (link.linkType != 'Report' || allowedReports.contains(link.linkTo))
            link,
      ];
      if (links.isNotEmpty) sections.add(NavSection(section.label, links));
    }
    if (sections.isNotEmpty) {
      visible.add(NavGroup(group.title, group.icon, sections));
    }
  }
  return visible;
}

/// Compact, storable menu with an optional `m` map of server Report modules
/// keyed by link within each group.
List<Map<String, dynamic>> menuToJson(
  List<NavGroup> menu, [
  Map<String, String> modules = const {},
]) {
  final json = <Map<String, dynamic>>[];
  for (final group in menu) {
    final reportModules = <String, String>{};
    for (final link in group.links) {
      final module = modules[link.key];
      if (link.linkType == 'Report' &&
          module != null &&
          module.trim().isNotEmpty) {
        reportModules[link.key] = module;
      }
    }
    json.add({
      't': group.title,
      's': [
        for (final s in group.sections)
          {'l': s.label, 'k': [for (final l in s.links) l.key]},
      ],
      if (reportModules.isNotEmpty) 'm': reportModules,
    });
  }
  return json;
}

/// Restores group order and re-places links using the current catalog. When
/// provided, [modules] supplies current server metadata. Otherwise the
/// restore uses saved server Report modules and falls back to catalog groups.
/// Returns `null` for unreadable input.
List<NavGroup>? menuFromJson(
  List<dynamic>? json, [
  Map<String, String>? modules,
]) {
  if (json == null) return null;
  try {
    final titles = <String>[];
    final savedModules = <String, String>{};
    for (final group in json) {
      titles.add(group['t'] as String);
      final saved = group['m'];
      for (final section in group['s'] as List) {
        for (final key in section['k'] as List) {
          if (modules == null &&
              key is String &&
              key.startsWith('report:') &&
              saved is Map &&
              saved[key] is String) {
            savedModules[key] = saved[key] as String;
          }
        }
      }
    }
    return _placeLinks(titles, modules ?? savedModules);
  } catch (_) {
    return null;
  }
}
