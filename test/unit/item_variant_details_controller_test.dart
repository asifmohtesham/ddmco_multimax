import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

class _NamesApi extends Fake implements ApiProvider {
  final requests =
      <
        ({
          List<String> codes,
          CancelToken? token,
          Completer<Map<String, String>> reply,
        })
      >[];

  @override
  Future<Map<String, String>> getItemNames(
    List<String> itemCodes, {
    CancelToken? cancelToken,
  }) {
    final reply = Completer<Map<String, String>>();
    requests.add((codes: itemCodes, token: cancelToken, reply: reply));
    return reply.future;
  }

  @override
  Future<ItemVariantDetailsResult> getItemVariantDetails({
    List<String> items = const [],
    List<String> itemGroups = const [],
    List<String> warehouses = const [],
  }) async => (
    columns: <Map<String, dynamic>>[],
    rows: [
      for (var i = 0; i < 802; i++) {'variant_name': 'Code-$i'},
    ],
  );
}

class _DetailFieldsApi extends ApiProvider {
  List<String>? requestedFields;

  @override
  Future<List<Map<String, dynamic>>> getList(
    String? positional, {
    String? doctype,
    Map<String, dynamic>? filters,
    List<String>? fields,
    int limit = 20,
    String orderBy = 'modified desc',
    String? groupBy = '',
    String? filterDoctype,
  }) async {
    requestedFields = fields;
    return [
      {
        'name': 'A',
        'item_name': 'Belt A',
        'item_group': 'Belts',
        'image': '/files/belt.png',
      },
    ];
  }
}

class _EmptyStorage {
  Object? read(String key) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _NamesApi api;
  late ItemVariantDetailsController controller;

  setUp(() {
    api = Get.put<ApiProvider>(_NamesApi()) as _NamesApi;
    controller = Get.put(
      ItemVariantDetailsController(
        storage: StorageService.withStorage(_EmptyStorage()),
      ),
    );
    controller.filterControllers['item']!.text = 'Example';
  });
  tearDown(Get.reset);

  test('Item detail enrichment fetches image URLs', () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => 'build');
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final fieldsApi = _DetailFieldsApi();
    await Future<void>.delayed(Duration.zero);
    final withImage = await fieldsApi.getItemDetails(['A']);
    expect(fieldsApi.requestedFields, contains('image'));
    expect(withImage['A']?['image'], '/files/belt.png');
  });

  Future<void> startSearch() async {
    await controller.runReport();
    controller.search('target');
    await Future<void>.delayed(const Duration(milliseconds: 275));
  }

  List<String> matches() => controller
      .visibleGroups(controller.results.value, controller.query.value, false)
      .expand((group) => group.variants)
      .map(variantCode)
      .toList();

  Map<String, String> names(List<String> codes) => {
    for (final code in codes)
      code: code == 'Code-1' || code == 'Code-801' ? 'Target Name' : 'Belt',
  };

  test(
    'finds unseen names progressively and caches them for later searches',
    () async {
      await startSearch();
      expect(controller.nameProgress.value, (done: 0, total: 802));
      expect(matches(), isEmpty);
      final first = api.requests.first;
      first.reply.complete(names(first.codes));
      await Future<void>.delayed(Duration.zero);
      expect(controller.nameProgress.value, (done: 800, total: 802));
      expect(matches(), ['Code-1']);
      final second = api.requests.last;
      second.reply.complete(names(second.codes));
      await Future<void>.delayed(Duration.zero);
      expect(controller.nameProgress.value, isNull);
      expect(controller.nameSearchIncomplete.value, isFalse);
      expect(matches(), ['Code-1', 'Code-801']);
      controller.search('target name');
      await Future<void>.delayed(const Duration(milliseconds: 275));
      expect(matches(), ['Code-1', 'Code-801']);
      expect(api.requests, hasLength(2));
    },
  );

  test('a new report cancels the request and ignores late names', () async {
    await startSearch();
    final old = api.requests.single;
    await controller.runReport();
    expect(old.token!.isCancelled, isTrue);
    expect(controller.nameProgress.value, isNull);
    old.reply.complete(names(old.codes));
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, hasLength(1));
    expect(controller.nameProgress.value, isNull);
    controller.search('target');
    await Future<void>.delayed(const Duration(milliseconds: 275));
    expect(controller.nameProgress.value, (done: 0, total: 802));
    expect(matches(), isEmpty);
    expect(api.requests, hasLength(2));
    api.requests.last.reply.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.nameSearchIncomplete.value, isTrue);
    expect(controller.nameProgress.value, isNull);
  });

  test('collapsed summary uses server stock and filtered variant counts', () {
    final data = VariantResults([
      {
        'variant_name': 'Belt',
        'indent': 0,
        'current_stock': 5,
        'stock_uom': 'Nos',
      },
      {'variant_name': 'A', 'indent': 1, 'current_stock': 5},
      {'variant_name': 'B', 'indent': 1, 'current_stock': 0},
      {'variant_name': 'Mixed', 'indent': 0, 'current_stock': null},
      {'variant_name': 'C', 'indent': 1, 'current_stock': 7},
    ], []);
    final belt = data.groups.first;
    expect(
      belt.collapsedSummary(2, filtered: false),
      '2 variants \u00b7 Current Stock 5 Nos',
    );
    for (final match in [
      data.filter(query: 'Target', names: {'B': 'Target'}).single,
      data.filter(inStock: true).first,
    ]) {
      expect(
        match.group.collapsedSummary(match.variants.length, filtered: true),
        '1 of 2 \u00b7 Current Stock 5 Nos',
      );
    }
    expect(data.groups.last.collapsedSummary(1, filtered: false), '1 variant');
  });

  test('large lists allow thumb seeking when every heading is collapsed', () {
    expect(canDragVariantScrollbar(500, collapsed: false), isTrue);
    expect(canDragVariantScrollbar(501, collapsed: false), isFalse);
    expect(canDragVariantScrollbar(7496, collapsed: true), isTrue);
  });
}
