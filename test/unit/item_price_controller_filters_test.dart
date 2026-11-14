import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_price_provider.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';

/// On-device smoke found the Credit Selling chip (0 prices) showing the
/// unfiltered "No item prices" empty state with a Reload button, instead of
/// the "No matching prices" / Clear variant: the chip was not counted as an
/// active filter.
class _QuietProvider extends ItemPriceProvider {
  @override
  Future<Response> getItemPrices({
    int limit = 20,
    int limitStart = 0,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    String orderBy = 'modified desc',
  }) async =>
      Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: {'data': const []});

  @override
  Future<Response> getPriceLists() async => Response(
      requestOptions: RequestOptions(path: '/'),
      statusCode: 200,
      data: {'data': const []});

  @override
  Future<int> count(List<List<dynamic>> filters) async => 0;
}

class _QuietController extends ItemPriceController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  // ignore: must_call_super
  void onReady() {}
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

  setUp(() {
    Get.testMode = true;
    Get.put<ApiProvider>(ApiProvider());
    Get.put<ItemPriceProvider>(_QuietProvider());
  });

  tearDown(Get.reset);

  test('a selected price-list chip counts as an active filter', () {
    final c = Get.put<ItemPriceController>(_QuietController());
    expect(c.hasActiveFilters, isFalse);

    c.selectPriceList('Credit Selling');
    expect(c.hasActiveFilters, isTrue,
        reason: 'an empty result under a chip is a filtered empty state');

    // The count pill still shows the chip's own server total — the chip does
    // not narrow beyond what the per-list counts already know.
    c.listCounts.assignAll({'': 1661, 'Credit Selling': 0});
    expect(c.displayCount, 0);
    expect(c.countHasMore, isFalse);
  });

  test('clearing filters puts the list back on All', () {
    final c = Get.put<ItemPriceController>(_QuietController());
    c.selectPriceList('Standard Buying');
    c.applyFilters({'validity': 'Expired'});

    c.clearFilters();

    expect(c.selectedPriceList.value, '');
    expect(c.activeFilters, isEmpty);
    expect(c.hasActiveFilters, isFalse);
  });
}
