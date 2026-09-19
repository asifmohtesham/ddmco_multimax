import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// A screen the app can open, keyed by what a Frappe Workspace links to
/// (`DocType` / `Report` + name). The workspace decides WHERE it shows;
/// [group] / [section] are only used when no workspace places it (or the
/// workspace fetch failed), so every screen stays reachable.
class NavLink {
  final String linkType; // 'DocType' | 'Report'
  final String linkTo;
  final String title;
  final IconData icon;
  final String route;
  final PermEntry guard;
  final String group;
  final String? section;

  const NavLink(this.linkType, this.linkTo, this.title, this.icon, this.route,
      this.guard, this.group, [this.section]);

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

/// Every drawer destination. Order = fallback order.
final List<NavLink> kNavCatalog = [
  NavLink('DocType', 'Item', 'Item', Icons.category_rounded, AppRoutes.ITEM, _r('Item'), 'Stock'),
  NavLink('DocType', 'Batch', 'Batch', Icons.qr_code_scanner_rounded, AppRoutes.BATCH, _r('Batch'), 'Stock'),
  NavLink('DocType', 'Material Request', 'Material Request', Icons.playlist_add_check_rounded, AppRoutes.MATERIAL_REQUEST, _r('Material Request'), 'Stock'),
  NavLink('DocType', 'Stock Entry', 'Stock Entry', Icons.compare_arrows_rounded, AppRoutes.STOCK_ENTRY, _r('Stock Entry'), 'Stock'),
  NavLink('DocType', 'Delivery Note', 'Delivery Note', Icons.local_shipping_rounded, AppRoutes.DELIVERY_NOTE, _r('Delivery Note'), 'Stock'),
  NavLink('DocType', 'Packing Slip', 'Packing Slip', Icons.assignment_return_rounded, AppRoutes.PACKING_SLIP, _r('Packing Slip'), 'Stock'),
  NavLink('Report', 'Batch-Wise Balance History', 'Batch-Wise Balance History', Icons.history_toggle_off_rounded, AppRoutes.BATCH_WISE_BALANCE, _rep('Batch'), 'Stock', 'Reports'),
  NavLink('Report', 'Item Variant Details', 'Item Variant Details', Icons.style_outlined, AppRoutes.ITEM_VARIANT_DETAILS, _rep('Item'), 'Stock', 'Reports'),
  NavLink('Report', 'Stock Balance', 'Stock Balance', Icons.account_balance_wallet_outlined, AppRoutes.STOCK_BALANCE, _rep('Stock Entry'), 'Stock', 'Reports'),
  NavLink('DocType', 'Purchase Order', 'Purchase Order', Icons.description_rounded, AppRoutes.PURCHASE_ORDER, _r('Purchase Order'), 'Buying'),
  NavLink('DocType', 'Purchase Receipt', 'Purchase Receipt', Icons.receipt_long_rounded, AppRoutes.PURCHASE_RECEIPT, _r('Purchase Receipt'), 'Buying'),
  NavLink('DocType', 'BOM', 'Bill of Materials', Icons.account_tree_rounded, AppRoutes.BOM, _r('BOM'), 'Manufacturing'),
  NavLink('DocType', 'Work Order', 'Work Order', Icons.assignment_rounded, AppRoutes.WORK_ORDER, _r('Work Order'), 'Manufacturing'),
  NavLink('DocType', 'Job Card', 'Job Card', Icons.assignment_ind_rounded, AppRoutes.JOB_CARD, _r('Job Card'), 'Manufacturing'),
  NavLink('Report', 'BOM Search', 'BOM Search', Icons.manage_search_rounded, AppRoutes.BOM_SEARCH, _rep('BOM'), 'Manufacturing', 'Reports'),
  NavLink('Report', 'Job Card Summary', 'Job Card Summary', Icons.summarize_outlined, AppRoutes.JOB_CARD_SUMMARY, _rep('Job Card'), 'Manufacturing', 'Reports'),
  NavLink('Report', 'BOM Stock with Customer Code', 'BOM Stock with Customer Code', Icons.inventory_2_outlined, AppRoutes.BOM_STOCK_CUSTOMER_CODE, _rep('BOM'), 'Manufacturing', 'Reports'),
  NavLink('DocType', 'POS Upload', 'POS Upload', Icons.cloud_upload_rounded, AppRoutes.POS_UPLOAD, _r('POS Upload'), 'Selling'),
  NavLink('DocType', 'Item Price', 'Item Price', Icons.sell_outlined, AppRoutes.ITEM_PRICE, _r('Item Price'), 'Selling', 'Pricing'),
  NavLink('DocType', 'Pricing Rule', 'Pricing Rule', Icons.discount_outlined, AppRoutes.PRICING_RULE, _r('Pricing Rule'), 'Selling', 'Pricing'),
  NavLink('Report', 'POS and Delivery Note Item Rate', 'POS & DN Item Rate', Icons.price_change_outlined, AppRoutes.POS_DN_ITEM_RATE, _rep('POS Upload'), 'Selling', 'Reports'),
  NavLink('DocType', 'Attendance', 'Attendance', Icons.how_to_reg_rounded, AppRoutes.ATTENDANCE, _r('Attendance'), 'HR'),
  NavLink('Report', 'Monthly Attendance Sheet', 'Monthly Attendance Sheet', Icons.calendar_month_rounded, AppRoutes.MONTHLY_ATTENDANCE_SHEET, _rep('Attendance'), 'HR', 'Reports'),
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
  final byKey = {for (final l in kNavCatalog) l.key: l};
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
    final byKey = {for (final l in kNavCatalog) l.key: l};
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
