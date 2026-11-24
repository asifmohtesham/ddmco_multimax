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

  test(
    'posts selected links with drafts on and BOM expansion off by default',
    () async {
      await controller.run(
        filters: const SuppliersByItemFilters(
          items: ['ITEM-1', 'ITEM-2'],
          variantOf: ['TEMPLATE-1'],
          suppliers: ['SUP-1', 'SUP-2'],
          warehouses: ['Stores - MM'],
        ),
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/method/frappe.desk.query_report.run');
      expect(request.queryParameters, isEmpty);
      final body = adapter.bodies.single;
      expect(
        body.keys,
        unorderedEquals([
          'report_name',
          'filters',
          'ignore_prepared_report',
          'are_default_filters',
        ]),
      );
      expect(body['report_name'], 'Suppliers by Item');
      expect(jsonDecode(body['filters']!), {
        'items': ['ITEM-1', 'ITEM-2'],
        'variant_of': ['TEMPLATE-1'],
        'suppliers': ['SUP-1', 'SUP-2'],
        'warehouses': ['Stores - MM'],
        'include_drafts': 1,
        'expand_bom': 0,
      });
      expect(controller.error.value, isNull);
      expect(controller.activeFilters, {
        'items': '2 selected',
        'variant_of': 'TEMPLATE-1',
        'suppliers': '2 selected',
        'warehouses': 'Stores - MM',
      });
    },
  );

  test('posts only the check filters when no links are selected', () async {
    await controller.run();
    expect(jsonDecode(adapter.bodies.single['filters']!), {
      'include_drafts': 1,
      'expand_bom': 0,
    });
    expect(controller.activeFilters, isEmpty);
  });

  test('posts drafts off and BOM expansion on, and remembers both', () async {
    await controller.run(
      filters: const SuppliersByItemFilters(
        includeDrafts: false,
        expandBom: true,
      ),
    );
    await controller.run();

    expect(adapter.bodies, hasLength(2));
    for (final body in adapter.bodies) {
      expect(jsonDecode(body['filters']!), {
        'include_drafts': 0,
        'expand_bom': 1,
      });
    }
    expect(controller.activeFilters, {
      'include_drafts': 'Off',
      'expand_bom': 'On',
    });
  });

  test(
    'warehouse-scoped balance keeps the same supplier rows and matches',
    () async {
      Map<String, Object> reportResponse(num balance) => {
        'message': {
          'result': [
            {
              'node_id': 'item:ITEM-1',
              'balance_qty': balance,
              'stock_uom': 'Nos',
              'supplier_count': 2,
            },
            {
              'node_id': 'supplier:ITEM-1:SUP-1',
              'parent_id': 'item:ITEM-1',
              'matched_supplier': 1,
            },
            {
              'node_id': 'supplier:ITEM-1:SUP-2',
              'parent_id': 'item:ITEM-1',
              'matched_supplier': 0,
            },
          ],
        },
      };

      const expectedSuppliers = [('SUP-1', true), ('SUP-2', false)];
      List<(String?, bool)> supplierMatches(SuppliersByItemNode item) => [
        for (final child in item.children)
          (child.row.supplier, child.row.matchedSupplier),
      ];

      adapter.response = reportResponse(16.5);
      await controller.run(
        filters: const SuppliersByItemFilters(suppliers: ['SUP-1']),
      );
      final allWarehouses = controller.nodes.single;
      expect(allWarehouses.row.balanceQty, 16.5);
      expect(supplierMatches(allWarehouses), expectedSuppliers);

      adapter.response = reportResponse(4);
      await controller.run(
        filters: const SuppliersByItemFilters(
          suppliers: ['SUP-1'],
          warehouses: ['Stores - MM'],
        ),
      );
      final selectedWarehouses = controller.nodes.single;
      expect(selectedWarehouses.row.balanceQty, 4);
      expect(supplierMatches(selectedWarehouses), expectedSuppliers);
      expect(jsonDecode(adapter.bodies.last['filters']!), {
        'suppliers': ['SUP-1'],
        'warehouses': ['Stores - MM'],
        'include_drafts': 1,
        'expand_bom': 0,
      });
      expect(controller.error.value, isNull);
    },
  );

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
      'include_drafts': 1,
      'expand_bom': 0,
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
        arguments: const SuppliersByItemFilters(
          items: ['ITEM-1'],
          expandBom: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    final second = controllers.last;
    expect(second.filters.value.items, ['ITEM-1']);
    expect(second.filters.value.expandBom, isTrue);
    expect(first.filters.value.items, isEmpty);
    expect(first.filters.value.expandBom, isFalse);

    Get.back<void>();
    await tester.pumpAndSettle();
    expect(second.isClosed, isTrue);
    expect(first.isClosed, isFalse);
  });
}
