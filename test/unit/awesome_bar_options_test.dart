import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/awesome_bar_option.dart';
import 'package:multimax/app/data/services/awesome_bar_service.dart';
import 'package:multimax/app/data/utils/awesome_bar_query.dart';

GlobalSearchTarget _target(String d, String route,
        {Map<String, dynamic>? newArgs}) =>
    GlobalSearchTarget(
      doctype: d,
      label: '${d}s',
      icon: Icons.circle,
      color: Colors.blue,
      route: route,
      argsFor: (id) => {'name': id, 'mode': 'view'},
      newArgs: newArgs,
    );

final AwesomeBarRegistry kRegistry = AwesomeBarRegistry(
  doctypes: const [
    AwesomeBarDoctype(
        doctype: 'Delivery Note', label: 'Delivery Note', listRoute: '/dn'),
    AwesomeBarDoctype(doctype: 'Item', label: 'Item', listRoute: '/item'),
    AwesomeBarDoctype(
        doctype: 'Stock Entry', label: 'Stock Entry', listRoute: '/se'),
    AwesomeBarDoctype(
        doctype: 'Attendance',
        label: 'Attendance',
        listRoute: '/att',
        canSearch: false),
  ],
  reports: const [
    AwesomeBarReport(
        name: 'Stock Balance',
        label: 'Stock Balance',
        route: '/sb',
        guardDoctype: 'Stock Entry'),
  ],
  pages: const [AwesomeBarPage(title: 'Theme', route: '/theme')],
  targets: [
    _target('Delivery Note', '/dn/form',
        newArgs: const {'name': '', 'mode': 'new'}),
    _target('Item', '/item/form'),
    _target('Stock Entry', '/se/form',
        newArgs: const {'name': '', 'mode': 'new'}),
  ],
);

bool? _allow(String d, String p) => null;

List<AwesomeBarOption> _assemble(String q,
        {AwesomeBarCanAccess? canAccess,
        List<AwesomeBarRecent> recents = const [],
        Map<String, int> visits = const {},
        String? currentDoctype}) =>
    AwesomeBarService.assembleOptions(
      q,
      registry: kRegistry,
      canAccess: canAccess ?? _allow,
      recents: recents,
      visits: visits,
      currentDoctype: currentDoctype,
    );

Iterable<AwesomeBarOption> _ofType(
        List<AwesomeBarOption> o, AwesomeBarOptionType t) =>
    o.where((e) => e.type == t);

