import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/shared/item_sheet/rack_warehouse_resolver.dart';
import 'package:multimax/app/shared/item_sheet/rack_warehouse_rule.dart';

const _company = 'K A LLC';
const _rack = 'KA-WH-WIP1-1A';
const _warehouse = 'WH-WIP1 - KA';
const _otherWarehouse = 'WH-DXB1 - KA';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiProvider api;
  late RackWarehouseResolver resolver;
  late Map<String, (int, Object)> resources;
  late List<String> requested;

  setUp(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => 'build');
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    api = ApiProvider();
    await api.initDio();
    resolver = RackWarehouseResolver(api);
    requested = [];
    resources = {};
    api.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.uri.pathSegments.skip(2).join('/');
            requested.add(path);
            final (status, data) =
                resources[path] ?? (404, <String, dynamic>{});
            handler.resolve(
              Response(requestOptions: options, statusCode: status, data: data),
            );
          },
        ),
      );
  });

  void rack({String? link = _warehouse}) {
    resources['Rack/$_rack'] = (
      200,
      {
        'data': {'name': _rack, if (link != null) 'warehouse': link},
      },
    );
  }

  Map<String, Object> warehouse(
    String name, {
    int group = 0,
    int disabled = 0,
    String company = _company,
  }) => {
    'name': name,
    'warehouse_name': name.split(' - ').first,
    'company': company,
    'is_group': group,
    'disabled': disabled,
  };

  Future<RackPairVerdict> check({
    String label = _rack,
    String row = _warehouse,
  }) => resolver.check(
    rack: label,
    rowWarehouse: row,
    company: _company,
    side: RackSide.source,
  );

  test('stored Warehouse link wins over the rack name prefix', () async {
    rack(link: _otherWarehouse);
    resources['Warehouse/$_otherWarehouse'] = (
      200,
      {'data': warehouse(_otherWarehouse)},
    );
    final verdict = await check();
    expect(verdict.issue, RackPairIssue.mismatch);
    expect(verdict.warehouse, _otherWarehouse);
    expect((await check(row: _otherWarehouse)).isValid, isTrue);
    expect(requested, ['Rack/$_rack', 'Warehouse/$_otherWarehouse']);
  });

  test('exact lookup precedes the canonical company suffix alias', () async {
    rack();
    resources['Company/$_company'] = (
      200,
      {
        'data': {'name': _company, 'abbr': 'KA'},
      },
    );
    resources['Warehouse/$_warehouse'] = (200, {'data': warehouse(_warehouse)});
    final verdict = await check(label: '$_rack - KA');
    expect(verdict.isValid, isTrue);
    expect(verdict.rack, _rack);
    expect(requested, [
      'Rack/$_rack - KA',
      'Company/$_company',
      'Rack/$_rack',
      'Warehouse/$_warehouse',
    ]);
  });

  test(
    'missing, permission, and bad responses produce distinct outcomes',
    () async {
      expect((await check()).issue, RackPairIssue.notFound);
      resources['Rack/$_rack'] = (403, <String, dynamic>{});
      expect((await check()).issue, RackPairIssue.unavailable);
      resources['Rack/$_rack'] = (
        200,
        {
          'data': {'warehouse': _warehouse},
        },
      );
      expect((await check()).issue, RackPairIssue.unavailable);
    },
  );

  test('blank link uses the active leaf fallback', () async {
    rack(link: null);
    resources['Company/$_company'] = (
      200,
      {
        'data': {'name': _company, 'abbr': 'KA'},
      },
    );
    resources['Warehouse'] = (
      200,
      {
        'data': [warehouse(_warehouse), warehouse(_otherWarehouse)],
      },
    );
    expect((await check()).isValid, isTrue);
    expect(requested, ['Rack/$_rack', 'Company/$_company', 'Warehouse']);
  });

  test('dangling or invalid nonblank link never uses the fallback', () async {
    rack();
    expect((await check()).issue, RackPairIssue.invalidWarehouse);
    for (final record in [
      warehouse(_warehouse, group: 1),
      warehouse(_warehouse, disabled: 1),
      warehouse(_warehouse, company: 'Other Company'),
    ]) {
      api.setBaseUrl('https://example.invalid');
      resources['Warehouse/$_warehouse'] = (200, {'data': record});
      expect((await check()).issue, RackPairIssue.invalidWarehouse);
    }
    expect(requested.every((path) => !path.startsWith('Company')), isTrue);
  });

  test(
    'a server change invalidates positive cached Rack and Warehouse reads',
    () async {
      rack();
      resources['Warehouse/$_warehouse'] = (
        200,
        {'data': warehouse(_warehouse)},
      );
      expect((await check()).isValid, isTrue);
      expect((await check()).isValid, isTrue);
      expect(requested, hasLength(2));
      api.setBaseUrl('https://example.invalid');
      resources.remove('Rack/$_rack');
      expect((await check()).issue, RackPairIssue.notFound);
    },
  );
}
