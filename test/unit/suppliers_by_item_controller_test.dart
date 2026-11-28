import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_layout.dart';

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
  Future<SuppliersByItemReport> runSuppliersByItemReport(
    SuppliersByItemFilters filters,
  ) async => const SuppliersByItemReport(nodes: []);
}

class _ReportApi extends Fake implements ApiProvider {
  final requests = <SuppliersByItemFilters>[];
  late Future<List<SuppliersByItemNode>> Function() respond;

  @override
  Future<SuppliersByItemReport> runSuppliersByItemReport(
    SuppliersByItemFilters filters,
  ) async {
    requests.add(filters);
    return SuppliersByItemReport(nodes: await respond());
  }
}

List<SuppliersByItemNode> _variants({
  bool withBom = false,
  bool withDuplicatePair = false,
}) => SuppliersByItemNode.parseRows([
  {
    'node_id': 'template:ALS',
    'row_type': 'template',
    'template': 'ALS',
    'tree_label': 'ALS',
  },
  {
    'node_id': 'item:2002906',
    'parent_id': 'template:ALS',
    'row_type': 'item',
    'item_code': '2002906',
    'tree_label': '2002906',
  },
  {
    'node_id': 'supplier:edge',
    'parent_id': 'item:2002906',
    'row_type': 'supplier',
    'supplier': 'EDGE',
    'tree_label': 'EDGE',
    'open_order_qty': 2,
  },
  {
    'node_id': 'supplier:other',
    'parent_id': 'item:2002906',
    'row_type': 'supplier',
    'supplier': 'OTHER',
    'tree_label': 'OTHER',
  },
  if (withDuplicatePair)
    {
      'node_id': 'supplier:other:duplicate',
      'parent_id': 'item:2002906',
      'row_type': 'supplier',
      'supplier': 'OTHER',
      'tree_label': 'OTHER',
    },
  {
    'node_id': 'item:2002907',
    'parent_id': 'template:ALS',
    'row_type': 'item',
    'item_code': '2002907',
    'tree_label': '2002907',
  },
  if (withBom) ...[
    {
      'node_id': 'bom:owner',
      'parent_id': 'item:2002906',
      'row_type': 'bom',
      'bom_no': 'BOM-OWNER',
      'tree_label': 'BOM-OWNER',
    },
    {
      'node_id': 'component:first',
      'parent_id': 'bom:owner',
      'row_type': 'component',
      'item_code': 'FIRST',
      'tree_label': 'FIRST',
    },
    {
      'node_id': 'bom:nested',
      'parent_id': 'component:first',
      'row_type': 'bom',
      'bom_no': 'BOM-NESTED',
      'tree_label': 'BOM-NESTED',
    },
    {
      'node_id': 'component:deep',
      'parent_id': 'bom:nested',
      'row_type': 'component',
      'item_code': 'DEEP-COMPONENT',
      'tree_label': 'DEEP-COMPONENT',
    },
    {
      'node_id': 'supplier:deep',
      'parent_id': 'component:deep',
      'row_type': 'supplier',
      'supplier': 'SUPPLIED-COMPONENT',
      'tree_label': 'SUPPLIED-COMPONENT',
      'open_order_qty': 1,
    },
  ],
]);

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

  test(
    'guards double refresh and permission retry keeps all six server filters',
    () async {
      const filters = SuppliersByItemFilters(
        items: [' 2002906 '],
        variantOf: ['ALS'],
        suppliers: ['EDGE'],
        warehouses: ['Main - A'],
        includeDrafts: false,
        expandBom: true,
      );
      final denied = Completer<List<SuppliersByItemNode>>();
      final api = _ReportApi()..respond = () => denied.future;
      final report = SuppliersByItemController(
        api: api,
        initialFilters: filters,
      );
      addTearDown(report.onClose);

      final pending = report.run();
      expect(report.isLoading.value, isTrue);
      expect(report.canExpandAll, isFalse);
      await report.run();
      expect(api.requests, hasLength(1));
      denied.completeError(
        const SuppliersByItemReportException(
          SuppliersByItemReportException.denied,
          permissionDenied: true,
        ),
      );
      await pending;
      expect(report.error.value, SuppliersByItemReportException.denied);
      expect(report.hasLoaded, isFalse);
      expect(report.isLoading.value, isFalse);

      api.respond = () async => _variants();
      await report.run();
      expect(report.error.value, isNull);
      expect(report.hasLoaded, isTrue);
      expect(report.activeFilters, {
        'items': '2002906',
        'variant_of': 'ALS',
        'suppliers': 'EDGE',
        'warehouses': 'Main - A',
        'include_drafts': 'Off',
        'expand_bom': 'On',
      });
      for (final request in api.requests) {
        expect(request.toJson(), {
          'items': ['2002906'],
          'variant_of': ['ALS'],
          'suppliers': ['EDGE'],
          'warehouses': ['Main - A'],
          'include_drafts': 0,
          'expand_bom': 1,
        });
      }
    },
  );

  test(
    'search forces one owner trail, retains other suppliers and restores browse state',
    () async {
      final api = _ReportApi()..respond = () async => _variants();
      final report = SuppliersByItemController(api: api);
      report.onInit();
      addTearDown(report.onClose);
      await Future<void>.delayed(Duration.zero);
      const template = 'template:ALS';
      const variant = 'item:2002906';
      const evidence = 'supplier:edge';

      expect(report.isExpanded(template), isTrue);
      expect(report.isExpanded(variant), isFalse);
      report.toggleBranch(template);
      report.setQuery('  als 2002906 edge  ');
      expect(report.search!.matchingItemIds, {(nodeId: variant)});
      expect(report.isExpanded(template), isTrue);
      expect(report.isExpanded(variant), isTrue);
      expect(report.visibleRows.rows.map((row) => row.sourceKey.nodeId), [
        template,
        variant,
        evidence,
        'supplier:other',
      ]);
      report.toggleSupplier(evidence);
      expect(report.isSupplierExpanded(evidence), isTrue);
      report.collapseAll();
      expect(report.isExpanded(template), isTrue);
      expect(report.isExpanded(variant), isTrue);
      expect(report.isSupplierExpanded(evidence), isFalse);
      report.toggleSupplier(evidence);
      await report.setFieldVisible(
        SuppliersByItemField.searchMatchCount,
        false,
      );
      expect(
        report.fieldVisibility.shows(SuppliersByItemField.searchMatchCount),
        isFalse,
      );
      expect(report.search!.matchingItemIds, hasLength(1));
      await report.resetFields();
      expect(report.visibleRows.rows.first.sourceKey.nodeId, template);
      expect(report.visibleRows.rows.first.variantCount, 2);
      report.setQuery('  ');
      expect(report.search, isNull);
      expect(report.isExpanded(template), isFalse);
      expect(report.isExpanded(variant), isFalse);
      expect(report.isSupplierExpanded(evidence), isFalse);
      expect(api.requests, hasLength(1));
    },
  );

  test(
    'Collapse all in search preserves branches outside the retained results',
    () async {
      final api = _ReportApi()
        ..respond = () async => SuppliersByItemNode.parseRows([
          for (final code in ['ITEM-AX', 'ITEM-BY']) ...[
            {'node_id': 'item:$code', 'row_type': 'item', 'item_code': code},
            {
              'node_id': 'bom:$code',
              'parent_id': 'item:$code',
              'row_type': 'bom',
              'bom_no': 'BOM-$code',
            },
            {
              'node_id': 'component:$code',
              'parent_id': 'bom:$code',
              'row_type': 'component',
              'item_code': 'COMPONENT',
            },
          ],
        ]);
      final report = SuppliersByItemController(
        api: api,
        initialFilters: const SuppliersByItemFilters(expandBom: true),
      );
      addTearDown(report.onClose);
      await report.run();

      report.setQuery('ITEM');
      for (final code in ['ITEM-AX', 'ITEM-BY']) {
        report.toggleBranch('item:$code');
        report.toggleBranch('bom:$code');
        expect(report.isExpanded('bom:$code'), isTrue);
      }
      report.setQuery('ITEM-AX');
      report.collapseAll();
      expect(report.isExpanded('item:ITEM-AX'), isFalse);
      expect(report.isExpanded('bom:ITEM-AX'), isFalse);

      report.setQuery('ITEM-BY');
      expect(report.isExpanded('item:ITEM-BY'), isTrue);
      expect(report.isExpanded('bom:ITEM-BY'), isTrue);
      expect(
        report.visibleRows.indexByKey,
        contains((nodeId: 'component:ITEM-BY')),
      );
    },
  );

  test(
    'keeps browse expansion on refresh and resets query on a changed filter',
    () async {
      final api = _ReportApi()..respond = () async => _variants();
      final report = SuppliersByItemController(api: api);
      addTearDown(report.onClose);
      await report.run();
      const template = 'template:ALS';
      expect(report.isExpanded(template), isTrue);
      report.toggleBranch(template);
      await report.run();
      expect(report.isExpanded(template), isFalse);

      report.setQuery('nothing matches');
      expect(report.visibleRows.rows, isEmpty);
      expect(report.search!.matchingItemIds, isEmpty);
      expect(report.nodes.single.children, hasLength(2));
      final revision = report.loadedRevision.value;
      api.respond = () async => [];
      await report.run(
        filters: const SuppliersByItemFilters(items: ['absent']),
      );
      expect(report.loadedRevision.value, revision + 1);
      expect(report.filterRevision.value, 1);
      expect(report.query.value, isEmpty);
      expect(report.search, isNull);
      expect(report.nodes, isEmpty);
      expect(report.hasLoaded, isTrue);
      expect(report.error.value, isNull);
      expect(api.requests, hasLength(3));
    },
  );

  test(
    'Supplier search and sorting preserve per-mode hierarchy and pair details',
    () async {
      final api = _ReportApi()..respond = () async => _variants(withBom: true);
      final report = SuppliersByItemController(
        api: api,
        initialFilters: const SuppliersByItemFilters(expandBom: true),
      );
      addTearDown(report.onClose);
      await report.refreshFieldsScope();
      await report.run();
      const template = 'template:ALS';
      const variant = 'item:2002906';
      const edgePair = (nodeId: 'supplier:edge');
      const otherPair = (nodeId: 'supplier:other');
      const deepPair = (nodeId: 'supplier:deep');

      report.toggleBranch(variant);
      report.togglePair(edgePair);
      expect(report.isPairExpanded(edgePair), isTrue);
      report.toggleBranch(template);
      await report.setGroup(SuppliersByItemGroup.supplier);
      expect(report.isExpanded(template), isFalse);
      final firstGroup = report.visibleRows.rows.first.key;
      expect(report.isBranchExpanded(firstGroup), isTrue);
      final edge = report.visibleRows.rows.singleWhere(
        (row) => row.pairKey == edgePair,
      );
      expect(report.isPairExpanded(edgePair), isTrue);
      expect(report.isBranchExpanded(edge.key), isFalse);

      report.expandAll();
      final other = report.visibleRows.rows.singleWhere(
        (row) => row.pairKey == otherPair,
      );
      final component = report.visibleRows.rows.lastWhere(
        (row) => row.pairKey == deepPair,
      );
      expect(report.isBranchExpanded(other.key), isTrue);
      expect(report.isBranchExpanded(edge.key), isTrue);
      report.toggleBranchKey(edge.key);
      expect(report.isBranchExpanded(other.key), isTrue);
      report.toggleBranchKey(other.ancestorKeys.first);
      report.toggleBranchKey(component.ancestorKeys.first);
      expect(report.isBranchExpanded(component.ancestorKeys.first), isFalse);

      report.setQuery('2002906 BOM-NESTED supplied-component');
      expect(report.search!.matchingItemIds, {(nodeId: variant)});
      expect(report.isBranchExpanded(component.ancestorKeys.first), isTrue);
      expect(report.canToggleBranchKey(component.ancestorKeys.first), isFalse);
      expect(report.visibleRows.indexByKey, contains(component.key));
      report.expandAll();
      expect(report.visibleRows.indexByKey, contains(other.key));
      report.collapseAll();
      expect(report.visibleRows.indexByKey, contains(component.key));
      expect(report.visibleRows.indexByKey, isNot(contains(other.key)));

      await report.setSortField(SuppliersByItemSortField.lastPurchase);
      await report.setSortDirection(SuppliersByItemSortDirection.asc);
      expect(report.visibleRows.indexByKey, contains(component.key));
      await report.setGroup(SuppliersByItemGroup.template);
      expect(report.query.value, '2002906 BOM-NESTED supplied-component');
      expect(report.isExpanded(template), isTrue);
      expect(report.isExpanded('bom:nested'), isTrue);
      await report.setGroup(SuppliersByItemGroup.supplier);
      expect(report.visibleRows.indexByKey, contains(component.key));
      report.setQuery('');
      expect(report.isBranchExpanded(firstGroup), isTrue);
      expect(report.isBranchExpanded(edge.key), isFalse);
      expect(report.isBranchExpanded(component.ancestorKeys.first), isFalse);
      expect(report.isPairExpanded(edgePair), isTrue);
      await report.setGroup(SuppliersByItemGroup.template);
      expect(report.isExpanded(template), isFalse);
      expect(report.isExpanded(variant), isTrue);
      expect(report.isPairExpanded(edgePair), isTrue);
      expect(api.requests, hasLength(1));
    },
  );

  test(
    'Supplier refresh preserves explicit collapse until the ERP filters change',
    () async {
      final api = _ReportApi()..respond = () async => _variants();
      final report = SuppliersByItemController(api: api);
      addTearDown(report.onClose);
      await report.refreshFieldsScope();
      await report.setGroup(SuppliersByItemGroup.supplier);
      await report.run();
      final firstGroup = report.visibleRows.rows.first.key;
      expect(report.isBranchExpanded(firstGroup), isTrue);
      report.toggleBranchKey(firstGroup);
      await report.run();
      expect(report.isBranchExpanded(firstGroup), isFalse);

      report.setQuery('edge');
      expect(report.isBranchExpanded(firstGroup), isTrue);
      await report.run(
        filters: const SuppliersByItemFilters(items: ['2002906']),
      );
      expect(report.query.value, isEmpty);
      expect(report.view.value.group, SuppliersByItemGroup.supplier);
      expect(report.isBranchExpanded(firstGroup), isTrue);
      expect(api.requests, hasLength(3));
    },
  );

  test('regroup reveals an equivalent pair and the owner fallback', () async {
    final api = _ReportApi()
      ..respond = () async => _variants(withDuplicatePair: true);
    final report = SuppliersByItemController(api: api);
    addTearDown(report.onClose);
    await report.refreshFieldsScope();
    await report.run();
    const owner = (nodeId: 'item:2002906');
    const edge = (nodeId: 'supplier:edge');
    const other = (nodeId: 'supplier:other');
    const otherDuplicate = (nodeId: 'supplier:other:duplicate');
    await report.setGroup(SuppliersByItemGroup.supplier);
    final edgeOccurrence = report.visibleRows.rows.singleWhere(
      (row) => row.pairKey == edge,
    );
    expect(report.visibleRows.rows.any((row) => row.pairKey == other), isFalse);
    final otherOccurrence = report.revealAnchorOccurrence(
      key: otherDuplicate,
      ownerKey: owner,
      pairKey: otherDuplicate,
    );
    expect(otherOccurrence, isNotNull);
    expect(otherOccurrence, isNot(edgeOccurrence.key));
    expect(report.visibleRows.indexByKey, contains(otherOccurrence));
    expect(
      report.visibleRows.rows
          .singleWhere((row) => row.key == otherOccurrence)
          .pairKey,
      other,
    );
    expect(
      report.revealAnchorOccurrence(key: owner, ownerKey: owner),
      edgeOccurrence.key,
    );
    await report.setGroup(SuppliersByItemGroup.template);
    expect(
      report.revealAnchorOccurrence(
        key: otherOccurrence!,
        ownerKey: owner,
        pairKey: other,
      ),
      other,
    );
    expect(report.visibleRows.indexByKey, contains(other));
    expect(api.requests, hasLength(1));
  });

  test(
    'regroup reveals the same BOM structure within the owner copy',
    () async {
      final api = _ReportApi()..respond = () async => _variants(withBom: true);
      final report = SuppliersByItemController(
        api: api,
        initialFilters: const SuppliersByItemFilters(expandBom: true),
      );
      addTearDown(report.onClose);
      await report.refreshFieldsScope();
      await report.run();
      const owner = (nodeId: 'item:2002906');
      const nestedBom = (nodeId: 'bom:nested');
      await report.setGroup(SuppliersByItemGroup.supplier);
      final nestedCopy = report.revealAnchorOccurrence(
        key: nestedBom,
        ownerKey: owner,
      );
      final visibleCopy = report.visibleRows.rows.singleWhere(
        (row) => row.key == nestedCopy,
      );
      expect(nestedCopy, isNot(nestedBom));
      expect(visibleCopy.sourceKey, nestedBom);
      expect(visibleCopy.ownerKey, owner);
      expect(visibleCopy.ancestorKeys, hasLength(4));
      expect(
        report.visibleRows.rows.where(
          (row) => row.pairKey == (nodeId: 'supplier:other'),
        ),
        isEmpty,
      );
      await report.setGroup(SuppliersByItemGroup.template);
      expect(
        report.revealAnchorOccurrence(
          key: nestedCopy!,
          sourceKey: visibleCopy.sourceKey,
          ownerKey: visibleCopy.ownerKey,
        ),
        nestedBom,
      );
      expect(report.visibleRows.indexByKey, contains(nestedBom));
      expect(api.requests, hasLength(1));
    },
  );

  test(
    'Supplier search keeps detached supplier evidence with other rows',
    () async {
      const detached = (nodeId: 'detached:supplier');
      final api = _ReportApi()
        ..respond = () async => [
          ..._variants(),
          ...SuppliersByItemNode.parseRows([
            {
              'node_id': detached.nodeId,
              'parent_id': 'missing-owner',
              'row_type': 'supplier',
              'supplier': 'DETACHED-ONLY',
              'tree_label': 'DETACHED-ONLY',
            },
          ]),
        ];
      final report = SuppliersByItemController(api: api);
      addTearDown(report.onClose);
      await report.refreshFieldsScope();
      await report.run();
      await report.setGroup(SuppliersByItemGroup.supplier);
      report.setQuery('detached-only');
      expect(report.search!.matchingItemIds, isEmpty);
      expect(report.search!.matchingOtherIds, {detached});
      expect(report.visibleRows.rows, hasLength(2));
      expect(report.visibleRows.rows.first.group?.isOther, isTrue);
      expect(report.visibleRows.rows.last.sourceKey, detached);
    },
  );

  group('applyScan', () {
    Item item(String code, {String name = '', String? variantOf}) => Item(
      name: name,
      itemName: 'Item $code',
      itemCode: code,
      itemGroup: 'Products',
      variantOf: variantOf,
    );

    Future<SuppliersByItemController> report(
      _ReportApi api,
      Future<Item?> Function(String) resolve, {
      SuppliersByItemFilters filters = const SuppliersByItemFilters(),
    }) async {
      final report = SuppliersByItemController(
        api: api,
        initialFilters: filters,
        resolveBarcode: resolve,
      );
      addTearDown(report.onClose);
      await report.run();
      return report;
    }

    test('replaces the Item selection and keeps the other filters', () async {
      final api = _ReportApi()..respond = () async => _variants();
      final lookups = <String>[];
      final scanned = await report(
        api,
        (code) async {
          lookups.add(code);
          return item('2002906', name: 'ITEM-2002906');
        },
        filters: const SuppliersByItemFilters(
          items: ['OLD'],
          variantOf: ['OLD-TEMPLATE'],
          suppliers: ['EDGE'],
          warehouses: ['Stores - KA'],
          includeDrafts: false,
          expandBom: true,
        ),
      );
      scanned.setQuery('edge');

      expect(
        await scanned.applyScan(' 20029068 '),
        SuppliersByItemScanOutcome.applied,
      );

      expect(lookups, ['20029068']);
      expect(api.requests, hasLength(2));
      expect(api.requests.last.toJson(), {
        'items': ['ITEM-2002906'],
        'suppliers': ['EDGE'],
        'warehouses': ['Stores - KA'],
        'include_drafts': 0,
        'expand_bom': 1,
      });
      expect(scanned.activeFilters['items'], 'ITEM-2002906');
      expect(scanned.activeFilters.containsKey('variant_of'), isFalse);
      expect(scanned.query.value, isEmpty);
      expect(scanned.scanning.value, isFalse);
    });

    test('a variant selects its template', () async {
      final api = _ReportApi()..respond = () async => _variants();
      final scanned = await report(
        api,
        (_) async => item('2002906', variantOf: 'ALS'),
        filters: const SuppliersByItemFilters(items: ['OLD']),
      );

      await scanned.applyScan('20029068');

      expect(api.requests.last.items, isEmpty);
      expect(api.requests.last.variantOf, ['ALS']);
    });

    test(
      'an unmatched code and a failed lookup leave the report alone',
      () async {
        final api = _ReportApi()..respond = () async => _variants();
        var fail = false;
        final scanned = await report(
          api,
          (_) async => fail ? throw StateError('offline') : null,
          filters: const SuppliersByItemFilters(items: ['2002906']),
        );
        final revision = scanned.loadedRevision.value;

        expect(
          await scanned.applyScan('99999999'),
          SuppliersByItemScanOutcome.notFound,
        );
        fail = true;
        expect(
          await scanned.applyScan('99999999'),
          SuppliersByItemScanOutcome.failed,
        );

        expect(api.requests, hasLength(1));
        expect(scanned.filters.value.items, ['2002906']);
        expect(scanned.loadedRevision.value, revision);
        expect(scanned.hasLoaded, isTrue);
        expect(scanned.error.value, isNull);
        expect(scanned.scanning.value, isFalse);
      },
    );

    test(
      'drops a scan while busy, when empty, or without a resolver',
      () async {
        final api = _ReportApi()..respond = () async => _variants();
        final lookup = Completer<Item?>();
        var lookups = 0;
        final scanned = await report(api, (_) {
          lookups++;
          return lookup.future;
        });

        expect(
          await scanned.applyScan('  '),
          SuppliersByItemScanOutcome.ignored,
        );
        final first = scanned.applyScan('20029068');
        expect(scanned.scanning.value, isTrue);
        expect(
          await scanned.applyScan('20029075'),
          SuppliersByItemScanOutcome.ignored,
        );
        lookup.complete(item('2002906'));
        expect(await first, SuppliersByItemScanOutcome.applied);
        expect(lookups, 1);
        expect(api.requests, hasLength(2));

        final loading = Completer<List<SuppliersByItemNode>>();
        api.respond = () => loading.future;
        final running = scanned.run();
        expect(
          await scanned.applyScan('20029068'),
          SuppliersByItemScanOutcome.ignored,
        );
        loading.complete(_variants());
        await running;
        expect(lookups, 1);

        final plain = SuppliersByItemController(api: api);
        addTearDown(plain.onClose);
        expect(plain.canScan, isFalse);
        expect(
          await plain.applyScan('20029068'),
          SuppliersByItemScanOutcome.ignored,
        );
      },
    );
  });
}
