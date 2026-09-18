import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_controller.dart';
import 'package:multimax/app/modules/pricing/item_price/form/item_price_form_screen.dart';

/// Regression: saving a duplicate Item Price must surface the server's message
/// on screen. On-device the save failed silently (ERPNext answers 417
/// ItemPriceDuplicateItem) — this pins the banner to the real error payload.
Response _ok(dynamic data) => Response(
    requestOptions: RequestOptions(path: '/'), statusCode: 200, data: data);

class _DupProvider extends ItemPriceProvider {
  @override
  Future<Response> getPriceLists() async => _ok({
        'data': [
          {'name': 'Standard Buying', 'currency': 'AED', 'selling': 0, 'buying': 1},
        ]
      });

  @override
  Future<Response> getItem(String itemCode) async => _ok({
        'data': {
          'name': itemCode,
          'item_name': 'WALLETS COW',
          'stock_uom': 'Nos',
          'has_variants': 0,
          'uoms': [
            {'uom': 'Nos'}
          ],
        }
      });

  @override
  Future<Response> createItemPrice(Map<String, dynamic> data) async {
    // Verbatim shape ERPNext v15 returns for a duplicate (HTTP 417).
    throw DioException(
      requestOptions: RequestOptions(path: '/api/resource/Item Price'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/resource/Item Price'),
        statusCode: 417,
        data: {
          'exception':
              'erpnext.stock.doctype.item_price.item_price.ItemPriceDuplicateItem: Item Price appears multiple times based on Price List, Supplier/Customer, Currency, Item, Batch, UOM, Qty, and Dates.',
          'exc_type': 'ItemPriceDuplicateItem',
        },
      ),
    );
  }
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  tearDown(Get.reset);

  testWidgets('duplicate save shows the server message on screen',
      (tester) async {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms());
    Get.put<ItemPriceProvider>(_DupProvider());
    final c = Get.put(ItemPriceFormController()..mode.value = 'new');
    await tester.pumpWidget(const GetMaterialApp(home: ItemPriceFormScreen()));
    await tester.pumpAndSettle();

    await c.applyItem('1000001');
    c.rateController.text = '9';
    await tester.pumpAndSettle();

    await c.saveDocument();
    await tester.pumpAndSettle();

    expect(c.serverError.value, isNotEmpty,
        reason: 'the controller must capture the server message');
    // Specifically the in-form banner: a plain textContaining also matches the
    // snackbar, which is how the missing banner passed unnoticed.
    expect(
      find.descendant(
        of: find.byType(InlineBanner),
        matching: find.textContaining('Item Price appears multiple times',
            findRichText: true),
      ),
      findsOneWidget,
      reason: 'the failure must stay on the form, not only in a snackbar',
    );
    // A pumped tree always runs the entrance animation to completion, so the
    // zero-height banner seen on device cannot be reproduced here — pin the
    // setting that avoids it instead.
    expect(tester.widget<InlineBanner>(find.byType(InlineBanner)).animate,
        isFalse,
        reason: 'the animated banner collapses to zero height on device');
  });
}