void main() {
  group('assembleOptions', () {
    test('"new deliv" offers only creatable DocTypes', () {
      final o = _assemble('new deliv');
      final news = _ofType(o, AwesomeBarOptionType.newDoc).toList();
      expect(news.map((e) => e.doctype), ['Delivery Note']);
      expect(news.single.route, '/dn/form');
      expect(news.single.arguments, {'name': '', 'mode': 'new'});
      expect(news.single.label, 'New Delivery Note');
      expect(_ofType(o, AwesomeBarOptionType.list), isEmpty);
    });

    test('"new" never offers a DocType without a create contract', () {
      final o = _assemble('new item');
      expect(_ofType(o, AwesomeBarOptionType.newDoc), isEmpty);
    });

    test('"stock in item" → "Find stock in Item" with the query argument',
        () {
      final o = _assemble('stock in item');
      final finds = _ofType(o, AwesomeBarOptionType.inList).toList();
      expect(finds.length, 1);
      expect(finds.single.label, 'Find stock in Item');
      expect(finds.single.route, '/item');
      expect(finds.single.arguments, {kAwesomeBarQueryArg: 'stock'});
    });

    test('"x in <list without search>" opens the list without a query', () {
      final o = _assemble('late in attendance');
      final find = _ofType(o, AwesomeBarOptionType.inList).single;
      expect(find.route, '/att');
      expect(find.arguments, isNull);
    });

    test('a query ending in "in" is not a search-in-list', () {
      final o = _assemble('stock in');
      expect(_ofType(o, AwesomeBarOptionType.inList), isEmpty);
    });

    test('"item list" keeps only the List option (set_specifics)', () {
      final o = _assemble('item list');
      final lists = _ofType(o, AwesomeBarOptionType.list).toList();
      expect(lists.map((e) => e.doctype), ['Item']);
      expect(lists.single.label, 'Item List');
      expect(lists.single.route, '/item');
      expect(_ofType(o, AwesomeBarOptionType.newDoc), isEmpty);
      expect(_ofType(o, AwesomeBarOptionType.report), isEmpty);
    });

    test('"delivery note new" keeps only the New option', () {
      final o = _assemble('delivery note new');
      expect(_ofType(o, AwesomeBarOptionType.newDoc).single.doctype,
          'Delivery Note');
      expect(_ofType(o, AwesomeBarOptionType.list), isEmpty);
    });

    test('a plain DocType query yields List + New, report and page hits', () {
      final o = _assemble('st');
      final lists = _ofType(o, AwesomeBarOptionType.list).map((e) => e.doctype);
      expect(lists, contains('Stock Entry'));
      expect(_ofType(o, AwesomeBarOptionType.newDoc).map((e) => e.doctype),
          contains('Stock Entry'));
      expect(_ofType(o, AwesomeBarOptionType.report).single.label,
          'Report Stock Balance');
      // "st" is not in "Theme".
      expect(_ofType(o, AwesomeBarOptionType.page), isEmpty);
      expect(_ofType(_assemble('the'), AwesomeBarOptionType.page).single.label,
          'Open Theme');
    });

    test('New sorts just below its List for the same DocType', () {
      final o = _assemble('deliv');
      final list = _ofType(o, AwesomeBarOptionType.list).single;
      final create = _ofType(o, AwesomeBarOptionType.newDoc).single;
      expect(list.index, closeTo(create.index + 0.035, 1e-9));
      expect(o.indexOf(list), lessThan(o.indexOf(create)));
    });

    test('denied read hides a DocType; unknown (null) keeps it', () {
      bool? deny(String d, String p) => d == 'Delivery Note' ? false : null;
      final denied = _assemble('deliv', canAccess: deny);
      expect(_ofType(denied, AwesomeBarOptionType.list), isEmpty);
      expect(_ofType(denied, AwesomeBarOptionType.newDoc), isEmpty);

      final unknown = _assemble('deliv');
      expect(_ofType(unknown, AwesomeBarOptionType.list).single.doctype,
          'Delivery Note');
    });

    test('denied create hides only the New option', () {
      bool? deny(String d, String p) => p == 'create' ? false : null;
      final o = _assemble('deliv', canAccess: deny);
      expect(_ofType(o, AwesomeBarOptionType.list).single.doctype,
          'Delivery Note');
      expect(_ofType(o, AwesomeBarOptionType.newDoc), isEmpty);
    });

    test('denied report permission hides the report', () {
      bool? deny(String d, String p) => p == 'report' ? false : null;
      expect(_ofType(_assemble('st', canAccess: deny),
          AwesomeBarOptionType.report), isEmpty);
    });

    test('every query carries "Search for" and ends with Help', () {
      final o = _assemble('deliv');
      final search = _ofType(o, AwesomeBarOptionType.search).single;
      expect(search.label, 'Search for deliv');
      expect(search.payload, 'deliv');
      expect(o.last.type, AwesomeBarOptionType.help);
    });

    test('the flat list is sorted by index descending', () {
      final o = _assemble('deliv');
      for (var i = 1; i < o.length; i++) {
        expect(o[i - 1].index, greaterThanOrEqualTo(o[i].index));
      }
    });

    test('a calculation adds the calculator row', () {
      final o = _assemble('(55 + 434) / 4');
      final calc = _ofType(o, AwesomeBarOptionType.calculator).single;
      expect(calc.payload, '122.25');
      expect(calc.label, '(55 + 434) / 4 = 122.25');
      expect(calc.index, AwesomeBarService.kCalculatorIndex);
    });

    test('a non-calculation adds no calculator row', () {
      expect(_ofType(_assemble('12abc'), AwesomeBarOptionType.calculator),
          isEmpty);
      expect(_ofType(_assemble('1/0'), AwesomeBarOptionType.calculator),
          isEmpty);
    });

    test('"Find in current list" only from a list screen, without " in"', () {
      final o = _assemble('kA-1', currentDoctype: 'Delivery Note');
      final cur = _ofType(o, AwesomeBarOptionType.current).single;
      expect(cur.label, 'Find kA-1 in Delivery Note');
      expect(cur.route, '/dn');
      expect(cur.arguments, {kAwesomeBarQueryArg: 'kA-1'});
      expect(cur.index, AwesomeBarService.kCurrentIndex);

      expect(_ofType(_assemble('kA-1'), AwesomeBarOptionType.current),
          isEmpty);
      expect(
          _ofType(_assemble('x in item', currentDoctype: 'Delivery Note'),
              AwesomeBarOptionType.current),
          isEmpty);
    });

    test('whitespace is trimmed and collapsed', () {
      final o = _assemble('  item    list ');
      expect(_ofType(o, AwesomeBarOptionType.list).single.label, 'Item List');
      expect(_ofType(o, AwesomeBarOptionType.search).single.payload,
          'item list');
    });

    test('a single character shows recents, not nav options', () {
      const rec = AwesomeBarRecent(
          kind: 'form', name: 'Delivery Note', docname: 'KA-DN-1');
      final o = _assemble('d', recents: const [rec]);
      expect(_ofType(o, AwesomeBarOptionType.search), isEmpty);
      final recent = _ofType(o, AwesomeBarOptionType.recent).single;
      expect(recent.label, 'Delivery Note KA-DN-1');
      expect(recent.route, '/dn/form');
      expect(recent.arguments, {'name': 'KA-DN-1', 'mode': 'view'});
      expect(recent.recent, isTrue);
      expect(o.last.type, AwesomeBarOptionType.help);
    });

    test('empty query lists recents newest first then frequent links', () {
      const recents = [
        AwesomeBarRecent(kind: 'form', name: 'Item', docname: 'FG-2'),
        AwesomeBarRecent(kind: 'list', name: 'Delivery Note', route: '/dn'),
        AwesomeBarRecent(kind: 'report', name: 'Stock Balance', route: '/sb'),
        AwesomeBarRecent(kind: 'page', name: 'Theme', route: '/theme'),
      ];
      final o = _assemble('', recents: recents, visits: {
        'list:Stock Entry:': 7,
      });
      final labels = o.map((e) => e.label).toList();
      expect(labels, [
        'Item FG-2',
        'Delivery Note List',
        'Stock Balance Report',
        'Theme',
        'Stock Entry List',
        'Help on Search',
      ]);
      // Frequent links carry their visit count as index, not the recent 80.
      expect(o[4].index, 7);
      expect(o[4].recent, isFalse);
    });

    test('a recent whose DocType the app no longer routes is dropped', () {
      const rec = AwesomeBarRecent(kind: 'form', name: 'Gone', docname: 'X');
      expect(_ofType(_assemble('', recents: const [rec]),
          AwesomeBarOptionType.recent), isEmpty);
    });

    test('recents match on substring, case-insensitively, "-" as space', () {
      const rec = AwesomeBarRecent(
          kind: 'form', name: 'Delivery Note', docname: 'KA-DN-0012');
      expect(_ofType(_assemble('dn 0012', recents: const [rec]),
          AwesomeBarOptionType.recent).length, 1);
      expect(_ofType(_assemble('ka-dn', recents: const [rec]),
          AwesomeBarOptionType.recent).length, 1);
      expect(_ofType(_assemble('zzz', recents: const [rec]),
          AwesomeBarOptionType.recent), isEmpty);
    });
  });

  group('deduplicate', () {
    AwesomeBarOption opt(String key, double index, {bool recent = false}) =>
        AwesomeBarOption(
          type: AwesomeBarOptionType.list,
          match: key,
          value: key,
          index: index,
          dedupeKey: key,
          recent: recent,
        );

    test('a higher non-recent duplicate replaces the earlier option', () {
      final out = AwesomeBarService.deduplicate([opt('a', 5), opt('a', 9)]);
      expect(out.single.index, 9);
    });

    test('a lower duplicate is dropped', () {
      final out = AwesomeBarService.deduplicate([opt('a', 5), opt('a', 3)]);
      expect(out.single.index, 5);
    });

    test('a recent never displaces an existing option', () {
      final out = AwesomeBarService.deduplicate(
          [opt('a', 5), opt('a', 90, recent: true)]);
      expect(out.single.index, 5);
      expect(out.single.recent, isFalse);
    });

    test('options without a key are always kept', () {
      final out = AwesomeBarService.deduplicate([
        AwesomeBarService.makeGlobalSearch('x'),
        AwesomeBarService.makeGlobalSearch('x'),
      ]);
      expect(out.length, 2);
    });
  });

  group('documentOptions', () {
    test('maps routable hits and drops the rest', () {
      final out = AwesomeBarService.documentOptions(
        const [
          GlobalSearchHit(
              doctype: 'Delivery Note',
              name: 'KA-DN-1',
              content: 'Customer : Acme ||| Remarks : none'),
          GlobalSearchHit(doctype: 'Unknown', name: 'X', content: ''),
        ],
        'acme',
        kRegistry,
      );
      expect(out.length, 1);
      expect(out.single.type, AwesomeBarOptionType.document);
      expect(out.single.route, '/dn/form');
      expect(out.single.arguments, {'name': 'KA-DN-1', 'mode': 'view'});
      expect(out.single.description, 'Customer: Acme');
      expect(out.single.dedupeKey, 'form:Delivery Note/KA-DN-1');
    });

    test('appendGlobalResults keeps a recent over the same document', () {
      const rec = AwesomeBarRecent(
          kind: 'form', name: 'Delivery Note', docname: 'KA-DN-1');
      final nav = _assemble('ka', recents: const [rec]);
      final docs = AwesomeBarService.documentOptions(
        const [
          GlobalSearchHit(
              doctype: 'Delivery Note', name: 'KA-DN-1', content: ''),
        ],
        'ka',
        kRegistry,
      );
      final all = AwesomeBarService.appendGlobalResults(nav, docs);
      final same = all.where((o) => o.docname == 'KA-DN-1').toList();
      expect(same.length, 1);
      expect(same.single.type, AwesomeBarOptionType.recent);
    });
  });
}
