import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';

class _FakeApiProvider extends ApiProvider {
  Map<String, dynamic>? getDocumentData;
  int getDocumentStatusCode = 200;

  @override
  Future<Response> getDocument(String doctype, String name) async {
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype/$name'),
      statusCode: getDocumentStatusCode,
      data: getDocumentData == null ? null : {'data': getDocumentData},
    );
  }
}

class _FakeItemProvider extends ItemProvider {
  // updateReorderLevels
  String? lastUpdateItemCode;
  Map<String, dynamic>? lastUpdatePayload;
  int updateStatusCode = 200;
  Object? throwOnUpdate;

  @override
  Future<Response> updateReorderLevels(
    String itemCode,
    Map<String, dynamic> data,
  ) async {
    lastUpdateItemCode = itemCode;
    lastUpdatePayload = data;
    if (throwOnUpdate != null) throw throwOnUpdate!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/Item/$itemCode'),
      statusCode: updateStatusCode,
    );
  }

  // getStockSettings
  dynamic autoIndentValue = 1;
  int stockSettingsStatusCode = 200;
  Object? throwOnStockSettings;

  @override
  Future<Response> getStockSettings() async {
    if (throwOnStockSettings != null) throw throwOnStockSettings!;
    return Response(
      requestOptions:
          RequestOptions(path: '/api/resource/Stock Settings/Stock Settings'),
      statusCode: stockSettingsStatusCode,
      data: {
        'data': {'auto_indent': autoIndentValue}
      },
    );
  }
}

