import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart';

Response _response(Map<String, dynamic> message) => Response(
      requestOptions: RequestOptions(path: '/'),
      data: {'message': message},
    );

Map<String, dynamic> _message({
  Map<String, dynamic>? customFilters,
  List<Map<String, dynamic>> rows = const [
    {'item_code': 'A', 'qty': 1}
  ],
}) =>
    {
      'columns': [
        {'fieldname': 'range1', 'label': 'Age (0 - 90)'},
      ],
      'result': rows,
      'custom_filters': customFilters,
    };

const _saved = {
  'company': 'Multimax',
  'to_date': '2026-11-14',
  'warehouse': 'Finished Goods - KA',
  'range': '90, 180, 360, 720',
  'show_warehouse_wise_stock': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<Map<String, dynamic>?> calls;
  List<String>? stored;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stock_ageing_ctrl_test');
    calls = [];
    stored = null;
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  StockAgeingController build(
    Future<Response> Function(Map<String, dynamic>? filters) run,
  ) =>
      StockAgeingController(
        cache: StockAgeingCache(directory: () async => dir),
        company: () => 'Session Co',
        baseUrl: () => 'https://erp.domain.com',
        loadCardFields: () => stored,
        saveCardFields: (f) => stored = f,
        run: ({Map<String, dynamic>? filters}) {
          calls.add(filters);
          return run(filters);
        },
      );

  test('untouched sheet keeps using the saved defaults', () async {
    final c = build((_) async => _response(_message(customFilters: _saved)));
    await c.runReport();
    await c.runReport();
    expect(calls, [null, null]);
    expect(c.filterControllers['warehouse']!.text, 'Finished Goods - KA');
    expect(c.activeFilters, isEmpty);
    c.onClose();
  });

  test('a changed filter sends the full set, saved extras included', () async {
    final c = build((_) async => _response(
        _message(customFilters: {..._saved, 'item_group': 'Wallets'})));
    await c.runReport();
    c.filterControllers['warehouse']!.text = '';
    await c.runReport();
    expect(calls.last, {
      'item_group': 'Wallets',
      'company': 'Multimax',
      'to_date': '2026-11-14',
      'range': '90, 180, 360, 720',
      'show_warehouse_wise_stock': 1,
    });
    expect(c.activeFilters.keys, ['warehouse']);
    c.onClose();
  });

  test('saved filters without a company or with extra keys still count as '
      'defaults', () async {
    final saved = {..._saved, 'item_group': 'Wallets'}..remove('company');
    final c = build((_) async => _response(_message(customFilters: saved)));
    await c.runReport();
    await c.runReport();
    expect(calls, [null, null]);
    c.onClose();
  });

  test('a run requested while one is in flight is queued, not dropped, and '
      'keeps the edits made meanwhile', () async {
    final first = Completer<Response>();
    var n = 0;
    final c = build((_) {
      n++;
      return n == 1
          ? first.future
          : Future.value(_response(_message(rows: const [
              {'item_code': 'B', 'qty': 2}
            ])));
    });

    final inFlight = c.runReport(); // default run, still loading
    c.filterControllers['to_date']!.text = '2026-11-01';
    c.filterControllers['range']!.text = '30, 60';
    await c.runReport(); // requested mid-flight
    expect(calls.length, 1);

    first.complete(_response(_message(customFilters: _saved)));
    await inFlight;

    expect(calls.length, 2);
    expect(calls.last?['to_date'], '2026-11-01');
    expect(calls.last?['range'], '30, 60');
    expect(c.rows.single['item_code'], 'B');
    expect(c.isLoading.value, isFalse);
    c.onClose();
  });

  test('no saved filters: nothing loops and the as-on date stays blank',
      () async {
    final c = build((_) async => _response(_message()));
    await c.runReport();
    expect(calls, [null]);
    expect(c.asOn.value, '');
    expect(c.rows.length, 1);
    c.onClose();
  });

  test('card fields start at the defaults, persist on toggle and reset',
      () async {
    final c = build((_) async => _response(_message(customFilters: _saved)));
    c.onInit();
    expect(c.cardFields, StockAgeingLogic.defaultCardFields);

    c.toggleCardField('image');
    c.toggleCardField('warehouse');
    expect(stored!.toSet(), {
      'variant_of',
      'item_name',
      'average_age',
      StockAgeingLogic.ageBarField,
      'image',
    });

    c.resetCardFields();
    expect(c.cardFields, StockAgeingLogic.defaultCardFields);
    expect(stored!.toSet(), StockAgeingLogic.defaultCardFields);
    await pumpEventQueue();
    c.onClose();
  });

  test('a saved selection is restored, columns are read from the run and '
      'image paths become absolute', () async {
    stored = ['brand'];
    final c = build((_) async => _response(_message(customFilters: _saved)));
    c.onInit();
    expect(c.cardFields, {'brand'});
    await pumpEventQueue();
    // One frozen bucket column in the fixture; the saved range has five.
    expect(c.columns.first.label, 'Age (0 - 90)');
    expect(c.columns.length, 10);
    expect(c.imageUrlOf({'image': '/files/a b.jpg'}),
        'https://erp.domain.com/files/a%20b.jpg');
    expect(c.imageUrlOf({'image': null}), isNull);
    c.onClose();
  });

  test('bucket titles follow the range in effect, not the frozen columns',
      () async {
    final c = build((_) async => _response(_message(customFilters: _saved)));
    await c.runReport();
    expect(c.buckets.map((b) => b.label),
        ['0 - 90', '91 - 180', '181 - 360', '361 - 720', '721 - Above']);

    c.filterControllers['range']!.text = '360, 720';
    await c.runReport();
    expect(calls.last?['range'], '360, 720');
    expect(c.buckets.map((b) => b.label),
        ['0 - 360', '361 - 720', '721 - Above']);
    expect(
        c.columns.map((x) => x.label).where((l) => l.startsWith('Value')),
        ['Value (0 - 360)', 'Value (361 - 720)', 'Value (721 - Above)']);

    c.clearFilters();
    await pumpEventQueue();
    expect(c.buckets.length, 5);
    c.onClose();
  });
}
