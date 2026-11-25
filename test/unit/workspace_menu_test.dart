import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

List<String> _titles(List<NavGroup> groups) => [
  for (final g in groups) g.title,
];
List<String> _links(NavGroup group) => [for (final l in group.links) l.linkTo];
List<(String, String?)> _homes(List<NavGroup> menu, String key) => [
  for (final group in menu)
    for (final section in group.sections)
      for (final link in section.links)
        if (link.key == key) (group.title, section.label),
];

final _drawerLinkCount = kNavCatalog.where((l) => l.showInDrawer).length;

const _docTypeModules = {
  'Item': 'Stock',
  'Batch': 'Stock',
  'Material Request': 'Stock',
  'Stock Entry': 'Stock',
  'Delivery Note': 'Stock',
  'Packing Slip': 'Stock',
  'Landed Cost Voucher': 'Stock',
  'Purchase Receipt': 'Stock',
  'Item Price': 'Stock',
  'Purchase Order': 'Buying',
  'BOM': 'Manufacturing',
  'Work Order': 'Manufacturing',
  'Job Card': 'Manufacturing',
  'POS Upload': 'Selling',
  'Sales Order': 'Selling',
  'Pricing Rule': 'Accounts',
  'Attendance': 'HR',
  'ToDo': 'Desk',
};

const _reportModules = {
  'Batch-Wise Balance History': 'Stock',
  'Item Variant Details': 'Stock',
  'Stock Balance': 'Stock',
  'Stock Ageing - Custom': 'Stock',
  'BOM Search': 'Stock',
  'Job Card Summary': 'Manufacturing',
  'BOM Stock with Customer Code': 'Manufacturing',
  'POS and Delivery Note Item Rate': 'Stock',
  'Monthly Attendance Sheet': 'HR',
  'Shift Attendance': 'HR',
  'Employee Hours Utilization Based On Timesheet': 'HR',
};

