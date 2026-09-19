import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

List<String> _titles(List<NavGroup> g) => [for (final x in g) x.title];
List<String> _links(NavGroup g) => [for (final l in g.links) l.linkTo];

void main() {
  test('no workspaces → built-in fallback layout', () {
    final m = buildWorkspaceMenu(const [], const {});
    expect(_titles(m), ['Stock', 'Buying', 'Manufacturing', 'Selling', 'HR']);
    expect(m.first.sections.map((s) => s.label), [null, 'Reports']);
    expect(m.expand((g) => g.links).length, kNavCatalog.length);
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
    expect(keys.toSet().length, kNavCatalog.length);
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
