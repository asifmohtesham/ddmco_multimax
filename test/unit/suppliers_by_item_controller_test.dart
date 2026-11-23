import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';

class _ReportAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <Map<String, String>>[];
  int status = 200;
  Map<String, Object> response = {
    'message': {'result': []},
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final encoded = await utf8.decoder.bind(requestStream!).join();
    bodies.add(Uri.splitQueryString(encoded));
    return ResponseBody.fromString(
      jsonEncode(response),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _EmptyApi extends ApiProvider {
  @override
  Future<List<SuppliersByItemNode>> runSuppliersByItem(
    SuppliersByItemFilters filters,
  ) async => [];
}

void main() {
  late SuppliersByItemController controller;
  late ApiProvider api;
  late _ReportAdapter adapter;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('suppliers_report_');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => dir.path,
        );
  });

  setUp(() async {
    api = ApiProvider();
    await api.initDio();
    adapter = _ReportAdapter();
    api.dio.httpClientAdapter = adapter;
    controller = SuppliersByItemController(api: api);
    addTearDown(() => api.dio.close(force: true));
  });

  test('posts all six selected filters with date-only values', () async {
    await controller.run(
      filters: SuppliersByItemFilters(
        items: ['ITEM-1', 'ITEM-2'],
        variantOf: ['TEMPLATE-1'],
        suppliers: ['SUP-1', 'SUP-2'],
        warehouses: ['Stores - MM'],
        fromDate: DateTime(2026, 11, 2, 18, 30),
        toDate: DateTime(2026, 11, 20),
      ),
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/method/frappe.desk.query_report.run');
    final body = adapter.bodies.single;
    expect(body['report_name'], 'Suppliers by Item');
    expect(jsonDecode(body['filters']!), {
      'items': ['ITEM-1', 'ITEM-2'],
      'variant_of': ['TEMPLATE-1'],
      'suppliers': ['SUP-1', 'SUP-2'],
      'warehouses': ['Stores - MM'],
      'from_date': '2026-11-02',
      'to_date': '2026-11-20',
    });
    expect(controller.error.value, isNull);
    expect(controller.activeFilters, {
      'items': '2 selected',
      'variant_of': 'TEMPLATE-1',
      'suppliers': '2 selected',
      'warehouses': 'Stores - MM',
      'from_date': '2026-11-02',
      'to_date': '2026-11-20',
    });
  });

  test('runs without optional filters and with a one-sided date', () async {
    await controller.run();
    expect(jsonDecode(adapter.bodies.single['filters']!), isEmpty);

    await controller.run(
      filters: SuppliersByItemFilters(toDate: DateTime(2026, 11, 22)),
    );
    expect(jsonDecode(adapter.bodies.last['filters']!), {
      'to_date': '2026-11-22',
    });
  });

  test('rejects a reversed date range before sending a request', () async {
    await controller.run(
      filters: SuppliersByItemFilters(
        fromDate: DateTime(2026, 11, 3),
        toDate: DateTime(2026, 11, 2),
      ),
    );
    expect(adapter.requests, isEmpty);
    expect(
      controller.error.value,
      SuppliersByItemReportException.invalidDateRange,
    );
    expect(controller.isLoading.value, isFalse);
  });

  test('uses its preset filters on the initial run', () async {
    adapter.response = {
      'message': {
        'result': [
          {'node_id': 'template:TEMPLATE-1', 'indent': 0},
          {
            'node_id': 'item:ITEM-1',
            'parent_id': 'template:TEMPLATE-1',
            'indent': 1,
          },
          {
            'node_id': 'supplier:ITEM-1:SUP-1',
            'parent_id': 'item:ITEM-1',
            'indent': 2,
          },
        ],
      },
    };
    final preset = SuppliersByItemController(
      api: api,
      initialFilters: const SuppliersByItemFilters(variantOf: ['TEMPLATE-1']),
    );
    final finished = preset.isLoading.stream.firstWhere((loading) => !loading);
    preset.onInit();
    await finished;

    expect(jsonDecode(adapter.bodies.single['filters']!), {
      'variant_of': ['TEMPLATE-1'],
    });
    expect(preset.nodes.single.row.template, 'TEMPLATE-1');
    expect(preset.error.value, isNull);
  });

  test('gives a role-specific message for a forbidden response', () async {
    adapter.status = 403;
    adapter.response = {'exc_type': 'PermissionError'};

    await controller.run();

    expect(controller.error.value, SuppliersByItemReportException.denied);
    expect(controller.isLoading.value, isFalse);
  });

  testWidgets('keeps a stacked Item report separate from the earlier report', (
    tester,
  ) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    Get.put<ApiProvider>(_EmptyApi());
    final controllers = <SuppliersByItemController>{};
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/',
        getPages: [
          GetPage(name: '/', page: () => const SizedBox.shrink()),
          GetPage(name: '/item', page: () => const SizedBox.shrink()),
          GetPage(
            name: AppRoutes.SUPPLIERS_BY_ITEM,
            binding: SuppliersByItemBinding(),
            page: () => Builder(
              builder: (context) {
                final controller = Get.find<SuppliersByItemController>(
                  tag: SuppliersByItemBinding.tagForRoute(
                    ModalRoute.of(context),
                  ),
                );
                controllers.add(controller);
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );

    unawaited(Get.toNamed<void>(AppRoutes.SUPPLIERS_BY_ITEM));
    await tester.pumpAndSettle();
    final first = controllers.single;
    expect(first.filters.value.items, isEmpty);

    unawaited(Get.toNamed<void>('/item'));
    await tester.pumpAndSettle();
    unawaited(
      Get.toNamed<void>(
        AppRoutes.SUPPLIERS_BY_ITEM,
        arguments: const SuppliersByItemFilters(items: ['ITEM-1']),
      ),
    );
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    final second = controllers.last;
    expect(second.filters.value.items, ['ITEM-1']);
    expect(first.filters.value.items, isEmpty);

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(second.isClosed, isTrue);
    expect(first.isClosed, isFalse);
  });
}
