import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Default navigation argument builder: `{'name': id, 'mode': 'view'}`.
Map<String, dynamic> _defaultArgsFor(String id) => {'name': id, 'mode': 'view'};

/// A screen the app can open, keyed by what a Frappe Workspace links to
/// (`DocType` / `Report` + name). The workspace decides WHERE it shows;
/// [group] / [section] are only used when no workspace places it (or the
/// workspace fetch failed), so every screen stays reachable.
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
/// Order = fallback drawer order; search targets are derived automatically.
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
  NavLink('DocType', 'Landed Cost Voucher', 'Landed Cost Voucher', Icons.flight_land_rounded, AppRoutes.LANDED_COST_VOUCHER, _r('Landed Cost Voucher'), 'Stock',
      'Tools', AppRoutes.LANDED_COST_VOUCHER_FORM, Colors.brown),

  // ── Buying ──
  NavLink('DocType', 'Purchase Order', 'Purchase Order', Icons.description_rounded, AppRoutes.PURCHASE_ORDER, _r('Purchase Order'), 'Buying',
      null, AppRoutes.PURCHASE_ORDER_FORM, Colors.brown),
  NavLink('DocType', 'Purchase Receipt', 'Purchase Receipt', Icons.receipt_long_rounded, AppRoutes.PURCHASE_RECEIPT, _r('Purchase Receipt'), 'Buying',
      null, AppRoutes.PURCHASE_RECEIPT_FORM, Colors.green),

  // ── Manufacturing ──
  NavLink('DocType', 'BOM', 'Bill of Materials', Icons.account_tree_rounded, AppRoutes.BOM, _r('BOM'), 'Manufacturing',
      null, AppRoutes.BOM_FORM, Colors.teal, 'BOMs', _nameOnly),
  NavLink('DocType', 'Work Order', 'Work Order', Icons.assignment_rounded, AppRoutes.WORK_ORDER, _r('Work Order'), 'Manufacturing',
      null, AppRoutes.WORK_ORDER_FORM, Colors.indigo),
  NavLink('DocType', 'Job Card', 'Job Card', Icons.assignment_ind_rounded, AppRoutes.JOB_CARD, _r('Job Card'), 'Manufacturing',
      null, AppRoutes.JOB_CARD_FORM, Colors.deepOrange, null, _nameOnly),
  NavLink('Report', 'BOM Search', 'BOM Search', Icons.manage_search_rounded, AppRoutes.BOM_SEARCH, _rep('BOM'), 'Manufacturing', 'Reports'),
  NavLink('Report', 'Job Card Summary', 'Job Card Summary', Icons.summarize_outlined, AppRoutes.JOB_CARD_SUMMARY, _rep('Job Card'), 'Manufacturing', 'Reports'),
  NavLink('Report', 'BOM Stock with Customer Code', 'BOM Stock with Customer Code', Icons.inventory_2_outlined, AppRoutes.BOM_STOCK_CUSTOMER_CODE, _rep('BOM'), 'Manufacturing', 'Reports'),

  // ── Selling ──
  NavLink('DocType', 'POS Upload', 'POS Upload', Icons.cloud_upload_rounded, AppRoutes.POS_UPLOAD, _r('POS Upload'), 'Selling',
      null, AppRoutes.POS_UPLOAD_FORM, Colors.deepPurple),
  NavLink('DocType', 'Sales Order', 'Sales Order', Icons.request_quote_rounded, AppRoutes.SALES_ORDER, _r('Sales Order'), 'Selling',
      null, AppRoutes.SALES_ORDER_FORM, Colors.teal),
  NavLink('DocType', 'Item Price', 'Item Price', Icons.sell_outlined, AppRoutes.ITEM_PRICE, _r('Item Price'), 'Selling',
      'Pricing', AppRoutes.ITEM_PRICE_FORM, Colors.indigo, null, _nameEdit, false),
  NavLink('DocType', 'Pricing Rule', 'Pricing Rule', Icons.discount_outlined, AppRoutes.PRICING_RULE, _r('Pricing Rule'), 'Selling',
      'Pricing', AppRoutes.PRICING_RULE_FORM, Colors.deepOrange, null, _nameEdit),
  NavLink('Report', 'POS and Delivery Note Item Rate', 'POS & DN Item Rate', Icons.price_change_outlined, AppRoutes.POS_DN_ITEM_RATE, _rep('POS Upload'), 'Selling', 'Reports'),

  // ── HR ──
  NavLink('DocType', 'Attendance', 'Attendance', Icons.how_to_reg_rounded, AppRoutes.ATTENDANCE, _r('Attendance'), 'HR'),
  NavLink('Report', 'Monthly Attendance Sheet', 'Monthly Attendance Sheet', Icons.calendar_month_rounded, AppRoutes.MONTHLY_ATTENDANCE_SHEET, _rep('Attendance'), 'HR', 'Reports'),

  // ── Search-only (not shown in drawer) ──
  NavLink('DocType', 'ToDo', 'ToDo', Icons.check_circle_outline, AppRoutes.TODO, _r('ToDo'), 'Tools',
      null, AppRoutes.TODO_FORM, Colors.cyan, 'ToDos', _defaultArgsFor, true, false),
];