void main() {
  for (final (type, modules) in const [
    ('DocType', _docTypeModules),
    ('Report', _reportModules),
  ]) {
    test('each catalog $type uses its server module as its group', () {
      final links = kNavCatalog.where((link) => link.linkType == type);
      expect(
        links.map((link) => link.linkTo),
        unorderedEquals(modules.keys),
        reason:
            'Keep the expected ${type}s in sync with the catalog and set '
            'each catalog group to its $type\'s server module.',
      );
      for (final link in links) {
        final module = modules[link.linkTo];
        expect(
          link.group,
          module,
          reason:
              'Set the catalog group for ${link.linkTo} to its server module '
              '($module).',
        );
      }
    });
  }

  test('no workspace pages uses catalog groups, sections and order', () {
    final menu = buildWorkspaceMenu(const []);
    expect(_titles(menu), [
      'Stock',
      'Buying',
      'Manufacturing',
      'Selling',
      'Accounts',
      'HR',
    ]);
    final stock = menu.first;
    expect(stock.sections.map((s) => s.label), [
      null,
      'Tools',
      'Pricing',
      'Reports',
    ]);
    expect(_links(stock), [
      'Item',
      'Batch',
      'Material Request',
      'Stock Entry',
      'Delivery Note',
      'Packing Slip',
      'Purchase Receipt',
      'Landed Cost Voucher',
      'Item Price',
      'Batch-Wise Balance History',
      'Item Variant Details',
      'Stock Balance',
      'Stock Ageing - Custom',
      'BOM Search',
      'POS and Delivery Note Item Rate',
    ]);
    expect(
      menu.singleWhere((g) => g.title == 'Accounts').icon,
      Icons.account_balance_rounded,
    );
    final keys = menu.expand((g) => g.links).map((l) => l.key).toList();
    expect(keys.length, _drawerLinkCount);
    expect(keys.toSet().length, _drawerLinkCount);
  });

  test('workspace pages seed group order with hidden pages ignored and '
      'child pages folded into their parent', () {
    final menu = buildWorkspaceMenu([
      {'name': 'HR', 'title': 'HR', 'is_hidden': 1},
      {'name': 'Buying', 'title': 'Buying'},
      {
        'name': 'Stock Reports',
        'title': 'Stock Reports',
        'parent_page': 'Stock',
      },
      {'name': 'Selling', 'title': 'Selling'},
      {'name': 'Stock', 'title': 'Stock'},
      {'name': 'Accounting', 'title': 'Accounting', 'module': 'Accounts'},
    ]);
    expect(_titles(menu), [
      'Buying',
      'Stock',
      'Selling',
      'Manufacturing',
      'Accounts',
      'HR',
    ]);
    expect(_links(menu.first), ['Purchase Order']);
    expect(_homes(menu, 'doctype:Item'), [('Stock', null)]);
    expect(_homes(menu, 'doctype:Stock Entry'), [('Stock', null)]);
    expect(_homes(menu, 'doctype:Purchase Receipt'), [('Stock', null)]);
    expect(_homes(menu, 'doctype:Batch'), [('Stock', null)]);
    expect(_homes(menu, 'report:Stock Balance'), [('Stock', 'Reports')]);
    expect(_homes(menu, 'doctype:Pricing Rule'), [('Accounts', 'Pricing')]);
  });

  test(
    'a Report uses its module and catalog section with or without pages',
    () {
      const modules = {
        'doctype:Pricing Rule': 'Accounts',
        'report:Stock Balance': 'Accounts',
      };
      for (final pages in const <List<Map<String, dynamic>>>[
        [],
        [
          {'name': 'Invoicing', 'title': 'Invoicing', 'module': 'Accounts'},
          {'name': 'Accounting', 'title': 'Accounting', 'module': 'Accounts'},
          {
            'name': 'Payables',
            'title': 'Payables',
            'module': 'Accounts',
            'parent_page': 'Accounting',
          },
        ],
      ]) {
        final menu = buildWorkspaceMenu(pages, modules);
        expect(_homes(menu, 'report:Stock Balance'), [('Accounts', 'Reports')]);
        expect(_homes(menu, 'doctype:Pricing Rule'), [('Accounts', 'Pricing')]);
        expect(_titles(menu), isNot(contains('Invoicing')));
        expect(_titles(menu), isNot(contains('Accounting')));
        final accounts = menu.singleWhere((g) => g.title == 'Accounts');
        expect(accounts.sections.map((s) => s.label), ['Pricing', 'Reports']);
      }
    },
  );

  test(
    'all Reports use the catalog group when their server module is unknown',
    () {
      final menu = buildWorkspaceMenu(
        const [
          {'name': 'Shift & Attendance', 'title': 'Shift & Attendance'},
        ],
        const {'report:Stock Balance': '', 'report:Shift Attendance': '  '},
      );
      for (final entry in _reportModules.entries) {
        expect(_homes(menu, 'report:${entry.key}'), [(entry.value, 'Reports')]);
      }
      expect(_titles(menu), isNot(contains('Shift & Attendance')));
    },
  );

  group('Item placement across user layouts', () {
    const selling = {
      'name': 'Selling',
      'title': 'Selling',
      'module': 'Selling',
    };
    const buying = {'name': 'Buying', 'title': 'Buying', 'module': 'Buying'};
    const stock = {'name': 'Stock', 'title': 'Stock', 'module': 'Stock'};
    const layouts = <(String, List<Map<String, dynamic>>)>[
      ('v16 with Stock and Buying blocked', [selling]),
      ('v16 with all three workspace pages', [buying, selling, stock]),
      ('v16 with reversed workspace order', [stock, selling, buying]),
      (
        'v16 with a renamed Stock page',
        [
          buying,
          selling,
          {'name': 'Inventory', 'title': 'Inventory', 'module': 'Stock'},
        ],
      ),
      (
        'v15 workspace with an Item card and shortcut',
        [
          {
            ...selling,
            'content': [
              {
                'type': 'shortcut',
                'data': {'shortcut_name': 'Item'},
              },
              {
                'type': 'card',
                'data': {'card_name': 'Workspace Items'},
              },
            ],
          },
        ],
      ),
      (
        'personal workspace with an Item card',
        [
          {
            'name': 'My Workspace',
            'title': 'My Workspace',
            'module': 'Selling',
            'public': 0,
            'for_user': 'fixture@example.com',
            'content': [
              {
                'type': 'card',
                'data': {'card_name': 'Workspace Items'},
              },
            ],
          },
        ],
      ),
    ];

    for (final (name, pages) in layouts) {
      test('$name uses the server module or catalog fallback', () {
        for (final (modules, group) in const [
          ({'doctype:Item': 'Stock'}, 'Stock'),
          ({'doctype:Item': 'Selling'}, 'Selling'),
          (<String, String>{}, 'Stock'),
        ]) {
          final menu = buildWorkspaceMenu(pages, modules);
          expect(_homes(menu, 'doctype:Item'), [
            (group, null),
          ], reason: '$modules');
        }
      });
    }
  });

  test('reads Desk boot data embedded in /app', () {
    final boot = jsonEncode({
      'user': {
        'name': 'op@example.com',
        'roles': ['Sales User'],
        'all_reports': {'Shift Attendance': {}},
      },
      'note': 'quotes " and </b> survive',
    });
    final html =
        '<script>\n'
        '  frappe.boot = JSON.parse(${jsonEncode(boot)});\n'
        '  frappe._messages = frappe.boot["__messages"];\n'
        '</script>';
    final desk = deskBootFromHtml(html)!;
    expect(desk.userId, 'op@example.com');
    expect(desk.roles, ['Sales User']);
    expect(desk.allowedReports, {'Shift Attendance'});
    expect(desk.pages, isEmpty);
    expect(deskBootFromHtml('<html>login</html>'), isNull);
  });

  group('Frappe 16.56 boot data', () {
    final boot = jsonEncode({
      'user': {
        'name': 'op@example.com',
        'roles': ['Stock User', 'Sales User', 'All', 7],
        'all_reports': {'Job Card Summary': {}},
      },
      'workspaces': {
        'pages': [
          {'name': 'Stock', 'title': 'Stock', 'module': 'Stock', 'public': 1},
          {'name': 'Hidden', 'title': 'Hidden', 'is_hidden': 1},
          'not a page',
        ],
        'has_access': true,
      },
      'allowed_reports': {'Stock Balance': {}},
      'note': 'quotes " and braces } survive',
    });
    final desk = deskBootFromHtml(
      '<script>frappe.boot = $boot; if (frappe.boot) {}</script>',
    )!;

    test('workspace pages come from boot.workspaces', () {
      expect(desk.pages.map((p) => p['name']), ['Stock', 'Hidden']);
    });

    test('session user and roles come from boot.user', () {
      expect(desk.userId, 'op@example.com');
      expect(desk.roles, ['Stock User', 'Sales User', 'All']);
    });

    test('top-level report allowlist takes precedence', () {
      expect(desk.allowedReports, {'Stock Balance'});
    });
  });

  test('cached menu round-trips and heals against the current catalog', () {
    final menu = buildWorkspaceMenu([
      {'name': 'Stock', 'title': 'Stock', 'module': 'Stock'},
    ]);
    final json = menuToJson(menu);
    final back = menuFromJson(json)!;
    expect(menuToJson(back), json);

    final stale = [
      {
        't': 'Shift & Attendance',
        's': [
          {
            'l': 'An old card',
            'k': ['report:Shift Attendance'],
          },
        ],
      },
      {
        't': 'Stock',
        's': [
          {
            'l': 'Reports',
            'k': ['report:Stock Balance', 'report:Item Variant Details'],
          },
          {
            'l': null,
            'k': ['doctype:Gone', 'doctype:Item', 'report:Shift Attendance'],
          },
        ],
      },
      {
        't': 'Selling',
        's': [
          {
            'l': 'Sales Reports',
            'k': ['report:POS and Delivery Note Item Rate'],
          },
        ],
      },
    ];
    final healed = menuFromJson(stale)!;
    final keys = healed.expand((g) => g.links).map((l) => l.key).toList();
    expect(keys, isNot(contains('doctype:Gone')));
    expect(keys.length, _drawerLinkCount);
    expect(keys.toSet().length, _drawerLinkCount);
    expect(healed.first.links.first.linkTo, 'Item');
    expect(_titles(healed), isNot(contains('Shift & Attendance')));
    expect(_homes(healed, 'report:Shift Attendance'), [('HR', 'Reports')]);
    expect(_homes(healed, 'report:POS and Delivery Note Item Rate'), [
      ('Stock', 'Reports'),
    ]);
    final stock = healed.first;
    expect(stock.sections.map((s) => s.label), [
      null,
      'Tools',
      'Pricing',
      'Reports',
    ]);
    expect(stock.sections.last.links.map((l) => l.linkTo), [
      'Batch-Wise Balance History',
      'Item Variant Details',
      'Stock Balance',
      'Stock Ageing - Custom',
      'BOM Search',
      'POS and Delivery Note Item Rate',
    ]);

    expect(menuFromJson(null), isNull);
    expect(menuFromJson(['garbage']), isNull);
  });

  test(
    'cached server Report module is available until metadata is refreshed',
    () {
      const modules = {
        'report:Shift Attendance': 'Attendance Management',
        'doctype:Item': 'Selling',
      };
      final menu = buildWorkspaceMenu(const [], modules);
      final json = menuToJson(menu, modules);
      final restored = menuFromJson(json)!;
      expect(_homes(restored, 'report:Shift Attendance'), [
        ('Attendance Management', 'Reports'),
      ]);
      expect(_homes(restored, 'doctype:Item'), [('Stock', null)]);
      expect(_homes(menuFromJson(json, const {})!, 'report:Shift Attendance'), [
        ('HR', 'Reports'),
      ]);
      expect(
        _homes(
          menuFromJson(json, const {'report:Shift Attendance': 'Stock'})!,
          'report:Shift Attendance',
        ),
        [('Stock', 'Reports')],
      );
    },
  );

  test('every drawer guard is prefetched at login (no skeleton flash)', () {
    for (final l in kNavCatalog) {
      expect(kAppPermissions, contains(l.guard), reason: l.title);
    }
  });
}
