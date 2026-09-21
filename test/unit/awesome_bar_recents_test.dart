import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/awesome_bar_option.dart';
import 'package:multimax/app/data/services/awesome_bar_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';

/// Minimal GetStorage stand-in for [StorageService.withStorage].
class FakeBox {
  final Map<String, dynamic> data = {};
  T? read<T>(String key) => data[key] as T?;
  Future<void> write(String key, dynamic value) async => data[key] = value;
  Future<void> remove(String key) async => data.remove(key);
  bool hasData(String key) => data.containsKey(key);
}

AwesomeBarRecent _form(String docname) =>
    AwesomeBarRecent(kind: 'form', name: 'Delivery Note', docname: docname);

final AwesomeBarRegistry kRegistry = AwesomeBarRegistry(
  doctypes: const [
    AwesomeBarDoctype(
        doctype: 'Delivery Note', label: 'Delivery Note', listRoute: '/dn'),
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
    GlobalSearchTarget(
      doctype: 'Delivery Note',
      label: 'Delivery Notes',
      icon: Icons.circle,
      color: Colors.blue,
      route: '/dn/form',
      argsFor: (id) => {'name': id, 'mode': 'view'},
    ),
    GlobalSearchTarget(
      doctype: 'Item',
      label: 'Items',
      icon: Icons.circle,
      color: Colors.blue,
      route: '/item/form',
      argsFor: (id) => {'itemCode': id},
    ),
  ],
);

void main() {
  group('push', () {
    test('newest first, capped at 20, deduplicated', () {
      var list = <AwesomeBarRecent>[];
      for (var i = 0; i < 25; i++) {
        list = AwesomeBarRecentsStore.push(list, _form('DN-$i'));
      }
      expect(list.length, AwesomeBarRecentsStore.kMaxRecents);
      expect(list.first.docname, 'DN-24');
      expect(list.last.docname, 'DN-5');

      list = AwesomeBarRecentsStore.push(list, _form('DN-10'));
      expect(list.length, AwesomeBarRecentsStore.kMaxRecents);
      expect(list.first.docname, 'DN-10');
      expect(list.where((r) => r.docname == 'DN-10').length, 1);
    });
  });

  group('bump', () {
    test('increments and drops the least visited past the cap', () {
      var counts = <String, int>{};
      counts = AwesomeBarRecentsStore.bump(counts, 'a');
      counts = AwesomeBarRecentsStore.bump(counts, 'a');
      counts = AwesomeBarRecentsStore.bump(counts, 'b');
      expect(counts, {'a': 2, 'b': 1});

      counts = AwesomeBarRecentsStore.bump(counts, 'c', max: 2);
      expect(counts.length, 2);
      expect(counts.containsKey('a'), isTrue);
    });
  });

  group('recentForRoute', () {
    test('a form route with a name records a form recent', () {
      final r = AwesomeBarRecentsStore.recentForRoute(
          '/dn/form', {'name': 'KA-DN-1', 'mode': 'view'}, kRegistry)!;
      expect(r.kind, 'form');
      expect(r.name, 'Delivery Note');
      expect(r.docname, 'KA-DN-1');
    });

    test('Item forms use itemCode', () {
      final r = AwesomeBarRecentsStore.recentForRoute(
          '/item/form', {'itemCode': 'FG-1'}, kRegistry)!;
      expect(r.docname, 'FG-1');
    });

    test('a form in new mode or without a name is not a visit', () {
      expect(
          AwesomeBarRecentsStore.recentForRoute(
              '/dn/form', {'name': '', 'mode': 'new'}, kRegistry),
          isNull);
      expect(
          AwesomeBarRecentsStore.recentForRoute('/dn/form', null, kRegistry),
          isNull);
    });

    test('list, report and page routes record their kind', () {
      expect(AwesomeBarRecentsStore.recentForRoute('/dn', null, kRegistry)!.kind,
          'list');
      expect(
          AwesomeBarRecentsStore.recentForRoute('/sb', null, kRegistry)!.kind,
          'report');
      expect(
          AwesomeBarRecentsStore.recentForRoute('/theme', null, kRegistry)!
              .kind,
          'page');
    });

    test('unknown routes are ignored', () {
      expect(AwesomeBarRecentsStore.recentForRoute('/home', null, kRegistry),
          isNull);
      expect(AwesomeBarRecentsStore.recentForRoute('', null, kRegistry),
          isNull);
    });
  });

  group('AwesomeBarRecentsStore (persisted)', () {
    late FakeBox box;
    late StorageService storage;

    setUp(() {
      box = FakeBox();
      storage = StorageService.withStorage(box);
    });

    AwesomeBarRecentsStore storeFor(String user) =>
        AwesomeBarRecentsStore(storage: storage, user: () => user);

    test('records, lists and counts per user', () async {
      final a = storeFor('a@x.com');
      final b = storeFor('b@x.com');
      await a.record(_form('DN-1'));
      await a.record(_form('DN-2'));
      await a.record(_form('DN-1'));

      expect(a.list().map((r) => r.docname), ['DN-1', 'DN-2']);
      expect(a.visits(), {'form:Delivery Note:DN-1': 2, 'form:Delivery Note:DN-2': 1});
      expect(b.list(), isEmpty);
      expect(b.visits(), isEmpty);
    });

    test('survives a JSON round trip', () async {
      final a = storeFor('a@x.com');
      await a.record(const AwesomeBarRecent(
          kind: 'list', name: 'Delivery Note', route: '/dn'));
      final again = storeFor('a@x.com').list().single;
      expect(again.kind, 'list');
      expect(again.name, 'Delivery Note');
      expect(again.route, '/dn');
    });

    test('clear forgets only that user', () async {
      final a = storeFor('a@x.com');
      final b = storeFor('b@x.com');
      await a.record(_form('DN-1'));
      await b.record(_form('DN-9'));
      await a.clear('a@x.com');
      expect(a.list(), isEmpty);
      expect(a.visits(), isEmpty);
      expect(b.list().single.docname, 'DN-9');
    });

    test('recordRoute resolves through the registry', () async {
      final a = storeFor('a@x.com');
      await a.recordRoute('/dn/form', {'name': 'KA-DN-1', 'mode': 'view'},
          registry: kRegistry);
      await a.recordRoute('/home', null, registry: kRegistry);
      expect(a.list().single.docname, 'KA-DN-1');
    });

    test('no user → nothing recorded, nothing listed', () async {
      final none = AwesomeBarRecentsStore(storage: storage, user: () => null);
      await none.record(_form('DN-1'));
      expect(none.list(), isEmpty);
      expect(box.data, isEmpty);
    });

    test('corrupt stored rows are skipped', () {
      box.data['awesome_bar_recent::a@x.com'] = [
        {'kind': 'form', 'name': 'Delivery Note', 'docname': 'DN-1'},
        {'kind': 'form'},
        'junk',
      ];
      expect(storeFor('a@x.com').list().single.docname, 'DN-1');
    });
  });
}