const Map<String, IconData> _groupIcons = {
  'Stock': Icons.inventory_2_rounded,
  'Buying': Icons.shopping_bag_rounded,
  'Manufacturing': Icons.precision_manufacturing_rounded,
  'Selling': Icons.storefront_rounded,
  'HR': Icons.badge_rounded,
};

IconData _groupIcon(String title) =>
    _groupIcons[title] ?? Icons.workspaces_outlined;

/// Names of the cards and shortcuts actually placed on a workspace page.
/// Frappe Desk renders only blocks in the page's `content` (Editor.js JSON);
/// the links/shortcuts tables can hold more. `null` = no usable layout, so
/// nothing is filtered.
({Set<String> cards, Set<String> shortcuts})? _placedBlocks(dynamic content) {
  try {
    final blocks = content is String ? jsonDecode(content) : content;
    if (blocks is! List || blocks.isEmpty) return null;
    final cards = <String>{}, shortcuts = <String>{};
    for (final b in blocks) {
      final data = b is Map ? b['data'] : null;
      if (data is! Map) continue;
      if (b['type'] == 'card' && data['card_name'] is String) {
        cards.add(data['card_name'] as String);
      } else if (b['type'] == 'shortcut' && data['shortcut_name'] is String) {
        shortcuts.add(data['shortcut_name'] as String);
      }
    }
    return (cards: cards, shortcuts: shortcuts);
  } catch (_) {
    return null;
  }
}

