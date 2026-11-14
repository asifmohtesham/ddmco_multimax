import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_screen.dart';

class _FakeProvider extends PricingRuleProvider {
  _FakeProvider(this.doc);
  final Map<String, dynamic> doc;
  @override
  Future<Response> getRule(String name) async => Response(
      requestOptions: RequestOptions(path: '/'), statusCode: 200, data: {'data': doc});

  /// Loading an Item Code rule looks item names up; without this the real
  /// implementation reaches Dio and leaves a pending timer.
  @override
  Future<void> attachItemLabels(List<PricingRuleTarget> targets) async {}
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

Map<String, dynamic> _doc({String? scheme, String pod = 'Price', String rod = 'Discount Percentage'}) => {
      'name': 'PRLE-0007',
      'title': 'Retail winter 10%',
      'apply_on': 'Item Code',
      'price_or_product_discount': pod,
      'selling': 1,
      'applicable_for': 'Customer Group',
      'customer_group': 'Retail',
      'rate_or_discount': rod,
      'discount_percentage': 10,
      'rate': 22,
      'for_price_list': 'Standard Selling',
      'currency': 'AED',
      'free_item': '2001490',
      'free_qty': 1,
      'promotional_scheme': scheme,
      'modified': 'm',
      'items': [
        {'name': 'r1', 'item_code': '1000001', 'uom': null}
      ],
    };

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

  Future<PricingRuleFormController> pump(WidgetTester tester, Map<String, dynamic> doc,
      {Brightness brightness = Brightness.light}) async {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<PermissionService>(_Perms());
    Get.put<PricingRuleProvider>(_FakeProvider(doc));
    final c = Get.put(PricingRuleFormController()
      ..name = 'PRLE-0007'
      ..mode.value = 'edit');
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const PricingRuleFormScreen(),
    ));
    await tester.pump();
    await tester.pump();
    return c;
  }

  const summary =
      '10% off Standard Selling for customer group Retail on item 1000001';

  testWidgets('Rule tab shows summary, party and target', (tester) async {
    await pump(tester, _doc());
    expect(tester.takeException(), isNull);
    // NestedScrollView body content sits in the sliver-overlap region above
    // the header's own visible extent, so Flutter's finders (skipOffstage:
    // true by default) miss it even though it renders; skipOffstage: false
    // walks the full element tree instead.
    expect(find.text(summary, skipOffstage: false), findsOneWidget);
    expect(find.text('Retail', skipOffstage: false), findsOneWidget);
    expect(find.text('1000001', skipOffstage: false), findsOneWidget);
    expect(find.text('Add item', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Discount tab: price list field only for discounts', (tester) async {
    final c = await pump(tester, _doc());
    await tester.tap(find.text('Discount'));
    await tester.pumpAndSettle();
    expect(find.text('Only for price list'), findsOneWidget);
    c.setRateOrDiscount('Rate');
    await tester.pumpAndSettle();
    expect(find.text('Only for price list'), findsNothing);
  });

  testWidgets('summary updates when the title-independent value changes',
      (tester) async {
    final c = await pump(tester, _doc());
    c.valueController.text = '15';
    await tester.pump();
    expect(find.textContaining('15% off'), findsOneWidget);
  });

  testWidgets('promotional scheme: locked banner, no Save', (tester) async {
    await pump(tester, _doc(scheme: 'Eid 2026'));
    expect(
        find.textContaining('Promotional Scheme “Eid 2026”', skipOffstage: false),
        findsOneWidget);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.text('Add item', skipOffstage: false), findsNothing);
  });

  testWidgets('product rule: read-only notice on Discount tab', (tester) async {
    await pump(tester, _doc(pod: 'Product'));
    await tester.tap(find.text('Discount'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Product rules are read-only in the app'),
        findsOneWidget);
  });

  testWidgets('Conditions tab warns when priority is not set (dark)',
      (tester) async {
    await pump(tester, _doc(), brightness: Brightness.dark);
    await tester.tap(find.text('Conditions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No priority set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
