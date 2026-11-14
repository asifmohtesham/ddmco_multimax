import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/pricing/pricing_logic.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/form/pricing_rule_form_controller.dart';

Response _res(int code, [dynamic data]) =>
    Response(requestOptions: RequestOptions(path: '/'), statusCode: code, data: data);

class _FakeProvider extends PricingRuleProvider {
  Map<String, dynamic> doc = {};
  Map<String, dynamic>? lastCreate;
  Map<String, dynamic>? lastUpdate;

  @override
  Future<({String name, String currency})?> getDefaultCompany() async =>
      (name: 'Multimax', currency: 'AED');

  @override
  Future<Response> getRule(String name) async => _res(200, {'data': doc});

  @override
  Future<Response> createRule(Map<String, dynamic> data) async {
    lastCreate = data;
    doc = {...data, 'name': 'PRLE-0001', 'modified': 'm1'};
    return _res(200, {'data': doc});
  }

  @override
  Future<Response> updateRule(String name, Map<String, dynamic> data) async {
    lastUpdate = data;
    return _res(200, {'data': doc});
  }

  @override
  Future<Response> deleteRule(String name) async => _res(202);

  List<String>? labelledCodes;

  @override
  Future<void> attachItemLabels(List<PricingRuleTarget> targets) async {
    labelledCodes = [for (final t in targets) t.value];
    for (final t in targets) {
      t.label = 'WALLETS COW';
      t.variantOf = 'TPL-1';
    }
  }
}

class _Perms extends PermissionService {
  final _g = true.obs;
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => _g.value;
}

Map<String, dynamic> _existing({String? scheme, String pod = 'Price'}) => {
      'name': 'PRLE-0007',
      'title': 'Retail winter 10%',
      'apply_on': 'Item Code',
      'price_or_product_discount': pod,
      'selling': 1,
      'buying': 0,
      'applicable_for': 'Customer Group',
      'customer_group': 'Retail',
      'rate_or_discount': 'Discount Percentage',
      'discount_percentage': 10,
      'for_price_list': 'Standard Selling',
      'currency': 'AED',
      'promotional_scheme': scheme,
      'modified': '2026-09-17 10:00:00',
      'items': [
        {'name': 'r1', 'item_code': '1000001', 'uom': null}
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeProvider provider;

  setUpAll(() {
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
    Get.put<PricingRuleProvider>(provider);
  });

  tearDown(Get.reset);

  Future<PricingRuleFormController> open({Map<String, dynamic>? doc}) async {
    final c = PricingRuleFormController();
    if (doc == null) {
      c.mode.value = 'new';
    } else {
      provider.doc = doc;
      c
        ..name = doc['name'] as String
        ..mode.value = 'edit';
    }
    Get.put(c);
    await pumpEventQueue();
    return c;
  }

  test('new: v15 defaults + company currency', () async {
    final c = await open();
    final r = c.rule.value;
    expect(r.applyOn, 'Item Code');
    expect(r.priceOrProductDiscount, 'Price');
    expect(r.rateOrDiscount, 'Discount Percentage');
    expect(r.selling, isTrue);
    expect(r.validFrom, frappeDate(DateTime.now()));
    expect(r.company, 'Multimax');
    expect(r.currency, 'AED');
    expect(c.isDirty.value, isTrue);
  });

  test('switching side to Buying clears a selling party', () async {
    final c = await open(doc: _existing());
    c.setSide('Buying');
    expect(c.rule.value.buying, isTrue);
    expect(c.rule.value.selling, isFalse);
    expect(c.rule.value.applicableFor, '');
    expect(c.rule.value.party, isNull);
    expect(c.forOptions, ['Everyone', 'Supplier', 'Supplier Group']);
  });

  test('Rate clears for_price_list and reseeds the value field', () async {
    final c = await open(doc: _existing());
    expect(c.valueController.text, '10');
    c.setRateOrDiscount('Rate');
    expect(c.rule.value.forPriceList, isNull);
    expect(c.valueController.text, '');
    c.valueController.text = '22';
    expect(c.rule.value.rate, 22);
  });

  test('setApplyOn resets targets', () async {
    final c = await open(doc: _existing());
    c.setApplyOn('Item Group');
    expect(c.rule.value.targets, isEmpty);
  });

  test('save blocked by validation and tab gets the error dot', () async {
    final c = await open();
    await c.saveDocument();
    expect(provider.lastCreate, isNull);
    expect(c.fieldErrors['title'], 'Title is required');
    expect(c.tabHasError(0), isTrue);
    expect(c.tabHasError(1), isFalse);
  });

  test('new save posts naming series, items table, string priority', () async {
    final c = await open();
    c.titleController.text = 'Retail 10%';
    c.valueController.text = '10';
    c.rule.update((r) => r!.targets = [PricingRuleTarget(value: '1000001')]);
    c.rule.update((r) {
      r!.hasPriority = true;
      r.priority = '5';
    });
    await c.saveDocument();
    expect(provider.lastCreate!['naming_series'], 'PRLE-.####');
    expect(provider.lastCreate!['items'], [
      {'item_code': '1000001', 'uom': null}
    ]);
    expect(provider.lastCreate!['priority'], '5');
    expect(provider.lastCreate!['discount_percentage'], 10.0);
    expect(c.mode.value, 'edit');
    expect(c.name, 'PRLE-0001');
  });

  test('edit: clean after load; update sends modified', () async {
    final c = await open(doc: _existing());
    expect(c.isDirty.value, isFalse);
    c.titleController.text = 'Retail winter 12%';
    expect(c.isDirty.value, isTrue);
    await c.saveDocument();
    expect(provider.lastUpdate!['modified'], '2026-09-17 10:00:00');
    expect(provider.lastUpdate!.containsKey('naming_series'), isFalse);
  });

  test('promotional scheme and product rules are read-only', () async {
    final promo = await open(doc: _existing(scheme: 'Eid 2026'));
    expect(promo.isEditable, isFalse);
    promo.setSide('Buying');
    expect(promo.rule.value.selling, isTrue, reason: 'edits ignored');
    Get.delete<PricingRuleFormController>();
    final product = await open(doc: _existing(pod: 'Product'));
    expect(product.isEditable, isFalse);
  });

  test('toggleTargetUom clears an existing unit', () async {
    final c = await open(doc: _existing());
    c.rule.update((r) => r!.targets.first.uom = 'Nos');
    await c.toggleTargetUom(0);
    expect(c.rule.value.targets.first.uom, isNull);
  });

  test('performDelete accepts 202', () async {
    final c = await open(doc: _existing());
    expect(await c.performDelete(), isTrue);
  });

  test('loading an Item Code rule attaches item names without dirtying it',
      () async {
    final c = await open(doc: _existing());
    // The child rows carry only the code, so on device a reloaded rule showed
    // bare codes and the variant-vs-template check never fired.
    expect(provider.labelledCodes, ['1000001']);
    expect(c.rule.value.targets.first.label, 'WALLETS COW');
    expect(c.rule.value.targets.first.variantOf, 'TPL-1');
    expect(c.isDirty.value, isFalse,
        reason: 'label/variantOf are client-only and are not sent back');
  });

  test('a Brand rule does not look up item names', () async {
    await open(doc: {..._existing(), 'apply_on': 'Brand', 'items': []});
    expect(provider.labelledCodes, isNull);
  });
}