/// Maps Frappe v15 workspaces onto the app's screens.
///
/// [pages] is `get_workspace_sidebar_items().pages` (already filtered by the
/// server for module blocks, roles and domains, in sidebar order).
/// [desktop] maps page name → `get_desktop_page(page)` (links already
/// permission-filtered). [modules] maps [NavLink.key] → the DocType's /
/// Report's Frappe module. Child workspaces fold into their top-level parent.
///
/// Each screen appears ONCE, in its native workspace (the first workspace
/// whose module is the screen's module) — at the card/shortcut that
/// workspace gives it, else at the top of that group. With no native
/// workspace visible it goes where the first workspace lists it, else to
/// its default group. Links to screens the app doesn't have are dropped.
/// With no pages this yields the plain fallback menu.
List<NavGroup> buildWorkspaceMenu(
  List<Map<String, dynamic>> pages,
  Map<String, Map<String, dynamic>> desktop, [
  Map<String, String> modules = const {},
]) {
  final drawerLinks = kNavCatalog.where((l) => l.showInDrawer);
  final byKey = {for (final l in drawerLinks) l.key: l};
  final visible = pages.where((p) => p['is_hidden'] != 1).toList();
  final byName = {for (final p in visible) p['name'] as String: p};

  String rootTitle(Map<String, dynamic> p) {
    final seen = <String>{};
    var cur = p;
    while (true) {
      final parent = cur['parent_page'] as String?;
      final next = (parent == null || parent.isEmpty) ? null : byName[parent];
      if (next == null || !seen.add(parent!)) break;
      cur = next;
    }
    return (cur['title'] ?? cur['name']) as String;
  }

  // group → section label → links; seeded in sidebar/card order so the
  // layout follows the workspaces even though links are placed later.
  final groups = <String, Map<String?, List<NavLink>>>{};
  final nativeGroup = <String, String>{}; // module → group
  final listed = <(String key, String group, String? section)>[];

  for (final p in visible) {
    final group = rootTitle(p);
    final sections = groups.putIfAbsent(group, () => {null: []});
    final module = p['module'];
    if (module is String && module.isNotEmpty) {
      nativeGroup.putIfAbsent(module, () => group);
    }
    final page = desktop[p['name']];
    if (page == null) continue;
    var shortcuts = page['shortcuts']?['items'] as List? ?? const [];
    var cards = page['cards']?['items'] as List? ?? const [];
    final placed = _placedBlocks(p['content']);
    if (placed != null) {
      final s = [
        for (final x in shortcuts)
          if (placed.shortcuts.contains(x['label']) ||
              placed.shortcuts.contains(x['link_to']))
            x
      ];
      final c = [
        for (final x in cards)
          if (placed.cards.contains(x['label'])) x
      ];
      // Labels arrive translated but `content` names don't: if nothing
      // matches, the layout can't be trusted — keep everything.
      if (s.isNotEmpty || c.isNotEmpty) {
        shortcuts = s;
        cards = c;
      }
    }
    for (final s in shortcuts) {
      final key = '${(s['type'] ?? '').toString().toLowerCase()}:${s['link_to']}';
      if (byKey.containsKey(key)) listed.add((key, group, null));
    }
    for (final card in cards) {
      final label = card['label'] as String?;
      for (final s in (card['links'] as List? ?? const [])) {
        final key = '${(s['link_type'] ?? '').toString().toLowerCase()}:${s['link_to']}';
        if (!byKey.containsKey(key)) continue;
        sections.putIfAbsent(label, () => []);
        listed.add((key, group, label));
      }
    }
  }

  // One home per screen.
  final home = <String, (String, String?)>{};
  for (final l in byKey.values) {
    final native = nativeGroup[modules[l.key]];
    final spots = listed.where((e) => e.$1 == l.key);
    final inNative = spots.where((e) => e.$2 == native);
    home[l.key] = native != null
        ? (inNative.isEmpty ? (native, null) : (native, inNative.first.$3))
        : spots.isNotEmpty
            ? (spots.first.$2, spots.first.$3)
            : (l.group, l.section);
  }

  // Screens at their workspace spot in workspace order, then the rest in
  // catalog order.
  final order = [
    for (final e in listed)
      if (home[e.$1] == (e.$2, e.$3)) e.$1,
    for (final l in byKey.values) l.key,
  ];
  final done = <String>{};
  for (final key in order) {
    if (!done.add(key)) continue;
    final (group, section) = home[key]!;
    groups
        .putIfAbsent(group, () => {null: []})
        .putIfAbsent(section, () => [])
        .add(byKey[key]!);
  }

  return _toGroups(groups);
}

List<NavGroup> _toGroups(Map<String, Map<String?, List<NavLink>>> groups) => [
      for (final e in groups.entries)
        if (e.value.values.any((links) => links.isNotEmpty))
          NavGroup(e.key, _groupIcon(e.key), [
            for (final s in e.value.entries)
              if (s.value.isNotEmpty) NavSection(s.key, s.value),
          ]),
    ];

/// Compact, storable form of a menu: `[{t: title, s: [{l: label, k: [keys]}]}]`.
List<Map<String, dynamic>> menuToJson(List<NavGroup> menu) => [
      for (final g in menu)
        {
          't': g.title,
          's': [
            for (final s in g.sections)
              {'l': s.label, 'k': [for (final l in s.links) l.key]}
          ],
        }
    ];

/// Restores [menuToJson] output against the CURRENT catalog: keys the app
/// no longer has are dropped, screens added since go to their default group.
/// Returns `null` for unreadable input.
List<NavGroup>? menuFromJson(List<dynamic>? json) {
  if (json == null) return null;
  try {
    final drawerLinks = kNavCatalog.where((l) => l.showInDrawer);
    final byKey = {for (final l in drawerLinks) l.key: l};
    final groups = <String, Map<String?, List<NavLink>>>{};
    final seen = <String>{};
    for (final g in json) {
      final sections = groups.putIfAbsent(g['t'] as String, () => {null: []});
      for (final s in g['s'] as List) {
        for (final k in s['k'] as List) {
          final l = byKey[k];
          if (l == null || !seen.add(l.key)) continue;
          sections.putIfAbsent(s['l'] as String?, () => []).add(l);
        }
      }
    }
    for (final l in byKey.values) {
      if (!seen.add(l.key)) continue;
      groups
          .putIfAbsent(l.group, () => {null: []})
          .putIfAbsent(l.section, () => [])
          .add(l);
    }
    return _toGroups(groups);
  } catch (_) {
    return null;
  }
}
