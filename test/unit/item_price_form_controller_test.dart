import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';

Response _res(int code, [dynamic data]) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: code, data: data);

class _FakeProvider extends ItemPriceProvider {
  Map<String, dynamic>? lastCreate;
  Map<String, dynamic>? lastUpdate;
  Object? throwOnCreate;
  int deleteStatus = 202;

  @override
  Future<Response> getPriceLists() async => _res(200, {
        'data': [
          {'name': 'Credit Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
          {'name': 'Standard Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
        ]
      });

  @override
  Future<Response> getItemPrice(String name) async => _res(200, {
        'data': {
          'name': name,
          'item_code': '1000001',
          'item_name': 'WALLETS COW',
          'uom': 'Nos',
          'price_list': 'Standard Selling',
          'selling': 1,
          'currency': 'AED',
          'price_list_rate': 25,
          'valid_from': '2026-04-22',
          'customer': 'Al Noor Trading',
          'modified': '2026-04-22 17:36:55',
        }
      });

  @override
  Future<Response> getItem(String itemCode) async => _res(200, {
        'data': {
          'name': itemCode,
          'item_name': 'WALLETS COW',
          'stock_uom': 'Nos',
          'has_variants': 0,
          'uoms': [
            {'uom': 'Nos'},
            {'uom': 'Box'},
          ],
        }
      });

  @override
  Future<Response> createItemPrice(Map<String, dynamic> data) async {
    lastCreate = data;
    if (throwOnCreate != null) throw throwOnCreate!;
    return _res(200, {'data': {...data, 'name': 'newhash'}});
  }

  @override
  Future<Response> updateItemPrice(String name, Map<String, dynamic> data) async {
    lastUpdate = data;
    return _res(200, {'data': data});
  }

  @override
  Future<Response> deleteItemPrice(String name) async => _res(deleteStatus);
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

void main() {
  late _FakeProvider provider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms());
    provider = _FakeProvider();
    Get.put<ItemPriceProvider>(provider);
  });

  tearDown(Get.reset);

  Future<ItemPriceFormController> newForm() async {
    final c = ItemPriceFormController()..mode.value = 'new';
    Get.put(c);
    await pumpEventQueue();
    return c;
  }

  Future<ItemPriceFormController> editForm() async {
    final c = ItemPriceFormController()
      ..name = 'hash1'
      ..mode.value = 'edit';
    Get.put(c);
    await pumpEventQueue();
    return c;
  }

  test('new: defaults to Standard Selling, today, dirty', () async {
    final c = await newForm();
    expect(c.price.value.priceList, 'Standard Selling');
    expect(c.price.value.validFrom, frappeDate(DateTime.now()));
    expect(c.isDirty.value, isTrue);
    expect(c.isLoading.value, isFalse);
  });

  test('new: save is blocked by client validation', () async {
    final c = await newForm();
    await c.saveDocument();
    expect(provider.lastCreate, isNull);
    expect(c.fieldErrors['item_code'], 'Item is required');
  });

  test('applyItem loads units and defaults to the stock uom', () async {
    final c = await newForm();
    await c.applyItem('1000001');
    expect(c.itemUoms, ['Nos', 'Box']);
    expect(c.price.value.uom, 'Nos');
    expect(c.price.value.itemName, 'WALLETS COW');
  });

  test('new: save sends only sendable keys and flips to edit', () async {
    final c = await newForm();
    await c.applyItem('1000001');
    c.rateController.text = '30';
    await c.saveDocument();
    expect(provider.lastCreate!.keys.toSet(), {
      'item_code', 'uom', 'packing_unit', 'price_list', 'customer',
      'supplier', 'batch_no', 'price_list_rate', 'valid_from', 'valid_upto',
      'lead_time_days', 'note',
    });
    expect(provider.lastCreate!['price_list_rate'], 30.0);
    expect(c.mode.value, 'edit');
    expect(c.name, 'newhash');
  });

  test('server error lands in serverError (verbatim, tags stripped)', () async {
    final c = await newForm();
    await c.applyItem('1000001');
    provider.throwOnCreate = DioException(
      requestOptions: RequestOptions(path: '/'),
      response: _res(417, {
        '_server_messages': jsonEncode([
          jsonEncode({
            'message':
                'Item Price appears multiple times based on <b>Price List</b>, Supplier/Customer, Currency, Item, Batch, UOM, Qty, and Dates.'
          })
        ])
      }),
    );
    await c.saveDocument();
    expect(c.serverError.value,
        'Item Price appears multiple times based on Price List, Supplier/Customer, Currency, Item, Batch, UOM, Qty, and Dates.');
  });

  test('edit: loads, not dirty, update sends modified', () async {
    final c = await editForm();
    expect(c.price.value.customer, 'Al Noor Trading');
    expect(c.rateController.text, '25.00');
    expect(c.isDirty.value, isFalse);
    c.rateController.text = '27.50';
    expect(c.isDirty.value, isTrue);
    await c.saveDocument();
    expect(provider.lastUpdate!['modified'], '2026-04-22 17:36:55');
    expect(provider.lastUpdate!['price_list_rate'], 27.5);
  });

  test('switching to a buying list clears the customer', () async {
    final c = await editForm();
    c.setPriceList('Standard Buying');
    expect(c.price.value.customer, isNull);
    expect(c.price.value.buying, isTrue);
    expect(c.isSellingList, isFalse);
  });

  test('performDelete accepts 202', () async {
    final c = await editForm();
    expect(await c.performDelete(), isTrue);
  });
}
