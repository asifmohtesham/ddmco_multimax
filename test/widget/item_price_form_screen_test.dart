import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_screen.dart';

Response _res(dynamic data) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: 200, data: data);

class _FakeProvider extends ItemPriceProvider {
  _FakeProvider(this.listName, {this.selling = true});
  final String listName;
  final bool selling;

  @override
  Future<Response> getPriceLists() async => _res({
        'data': [
          {'name': 'Standard Selling', 'currency': 'AED', 'selling': 1, 'buying': 0},
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
        ]
      });

  @override
  Future<Response> getItemPrice(String name) async => _res({
        'data': {
          'name': name,
          'item_code': '1000001',
          'item_name': 'WALLETS COW',
          'uom': 'Nos',
          'price_list': listName,
          'selling': selling ? 1 : 0,
          'buying': selling ? 0 : 1,
          'currency': 'AED',
          'price_list_rate': 25,
          'valid_from': '2026-04-22',
          'modified': 'x',
        }
      });

  @override
  Future<Response> getItem(String itemCode) async => _res({
        'data': {'name': itemCode, 'stock_uom': 'Nos', 'uoms': []}
      });
}

class _Perms extends PermissionService {
  _Perms(bool v) : _g = v.obs;
  final RxBool _g;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  Future<ItemPriceFormController> pump(
    WidgetTester tester, {
    String listName = 'Standard Selling',
    bool selling = true,
    bool canWrite = true,
    Brightness brightness = Brightness.light,
  }) async {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms(canWrite));
    Get.put<ItemPriceProvider>(_FakeProvider(listName, selling: selling));
    final c = Get.put(ItemPriceFormController()
      ..name = 'hash1'
      ..mode.value = 'edit');
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const ItemPriceFormScreen(),
    ));
    await tester.pump();
    await tester.pump();
    return c;
  }

  testWidgets('edit mode: title, rate, Save + Delete, More options toggles',
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('WALLETS COW'), findsWidgets);
    expect(find.text('25.00'), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.text('Customer'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Expand'));
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Supplier'), findsNothing);
  });

  testWidgets('buying list shows Supplier, not Customer', (tester) async {
    await pump(tester, listName: 'Standard Buying', selling: false);
    await tester.ensureVisible(find.byTooltip('Expand'));
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('Customer'), findsNothing);
  });

  testWidgets('read-only user: no Save/Delete, read-only note', (tester) async {
    await pump(tester, canWrite: false);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('Read-only · you can view prices but not change them'),
        findsOneWidget);
  });

  testWidgets('server error banner shows the message', (tester) async {
    final c = await pump(tester);
    c.serverError.value = 'Item Price appears multiple times';
    await tester.pumpAndSettle();
    expect(find.textContaining('Item Price appears multiple times'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
    expect(find.text('25.00'), findsOneWidget);
  });
}
