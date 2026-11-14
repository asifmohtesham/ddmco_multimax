import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_screen.dart';

class _FakeProvider extends PricingRuleProvider {
  _FakeProvider(this.rows);
  final List<Map<String, dynamic>> rows;

  @override
  Future<Response> getRules({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async =>
      Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: {'data': rows});

  @override
  Future<int> count(List<List<dynamic>> filters) async => 0;

  @override
  Future<void> attachTargets(List<PricingRule> rules) async {
    for (final r in rules) {
      r.targets = [PricingRuleTarget(value: 'Belts')];
    }
  }
}

class _Perms extends PermissionService {
  _Perms(bool? v) : _g = Rx<bool?>(v);
  final Rx<bool?> _g;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

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
    Get.put<PermissionService>(_Perms(grant));
    Get.put<PricingRuleProvider>(_FakeProvider(rows));
    Get.put(PricingRuleController());
    await tester.pumpWidget(const GetMaterialApp(home: PricingRuleScreen()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('zero rules: explanatory empty state with create CTA',
      (tester) async {
    await pump(tester, rows: const []);
    expect(tester.takeException(), isNull);
    expect(find.text('No pricing rules yet'), findsOneWidget);
    expect(find.text('New pricing rule'), findsOneWidget);
  });

  testWidgets('empty state hides the CTA without create permission',
      (tester) async {
    await pump(tester, rows: const [], grant: false);
    expect(find.text('No pricing rules yet'), findsOneWidget);
    expect(find.text('New pricing rule'), findsNothing);
  });

  testWidgets('rows show title, summary sentence, status and priority badge',
      (tester) async {
    await pump(tester, rows: [
      {
        'name': 'PRLE-0001',
        'title': 'Belts clearance',
        'disable': 0,
        'apply_on': 'Item Group',
        'price_or_product_discount': 'Price',
        'selling': 1,
        'rate_or_discount': 'Discount Amount',
        'discount_amount': 5,
        'currency': 'AED',
        'valid_upto': '2026-08-31',
        'has_priority': 1,
        'priority': '3',
      },
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Belts clearance'), findsOneWidget);
    expect(find.text('AED 5.00 off for everyone on item group Belts, until 31 Aug 2026'),
        findsOneWidget);
    expect(find.text('Expired'), findsWidgets);
    expect(find.text('P3'), findsOneWidget);
  });
}
