import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

List<String> _titles(List<NavGroup> g) => [for (final x in g) x.title];
List<String> _links(NavGroup g) => [for (final l in g.links) l.linkTo];

// Search-only catalog entries (showInDrawer: false) never reach the drawer.
final _drawerLinkCount = kNavCatalog.where((l) => l.showInDrawer).length;

void main() {
  test('no workspaces → built-in fallback layout', () {
    final m = buildWorkspaceMenu(const [], const {});
    expect(_titles(m), ['Stock', 'Buying', 'Manufacturing', 'Selling', 'HR']);
    expect(m.first.sections.map((s) => s.label), [null, 'Reports', 'Tools']);
    expect(m.expand((g) => g.links).length, _drawerLinkCount);
  });

  test('workspace order, cards and child pages drive layout', () {
    final pages = [
      {'name': 'Buying', 'title': 'Buying', 'module': 'Buying', 'is_hidden': 0},
      {'name': 'Stock', 'title': 'Stock', 'module': 'Stock', 'is_hidden': 0},
      {'name': 'Stock Reports', 'title': 'Stock Reports', 'module': 'Stock',
        'parent_page': 'Stock'},
      {'name': 'Hidden', 'title': 'Hidden', 'is_hidden': 1},
      {'name': 'Accounting', 'title': 'Accounting', 'module': 'Accounts'},
    ];
    final desktop = {
      'Buying': {
        'shortcuts': {'items': [
          {'type': 'DocType', 'link_to': 'Purchase Order'},
          {'type': 'DocType', 'link_to': 'Item'}, // native to Stock
          {'type': 'DocType', 'link_to': 'Supplier'}, // not in app → dropped
          {'type': 'DocType', 'link_to': 'Purchase Receipt'}, // module unknown
        ]},
      },
      'Stock': {
        'shortcuts': {'items': [
          {'type': 'DocType', 'link_to': 'Stock Entry'},
        ]},
        'cards': {'items': [
          {'label': 'Items Catalogue', 'links': [
            {'link_type': 'DocType', 'link_to': 'Item'},
          ]},
          {'label': 'Transactions', 'links': [
            {'link_type': 'DocType', 'link_to': 'Stock Entry'}, // dup
          ]},
        ]},
      },
      'Stock Reports': {
        'cards': {'items': [
          {'label': 'Key Reports', 'links': [
            {'link_type': 'Report', 'link_to': 'Stock Balance'},
          ]},
        ]},
      },
      'Hidden': {
        'shortcuts': {'items': [{'type': 'DocType', 'link_to': 'Batch'}]},
      },
      'Accounting': {'cards': {'items': []}},
    };
    final modules = {
      'doctype:Item': 'Stock',
      'doctype:Stock Entry': 'Stock',
      'doctype:Purchase Order': 'Buying',
      'doctype:Pricing Rule': 'Accounts', // listed nowhere → native group top
      'report:Stock Balance': 'Stock',
    };

    final m = buildWorkspaceMenu(pages, desktop, modules);
    final all = m.expand((g) => g.links).map((l) => l.key).toList();
    expect(all.toSet().length, all.length, reason: 'each screen once');

    expect(_titles(m),
        ['Buying', 'Stock', 'Accounting', 'Manufacturing', 'Selling', 'HR']);

    final buying = m[0];
    expect(_links(buying), ['Purchase Order', 'Purchase Receipt']);

    final stock = m[1];
    // Item sits at its native workspace's card, not Buying's shortcut.
    final catalogue = stock.sections.firstWhere((s) => s.label == 'Items Catalogue');
    expect(catalogue.links.map((l) => l.linkTo), ['Item']);
    // Shortcut wins over the later card for Stock Entry.
    expect(stock.sections.first.label, isNull);
    expect(stock.sections.first.links.first.linkTo, 'Stock Entry');
    expect(stock.sections.map((s) => s.label), isNot(contains('Transactions')));
    expect(stock.sections.map((s) => s.label), contains('Key Reports'));
    expect(_links(stock), contains('Batch')); // hidden workspace → default

    expect(_links(m[2]), ['Pricing Rule']);
    expect(_links(m.firstWhere((g) => g.title == 'Selling')),
        isNot(contains('Pricing Rule')));
  });

  group("Desk's breadcrumb workspace decides a module's group", () {
    // Sidebar order puts Invoicing first; Desk's breadcrumb (oldest public
    // workspace of the module) says Accounting.
    final pages = [
      {'name': 'Invoicing', 'title': 'Invoicing', 'module': 'Accounts'},
      {'name': 'Accounting', 'title': 'Accounting', 'module': 'Accounts'},
      {'name': 'Payables', 'title': 'Payables', 'module': 'Accounts',
        'parent_page': 'Accounting'},
    ];
    final desktop = {
      'Invoicing': {
        'cards': {'items': [
          {'label': 'Pricing', 'links': [
            {'link_type': 'DocType', 'link_to': 'Pricing Rule'},
          ]},
        ]},
      },
    };
    const modules = {'doctype:Pricing Rule': 'Accounts'};
    final desk = DeskBoot(moduleWorkspaces: moduleWorkspacesFromRows([
      {'name': 'Accounting', 'module': 'Accounts'},
      {'name': 'Invoicing', 'module': 'Accounts'},
      {'name': 'Payables', 'module': 'Accounts'},
      {'name': 'Stock', 'module': 'Stock'},
    ]));

    NavGroup groupOf(List<NavGroup> m, String doctype) =>
        m.firstWhere((g) => g.links.any((l) => l.linkTo == doctype));

    test('without Desk data, sidebar order decides (old behaviour)', () {
      final m = buildWorkspaceMenu(pages, desktop, modules);
      expect(groupOf(m, 'Pricing Rule').title, 'Invoicing');
    });

    test('Pricing Rule lands under Accounting, not Invoicing', () {
      final m = buildWorkspaceMenu(pages, desktop, modules, desk);
      final accounting = groupOf(m, 'Pricing Rule');
      expect(accounting.title, 'Accounting');
      // Listed only on Invoicing → top of its native group.
      expect(accounting.sections.first.label, isNull);
      expect(_titles(m), isNot(contains('Invoicing')));
    });

    test('native workspace missing from the sidebar still names the group', () {
      final m = buildWorkspaceMenu(
          pages.where((p) => p['name'] != 'Accounting').toList(),
          desktop, modules, desk);
      expect(groupOf(m, 'Pricing Rule').title, 'Accounting');
    });

    test('native child workspace folds into its parent', () {
      final m = buildWorkspaceMenu(pages, desktop, modules,
          const DeskBoot(moduleWorkspaces: {
            'Accounts': ['Payables', 'Accounting'],
          }));
      expect(groupOf(m, 'Pricing Rule').title, 'Accounting');
    });

    test('no pages → fallback menu even with Desk data', () {
      expect(_titles(buildWorkspaceMenu(const [], const {}, modules, desk)),
          ['Stock', 'Buying', 'Manufacturing', 'Selling', 'HR']);
    });
  });

  group('v16: the sidebar Desk opens names the group', () {
    // v16 has no Accounting workspace; Desk's label comes from sidebars.
    final pages = [
      {'name': 'Invoicing', 'title': 'Invoicing', 'module': 'Accounts'},
      {'name': 'Selling', 'title': 'Selling', 'module': 'Selling'},
      {'name': 'Stock', 'title': 'Stock', 'module': 'Stock'},
    ];
    const modules = {
      'doctype:Pricing Rule': 'Accounts',
      'doctype:Item': 'Stock',
      'doctype:Sales Order': 'Selling',
    };
    Map<String, dynamic> sb(String label, List<String> links,
            [String app = 'erpnext']) =>
        {'label': label, 'app': app, 'items': [for (final l in links) {'link_to': l}]};

    NavGroup groupOf(List<NavGroup> m, String doctype) =>
        m.firstWhere((g) => g.links.any((l) => l.linkTo == doctype));

    test('one linking sidebar → that sidebar', () {
      final desk = DeskBoot(
        moduleWorkspaces: const {'Accounts': ['Invoicing']},
        sidebars: {'selling': sb('Selling', ['Sales Order', 'Pricing Rule'])},
        moduleApp: const {'accounts': 'erpnext', 'selling': 'erpnext'},
      );
      final m = buildWorkspaceMenu(pages, const {}, modules, desk);
      expect(groupOf(m, 'Pricing Rule').title, 'Selling');
    });

    test('several linking sidebars → the one named like the module', () {
      final desk = DeskBoot(
        sidebars: {
          'selling': sb('Selling', ['Item']),
          'stock': sb('Stock', ['Item']),
        },
        moduleApp: const {'stock': 'erpnext'},
      );
      expect(resolveDeskSidebar('Item', 'Stock', desk), 'Stock');
      // No module (Reports) → first linking sidebar.
      expect(resolveDeskSidebar('Item', null, desk), 'Selling');
    });

    test("several, none named like the module → first linking", () {
      final desk = DeskBoot(
        sidebars: {
          'buying': sb('Buying', ['Pricing Rule']),
          'selling': sb('Selling', ['Pricing Rule']),
        },
        moduleApp: const {'accounts': 'erpnext'},
      );
      expect(resolveDeskSidebar('Pricing Rule', 'Accounts', desk), 'Buying');
    });

    test("other apps' sidebars are ignored; none left → module sidebar", () {
      final desk = DeskBoot(
        sidebars: {
          'hr': sb('HR', ['Pricing Rule'], 'hrms'),
          'accounts': sb('Accounting', []),
        },
        moduleApp: const {'accounts': 'erpnext'},
      );
      expect(resolveDeskSidebar('Pricing Rule', 'Accounts', desk), 'Accounting');
    });

    test('no fitting sidebar → v15 module workspace rule', () {
      const desk = DeskBoot(moduleWorkspaces: {'Accounts': ['Invoicing']});
      final m = buildWorkspaceMenu(pages, const {}, modules, desk);
      expect(groupOf(m, 'Pricing Rule').title, 'Invoicing');
    });
  });

  group('v16: sections and order follow the sidebar', () {
    // Trimmed from erp-v16's real Stock and Selling sidebars.
    Map<String, dynamic> link(String to, {bool child = false, String type = 'DocType'}) =>
        {'type': 'Link', 'link_type': type, 'link_to': to, 'child': child ? 1 : 0};
    Map<String, dynamic> sectionBreak(String label) =>
        {'type': 'Section Break', 'label': label, 'child': 0};
    final desk = DeskBoot(
      sidebars: {
        'stock': {'label': 'Stock', 'app': 'erpnext', 'items': [
          link('Stock', type: 'Workspace'),
          link('Stock Entry'),
          link('Purchase Receipt'),
          link('Delivery Note'),
          link('Material Request'),
          sectionBreak('Tools'),
          link('Landed Cost Voucher', child: true),
          link('Packing Slip', child: true),
          sectionBreak('Setup'),
          link('Item', child: true),
          link('Batch', child: true),
          sectionBreak('Reports'),
          link('Stock Balance', child: true, type: 'Report'),
          link('Batch-Wise Balance History', child: true, type: 'Report'),
          link('Item Variant Details', child: true, type: 'Report'),
        ]},
        'selling': {'label': 'Selling', 'app': 'erpnext', 'items': [
          link('Sales Order'),
          sectionBreak('Items & Pricing'),
          link('Item', child: true),
          link('Item Price', child: true),
          link('Pricing Rule', child: true),
          link('Selling Settings'), // top-level again after a section
        ]},
      },
      moduleApp: const {'stock': 'erpnext', 'selling': 'erpnext', 'accounts': 'erpnext'},
    );
    final pages = [
      {'name': 'Selling', 'title': 'Selling', 'module': 'Selling'},
      {'name': 'Stock', 'title': 'Stock', 'module': 'Stock'},
    ];
    // Workspace cards that v16 Desk no longer shows must not leak in.
    final desktop = {
      'Stock': {
        'cards': {'items': [
          {'label': 'Items Catalogue', 'links': [
            {'link_type': 'DocType', 'link_to': 'Item'},
          ]},
          {'label': 'Stock Transactions', 'links': [
            {'link_type': 'DocType', 'link_to': 'Stock Entry'},
          ]},
        ]},
      },
    };
    const modules = {
      'doctype:Item': 'Stock',
      'doctype:Batch': 'Stock',
      'doctype:Stock Entry': 'Stock',
      'doctype:Purchase Receipt': 'Stock',
      'doctype:Delivery Note': 'Stock',
      'doctype:Material Request': 'Stock',
      'doctype:Landed Cost Voucher': 'Stock',
      'doctype:Packing Slip': 'Stock',
      'doctype:Item Price': 'Stock',
      'doctype:Pricing Rule': 'Accounts',
      'doctype:Sales Order': 'Selling',
    };

    List<String> layout(NavGroup g) => [
          for (final s in g.sections)
            '${s.label}: ${[for (final l in s.links) l.linkTo].join(', ')}'
        ];

    test('sidebarSpot reads section breaks like Desk', () {
      expect(sidebarSpot('Stock', 'Item', desk), (section: 'Setup', index: 9));
      expect(sidebarSpot('Stock', 'Stock Entry', desk)?.section, isNull);
      expect(sidebarSpot('Selling', 'Selling Settings', desk)?.section, isNull);
      expect(sidebarSpot('Selling', 'Batch', desk), isNull);
    });

    test('Stock and Selling match the v16 sidebars', () {
      final m = buildWorkspaceMenu(pages, desktop, modules, desk);
      final stock = m.firstWhere((g) => g.title == 'Stock');
      expect(layout(stock).take(4), [
        'null: Stock Entry, Purchase Receipt, Delivery Note, Material Request',
        'Tools: Landed Cost Voucher, Packing Slip',
        'Setup: Item, Batch',
        'Reports: Stock Balance, Batch-Wise Balance History, Item Variant Details',
      ]);
      expect(stock.sections.map((s) => s.label),
          isNot(anyOf(contains('Items Catalogue'), contains('Stock Transactions'))));

      final selling = m.firstWhere((g) => g.title == 'Selling');
      expect(selling.sections.firstWhere((s) => s.label == 'Items & Pricing')
          .links.map((l) => l.linkTo), ['Item Price', 'Pricing Rule']);
    });
  });

  test('reads Desk boot data embedded in /app', () {
    final boot = jsonEncode({
      'module_wise_workspaces': {
        'Accounts': ['Accounting', 'Invoicing'],
        'Stock': ['Stock'],
      },
      'workspace_sidebar_item': {
        'selling': {'label': 'Selling', 'app': 'erpnext',
          'items': [{'link_to': 'Pricing Rule'}]},
      },
      'module_app': {'accounts': 'erpnext'},
      'note': 'quotes " and </b> survive',
    });
    final html = '<script>\n'
        '  frappe.boot = JSON.parse(${jsonEncode(boot)});\n'
        '  frappe._messages = frappe.boot["__messages"];\n'
        '</script>';
    final desk = deskBootFromHtml(html)!;
    expect(desk.moduleWorkspaces, {
      'Accounts': ['Accounting', 'Invoicing'],
      'Stock': ['Stock'],
    });
    expect(desk.sidebars.keys, ['selling']);
    expect(desk.moduleApp, {'accounts': 'erpnext'});
    expect(resolveDeskSidebar('Pricing Rule', 'Accounts', desk), 'Selling');
    expect(deskBootFromHtml('<html>login</html>'), isNull);

    // v16 embeds the object directly; braces inside strings don't count.
    final v16 = '<script>\n  frappe.boot = $boot;\n  if (frappe.boot) {}\n'
        '  let x = {"a": "}"};\n</script>';
    expect(deskBootFromHtml(v16)!.moduleApp, {'accounts': 'erpnext'});
  });

  test('cached menu round-trips and heals against the current catalog', () {
    final menu = buildWorkspaceMenu([
      {'name': 'Stock', 'title': 'Stock', 'module': 'Stock'},
    ], {
      'Stock': {
        'cards': {'items': [
          {'label': 'Serial No and Batch', 'links': [
            {'link_type': 'DocType', 'link_to': 'Batch'},
          ]},
        ]},
      },
    });
    final json = menuToJson(menu);
    final back = menuFromJson(json)!;
    expect(menuToJson(back), json);

    // A removed screen is dropped; a screen missing from the cache (added in
    // a later app version) returns to its default group.
    final stale = [
      {'t': 'Stock', 's': [
        {'l': null, 'k': ['doctype:Gone', 'doctype:Item']},
      ]},
    ];
    final healed = menuFromJson(stale)!;
    final keys = healed.expand((g) => g.links).map((l) => l.key).toList();
    expect(keys, isNot(contains('doctype:Gone')));
    expect(keys.toSet().length, _drawerLinkCount);
    expect(healed.first.links.first.linkTo, 'Item');

    expect(menuFromJson(null), isNull);
    expect(menuFromJson(['garbage']), isNull);
  });

  test('only cards/shortcuts placed in the page content count', () {
    final content = jsonEncode([
      {'type': 'header', 'data': {'text': 'Stock'}},
      {'type': 'shortcut', 'data': {'shortcut_name': 'Stock Entry'}},
      {'type': 'card', 'data': {'card_name': 'Serial No and Batch'}},
    ]);
    final desktop = {
      'Stock': {
        'shortcuts': {'items': [
          {'type': 'DocType', 'link_to': 'Stock Entry', 'label': 'Stock Entry'},
          {'type': 'DocType', 'link_to': 'Item', 'label': 'Item'}, // not placed
        ]},
        'cards': {'items': [
          {'label': 'Serial No and Batch', 'links': [
            {'link_type': 'DocType', 'link_to': 'Batch'},
          ]},
          {'label': 'Custom Reports', 'links': [ // Frappe's auto card, unplaced
            {'link_type': 'Report', 'link_to': 'Stock Balance'},
          ]},
        ]},
      },
    };
    List<String?> labels(List<NavGroup> m) =>
        m.first.sections.map((s) => s.label).toList();

    final m = buildWorkspaceMenu(
        [{'name': 'Stock', 'title': 'Stock', 'content': content}], desktop);
    expect(m.first.sections.first.links.first.linkTo, 'Stock Entry');
    expect(labels(m), contains('Serial No and Batch'));
    expect(labels(m), isNot(contains('Custom Reports')));
    // Unplaced screens aren't lost — they fall back to their default spot.
    expect(m.first.sections.firstWhere((s) => s.label == 'Reports')
        .links.map((l) => l.linkTo), contains('Stock Balance'));

    // Translated labels match nothing in content → no filtering at all.
    final translated = jsonEncode([
      {'type': 'card', 'data': {'card_name': 'Seriennummer und Charge'}},
    ]);
    final t = buildWorkspaceMenu(
        [{'name': 'Stock', 'title': 'Stock', 'content': translated}], desktop);
    expect(labels(t), contains('Custom Reports'));
  });

  test('every drawer guard is prefetched at login (no skeleton flash)', () {
    for (final l in kNavCatalog) {
      expect(kAppPermissions, contains(l.guard), reason: l.title);
    }
  });
}
