import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pricing_rule_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';

class _FakeApiProvider extends ApiProvider {}

class _FakeItemProvider extends ItemProvider {}

/// Grants every [hasAccess] check so `fetchPricing` proceeds past the
/// permission gate without hitting the network.
class _GrantAllPermissionService extends PermissionService {
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => true;
}

class _FakeItemPriceProvider extends ItemPriceProvider {
  /// When set, [getItemPrices] throws this instead of returning.
  Object? throwOnGetItemPrices;

  @override
  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) async {
    if (throwOnGetItemPrices != null) throw throwOnGetItemPrices!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/Item Price'),
      statusCode: 200,
      data: {'data': <Map<String, dynamic>>[]},
    );
  }
}

class _FakePricingRuleProvider extends PricingRuleProvider {
  @override
  Future<List<PricingRule>> rulesForItem(
          String itemCode, String? variantOf) async =>
      <PricingRule>[];
}

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

  late _FakeItemPriceProvider fakeItemPriceProvider;

  setUp(() {
    Get.put<ApiProvider>(_FakeApiProvider());
    Get.put<ItemProvider>(_FakeItemProvider());
    Get.put<PermissionService>(_GrantAllPermissionService());
    fakeItemPriceProvider = _FakeItemPriceProvider();
    Get.put<ItemPriceProvider>(fakeItemPriceProvider);
    Get.put<PricingRuleProvider>(_FakePricingRuleProvider());
  });

  tearDown(() => Get.deleteAll(force: true));

  group('fetchPricing', () {
    test(
        'a non-DioException from getItemPrices is caught, not rethrown — '
        'fetchPricing completes and clears the loading flag', () async {
      final ctrl = ItemFormController();
      ctrl.itemCode = 'ITEM-1';
      // A payload shape the model can't parse (e.g. a cast failure) throws a
      // plain error, not a DioException.
      fakeItemPriceProvider.throwOnGetItemPrices =
          const FormatException('unexpected payload shape');

      // Before the fix this awaited call rethrows the FormatException out of
      // fetchPricing (it escapes the `on DioException` clause and Future.wait
      // propagates it), failing this test.
      await ctrl.fetchPricing();

      expect(ctrl.isLoadingPricing.value, isFalse);
      // The sibling load (rules) is unaffected by the prices failure.
      expect(ctrl.itemRules, isEmpty);
      expect(ctrl.rulesVisible.value, isTrue);
    });
  });
}
