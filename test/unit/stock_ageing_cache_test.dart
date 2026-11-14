import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';

void main() {
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
      {'fieldname': 'range1', 'label': 'Age (0 - 90)'}
    ],
    rows: const [
      {'item_code': '1000030', 'qty': 22.0, 'brand': null}
    ],
    defaults: const {'company': 'Multimax', 'to_date': '2026-11-14'},
  );

  test('round trip preserves rows, columns, defaults and fetch time',
      () async {
    await cache.write(snapshot);
    final back = await cache.read();
    expect(back, isNotNull);
    expect(back!.fetchedAt, snapshot.fetchedAt);
    expect(back.rows, snapshot.rows);
    expect(back.columns, snapshot.columns);
    expect(back.defaults, snapshot.defaults);
  });

  test('no file reads as null', () async {
    expect(await cache.read(), isNull);
  });

  test('a corrupt file reads as null', () async {
    await File('${dir.path}/stock_ageing_custom.json').writeAsString('{oops');
    expect(await cache.read(), isNull);
  });

  test('valid JSON of the wrong shape reads as null', () async {
    await File('${dir.path}/stock_ageing_custom.json').writeAsString('[1, 2]');
    expect(await cache.read(), isNull);
  });

  test('clear removes the snapshot', () async {
    await cache.write(snapshot);
    await cache.clear();
    expect(await cache.read(), isNull);
  });
}
