import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_screen.dart';

class _FakeItemPriceProvider extends ItemPriceProvider {
  _FakeItemPriceProvider(this.rows);
  final List<Map<String, dynamic>> rows;

  Response _ok(dynamic data) =>
      Response(requestOptions: RequestOptions(path: '/'), statusCode: 200, data: data);

  @override
  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) async =>
      _ok({'data': rows});

  @override
  Future<Response> getPriceLists() async => _ok({
        'data': [
          {'name': 'Standard Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
        ]
      });

  @override
  Future<int> count(List<List<dynamic>> filters) async => rows.length;
}

class _StubPermissionService extends PermissionService {
  _StubPermissionService(bool? value) : grant = Rx<bool?>(value);
  final Rx<bool?> grant;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => grant.value;
}

Map<String, dynamic> _row(String code, String name, num rate,
        {String? upto, String? customer}) =>
    {
      'name': 'hash-$code',
      'item_code': code,
      'item_name': name,
      'uom': 'Nos',
      'price_list': 'Standard Selling',
      'price_list_rate': rate,
      'currency': 'AED',
      'selling': 1,
      'buying': 0,
      'valid_from': '2026-01-01',
      'valid_upto': upto,
      'customer': customer,
    };

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester,
      {required List<Map<String, dynamic>> rows, bool? grant = true}) async {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(AuthenticationController());
    Get.put<PermissionService>(_StubPermissionService(grant));
    Get.put<ItemPriceProvider>(_FakeItemPriceProvider(rows));
    Get.put(ItemPriceController());
    await tester.pumpWidget(const GetMaterialApp(home: ItemPriceScreen()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders rows with rate, scope tag, expired pill and zero hint',
      (tester) async {
    await pump(tester, rows: [
      _row('1000001', 'WALLETS COW', 25, customer: 'Al Noor Trading'),
      _row('2001528', 'BELTS CASUAL 35MM', 0, upto: '2026-02-01'),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('WALLETS COW'), findsOneWidget);
    expect(find.text('25.00'), findsOneWidget);
    expect(find.text('Customer: Al Noor Trading'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('zero · / Nos'), findsOneWidget);
    expect(find.text('New price'), findsOneWidget);
  });

  testWidgets('empty list shows the empty state; FAB hidden without create',
      (tester) async {
    await pump(tester, rows: const [], grant: false);
    expect(tester.takeException(), isNull);
    expect(find.text('No item prices'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