Map<String, dynamic> _cannedItem({
  List<Map<String, dynamic>>? reorderLevels,
  int isStockItem = 1,
  String defaultType = 'Purchase',
  String modified = '2026-07-17 09:00:00',
}) =>
    {
      'name': 'ITEM-1',
      'item_name': 'Widget',
      'item_code': 'ITEM-1',
      'item_group': 'Products',
      'is_stock_item': isStockItem,
      'default_material_request_type': defaultType,
      'modified': modified,
      'reorder_levels': reorderLevels ?? const [],
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor fires _initDio(), which touches path_provider
    // for the cookie-jar directory — stub it so construction doesn't throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  late _FakeApiProvider fakeApi;
  late _FakeItemProvider fakeProvider;

  setUp(() {
    fakeApi = _FakeApiProvider();
    Get.put<ApiProvider>(fakeApi);
    fakeProvider = _FakeItemProvider();
    Get.put<ItemProvider>(fakeProvider);
  });

  tearDown(() => Get.deleteAll(force: true));

  Future<ItemFormController> loadedController({
    List<Map<String, dynamic>>? reorderLevels,
    int isStockItem = 1,
    String defaultType = 'Purchase',
  }) async {
    fakeApi.getDocumentData = _cannedItem(
      reorderLevels: reorderLevels,
      isStockItem: isStockItem,
      defaultType: defaultType,
    );
    final ctrl = ItemFormController();
    ctrl.itemCode = 'ITEM-1';
    await ctrl.fetchItemDetails();
    return ctrl;
  }

  group('reorder row seeding', () {
    test('seeds reorderRows from the fetched item', () async {
      final ctrl = await loadedController(reorderLevels: [
        {
          'name': 'r1',
          'warehouse': 'WH-A',
          'material_request_type': 'Purchase',
          'warehouse_reorder_level': 100,
          'warehouse_reorder_qty': 50,
        }
      ]);

      expect(ctrl.reorderRows.length, 1);
      expect(ctrl.reorderRows.first.warehouse, 'WH-A');
      expect(ctrl.isReorderDirty.value, isFalse);
    });

    test('seeds an empty list when the item has no rows', () async {
      final ctrl = await loadedController();
      expect(ctrl.reorderRows, isEmpty);
      expect(ctrl.isReorderDirty.value, isFalse);
    });
  });

  group('dirty tracking', () {
    test('adding a row marks dirty', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(
        const ItemReorder(warehouse: 'WH-A', materialRequestType: 'Purchase'),
      );
      expect(ctrl.isReorderDirty.value, isTrue);
    });

    test('is a diff, not a latch — reverting clears dirty', () async {
      final ctrl = await loadedController(reorderLevels: [
        {'name': 'r1', 'warehouse': 'WH-A', 'material_request_type': 'Purchase'}
      ]);

      ctrl.addReorderRow(
        const ItemReorder(warehouse: 'WH-B', materialRequestType: 'Transfer'),
      );
      expect(ctrl.isReorderDirty.value, isTrue);

      ctrl.removeReorderRow(1);
      expect(ctrl.isReorderDirty.value, isFalse);
    });

    test('editing a row marks dirty', () async {
      final ctrl = await loadedController(reorderLevels: [
        {'name': 'r1', 'warehouse': 'WH-A', 'material_request_type': 'Purchase'}
      ]);

      ctrl.updateReorderRow(
        0,
        ctrl.reorderRows.first.copyWith(warehouseReorderLevel: 500),
      );
      expect(ctrl.isReorderDirty.value, isTrue);
    });
  });

  group('newReorderRowTemplate', () {
    test('defaults the type from the item default', () async {
      final ctrl = await loadedController(defaultType: 'Material Transfer');
      expect(ctrl.newReorderRowTemplate().materialRequestType, 'Transfer');
    });

    test('leaves the type blank for Customer Provided', () async {
      final ctrl = await loadedController(defaultType: 'Customer Provided');
      expect(ctrl.newReorderRowTemplate().materialRequestType, '');
    });
  });

  group('fetchAutoIndentSetting', () {
    test('auto_indent 0 disables', () async {
      final ctrl = await loadedController();
      fakeProvider.autoIndentValue = 0;
      await ctrl.fetchAutoIndentSetting();
      expect(ctrl.autoIndentEnabled.value, isFalse);
    });

    test('auto_indent 1 enables', () async {
      final ctrl = await loadedController();
      fakeProvider.autoIndentValue = 1;
      await ctrl.fetchAutoIndentSetting();
      expect(ctrl.autoIndentEnabled.value, isTrue);
    });

    test('fails OPEN on a 403 — no false alarm for non-System-Managers',
        () async {
      final ctrl = await loadedController();
      fakeProvider.throwOnStockSettings = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 403,
        ),
      );

      await ctrl.fetchAutoIndentSetting();

      expect(ctrl.autoIndentEnabled.value, isTrue,
          reason: 'a permission error must not render the warning banner');
    });
  });

  group('saveReorderLevels', () {
    test('sends the rows plus the optimistic-lock modified token', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
        warehouseReorderLevel: 100,
        warehouseReorderQty: 50,
      ));

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdateItemCode, 'ITEM-1');
      expect(fakeProvider.lastUpdatePayload?['modified'],
          '2026-07-17 09:00:00');
      final sent =
          fakeProvider.lastUpdatePayload?['reorder_levels'] as List;
      expect(sent.length, 1);
      expect(sent.first['warehouse'], 'WH-A');
      // Blank group defaults to the warehouse (item.py:508-509).
      expect(sent.first['warehouse_group'], 'WH-A');
      expect(ctrl.isSavingReorder.value, isFalse);
    });

    test('a 200 save reseeds rows from the server and clears the dirty flag',
        () async {
      // Server persists the saved row and, per item.py:508-509, returns it
      // with warehouse_group defaulted to the warehouse.
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
        warehouseReorderLevel: 100,
        warehouseReorderQty: 50,
      ));
      expect(ctrl.isReorderDirty.value, isTrue);

      // Make the post-save re-fetch (fetchItemDetails, called again inside
      // saveReorderLevels on a 200) return the row as the server would
      // persist it — warehouse_group defaulted to the warehouse.
      fakeApi.getDocumentData = _cannedItem(reorderLevels: [
        {
          'name': 'srv1',
          'warehouse_group': 'WH-A',
          'warehouse': 'WH-A',
          'material_request_type': 'Purchase',
          'warehouse_reorder_level': 100,
          'warehouse_reorder_qty': 50,
        }
      ]);

      await ctrl.saveReorderLevels();

      expect(ctrl.isReorderDirty.value, isFalse,
          reason:
              'a successful save must reseed the dirty baseline from the server');
      expect(ctrl.reorderRows.length, 1);
      expect(ctrl.reorderRows.first.name, 'srv1',
          reason: 'rows are reseeded from the server response, not the local edit');
      expect(ctrl.reorderRows.first.warehouseGroup, 'WH-A');
    });

    test('blocks a duplicate (warehouse, type) and never calls the provider',
        () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdatePayload, isNull);
    });

    test('blocks a level with no qty', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
        warehouse: 'WH-A',
        materialRequestType: 'Purchase',
        warehouseReorderLevel: 100,
      ));

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdatePayload, isNull);
    });

    test('re-entrancy guard skips a save already in flight', () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));
      ctrl.isSavingReorder.value = true;

      await ctrl.saveReorderLevels();

      expect(fakeProvider.lastUpdatePayload, isNull);
    });

    test('surfaces the server message and clears the busy flag on failure',
        () async {
      final ctrl = await loadedController();
      ctrl.addReorderRow(const ItemReorder(
          warehouse: 'WH-A', materialRequestType: 'Purchase'));

      fakeProvider.throwOnUpdate = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 417,
          data: {
            '_server_messages':
                '["{\\"message\\": \\"Row #1: The warehouse <b>WH-A</b> is not a child warehouse of a group warehouse <b>G</b>\\"}"]'
          },
        ),
      );

      await ctrl.saveReorderLevels();

      expect(ctrl.isSavingReorder.value, isFalse);
    });

    test('extracts a Frappe _server_messages payload, stripped of HTML', () {
      final msg = ItemFormController.parseServerMessage({
        '_server_messages':
            '["{\\"message\\": \\"Row #1: The warehouse <b>WH-A</b> is not a child warehouse of a group warehouse <b>G</b>\\"}"]'
      });

      expect(
        msg,
        'Row #1: The warehouse WH-A is not a child warehouse of a group warehouse G',
      );
    });

    test('falls back to exception when _server_messages is absent', () {
      final msg = ItemFormController.parseServerMessage(
          {'exception': 'frappe.exceptions.ValidationError: Something broke'});
      expect(msg, 'Something broke');
    });

    test('falls back to a generic message for an unparseable body', () {
      expect(ItemFormController.parseServerMessage(null), 'Save failed');
      expect(ItemFormController.parseServerMessage({}), 'Save failed');
    });
  });
}
