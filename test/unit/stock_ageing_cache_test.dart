import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';

void main() {
  const scope = (site: 'https://one.example/Tenant', user: 'Buyer');
  late Directory dir;
  late StockAgeingCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stock_ageing_cache_test');
    cache = StockAgeingCache(directory: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final snapshot = StockAgeingSnapshot(
    fetchedAt: DateTime(2026, 11, 14, 9, 42),
    columns: const [
      {'fieldname': 'range1', 'label': 'Age (0 - 90)'},
    ],
    rows: const [
      {'item_code': '1000030', 'qty': 22.0, 'brand': null},
    ],
    defaults: const {'company': 'Multimax', 'to_date': '2026-11-14'},
  );

  test('round trip preserves rows, columns, defaults and fetch time', () async {
    await cache.write(scope, snapshot);
    final back = await cache.read(scope);
    expect(back, isNotNull);
    expect(back!.fetchedAt, snapshot.fetchedAt);
    expect(back.rows, snapshot.rows);
    expect(back.columns, snapshot.columns);
    expect(back.defaults, snapshot.defaults);
  });

  test('no file reads as null', () async {
    expect(await cache.read(scope), isNull);
  });

  test('a corrupt file reads as null', () async {
    await cache.write(scope, snapshot);
    final file = await dir
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .single;
    await file.writeAsString('{oops');
    expect(await cache.read(scope), isNull);
  });

  test('valid JSON of the wrong shape reads as null', () async {
    await cache.write(scope, snapshot);
    final file = await dir
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .single;
    await file.writeAsString('[1, 2]');
    expect(await cache.read(scope), isNull);
  });

  test('clear removes the snapshot', () async {
    await cache.write(scope, snapshot);
    await cache.clear(scope);
    expect(await cache.read(scope), isNull);
  });

  test('a different user or site cannot read the same cache', () async {
    await cache.write(scope, snapshot);
    expect(await cache.read((site: scope.site, user: 'Seller')), isNull);
    expect(
      await cache.read((site: 'https://two.example/Tenant', user: scope.user)),
      isNull,
    );
    expect(await cache.read(scope), isNotNull);
  });

  test('unowned legacy and a mismatched payload are ignored', () async {
    final legacy = File('${dir.path}/stock_ageing_custom.json');
    final releasedBytes = utf8.encode(
      '{"fetched_at":"2026-11-01T09:42:00.000",'
      '"columns":[{"fieldname":"qty","label":"Quantité ancienne"}],'
      '"rows":[{"item_code":"Previous account item","qty":19}],'
      '"defaults":{"company":"Previous company","to_date":"2026-11-01"}}',
    );
    await legacy.writeAsBytes(releasedBytes);
    expect(await cache.read(scope), isNull);
    expect(await cache.read((site: scope.site, user: 'Seller')), isNull);
    expect(
      await cache.read((site: 'https://two.example/Tenant', user: scope.user)),
      isNull,
    );
    await cache.write(scope, snapshot);
    final file = await dir
        .list()
        .where(
          (entry) =>
              entry is File && !entry.path.endsWith('stock_ageing_custom.json'),
        )
        .cast<File>()
        .single;
    final raw = await file.readAsString();
    await file.writeAsString(
      raw.replaceAll('"user":"Buyer"', '"user":"Other"'),
    );
    expect(await cache.read(scope), isNull);
    expect(await legacy.readAsBytes(), releasedBytes);
  });
}
