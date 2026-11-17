import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

typedef _Report = ({
  List<Map<String, dynamic>> columns,
  List<Map<String, dynamic>> rows,
});

class _FakeApi extends ApiProvider {
  final List<Map<String, dynamic>> itemCalls = [];
  final List<Map<String, dynamic>> reportCalls = [];
  Object? itemError;
  Object? reportError;
  List<Map<String, dynamic>> itemRows = [];

  /// Overrides the whole Item response body when set.
  Object? itemBody;
  List<Map<String, dynamic>> reportRows = [];

  @override
  Future<Response> getDocumentList(
    String doctype, {
    int limit = 20,
    int limitStart = 0,
    List<String>? fields,
    String? groupBy = '',
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    Map<String, dynamic>? orFilters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    itemCalls.add({
      'doctype': doctype,
      'fields': fields,
      'filterTuples': filterTuples,
      'limit': limit,
    });
    if (itemError != null) throw itemError!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype'),
      data: itemBody ?? {'data': itemRows},
    );
  }

  @override
  Future<_Report> getStockBalanceReport({
    required String fromDate,
    required String toDate,
    List<String>? itemCodes,
    List<String>? warehouses,
    String? itemGroup,
    String? warehouseType,
    String? rack,
    String? includeUom,
    bool showDimensionWise = false,
    bool showVariantAttributes = false,
    bool showStockAgeing = false,
    bool ignoreClosingBalance = false,
    bool includeZeroStockItems = false,
  }) async {
    reportCalls.add({
      'fromDate': fromDate,
      'toDate': toDate,
      'itemCodes': itemCodes,
      'warehouses': warehouses,
      'showDimensionWise': showDimensionWise,
    });
    if (reportError != null) throw reportError!;
    return (columns: <Map<String, dynamic>>[], rows: reportRows);
  }
}

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  response: Response(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: status,
  ),
  type: DioExceptionType.badResponse,
);

List<String> _codes(int n) => List.generate(n, (i) => '${2000000 + i}');

void main() {
  late _FakeApi api;
  late StockSheetProvider provider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor starts _initDio(), which asks path_provider.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => '/tmp/test_cookies',
        );
  });

  setUp(() {
    api = _FakeApi();
    provider = StockSheetProvider(
      api: api,
      now: () => DateTime(2026, 11, 17, 9, 5),
    );
  });

  group('fetchItems', () {
    test('sends the exact Item query and maps the rows', () async {
      api.itemRows = [
        {
          'name': '2001141',
          'item_name': 'Strap A',
          'variant_of': 'Strap',
          'country_of_origin': 'Italy',
        },
        {
          'name': '2001142',
          'item_name': 'Buckle',
          'variant_of': null,
          'country_of_origin': '',
        },
      ];
      final items = await provider.fetchItems(['2001141', '2001142']);

      expect(api.itemCalls.single['doctype'], 'Item');
      expect(api.itemCalls.single['fields'], [
        'name',
        'item_name',
        'variant_of',
        'country_of_origin',
      ]);
      expect(api.itemCalls.single['filterTuples'], [
        [
          'Item',
          'name',
          'in',
          ['2001141', '2001142'],
        ],
      ]);
      expect(api.itemCalls.single['limit'], 0);
      expect(items['2001141']!.variantOf, 'Strap');
      expect(items['2001142']!.variantOf, isNull);
      expect(items['2001142']!.countryOfOrigin, isNull);
    });

    test('150 codes make 2 calls; duplicates are sent once', () async {
      await provider.fetchItems([..._codes(150), ..._codes(10)]);
      expect(api.itemCalls.length, 2);
      final sizes = api.itemCalls
          .map((c) => (c['filterTuples'] as List).single[3].length as int)
          .toList();
      expect(sizes, [100, 50]);
    });

    test('a malformed Item response is an error, not "not in ERP"', () async {
      for (final body in <Object>[
        {'data': 'oops'},
        {'message': 'no data key'},
        'not a map',
      ]) {
        api.itemBody = body;
        await expectLater(
          provider.fetchItems(['2001141']),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Unexpected Item response',
            ),
          ),
        );
      }
    });

    test('403 becomes StockAccessDenied; other errors are rethrown', () async {
      api.itemError = _http(403);
      await expectLater(
        provider.fetchItems(['2001141']),
        throwsA(isA<StockAccessDenied>()),
      );
      api.itemError = _http(500);
      await expectLater(
        provider.fetchItems(['2001141']),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('fetchFinishedGoodsStock', () {
    test('sends today, Finished Goods and the chunk', () async {
      api.reportRows = [
        {'item_code': '2001141', 'bal_qty': 3},
      ];
      final rows = await provider.fetchFinishedGoodsStock(['2001141']);

      expect(api.reportCalls.single['fromDate'], '2026-11-17');
      expect(api.reportCalls.single['toDate'], '2026-11-17');
      expect(api.reportCalls.single['warehouses'], ['Finished Goods - KA']);
      expect(api.reportCalls.single['itemCodes'], ['2001141']);
      expect(api.reportCalls.single['showDimensionWise'], isTrue);
      expect(rows.single['bal_qty'], 3);
    });

    test('150 codes make 2 report calls', () async {
      await provider.fetchFinishedGoodsStock(_codes(150));
      expect(api.reportCalls.length, 2);
    });

    test('drops rows for codes outside the chunk (v15 < 15.72)', () async {
      api.reportRows = [
        {'item_code': '2001141', 'bal_qty': 3},
        {'item_code': '2009999', 'bal_qty': 8},
      ];
      final rows = await provider.fetchFinishedGoodsStock(['2001141']);
      expect(rows.map((r) => r['item_code']), ['2001141']);
    });

    test('403 becomes StockAccessDenied; other errors are rethrown', () async {
      api.reportError = _http(403);
      await expectLater(
        provider.fetchFinishedGoodsStock(['2001141']),
        throwsA(isA<StockAccessDenied>()),
      );
      api.reportError = _http(500);
      await expectLater(
        provider.fetchFinishedGoodsStock(['2001141']),
        throwsA(isA<DioException>()),
      );
    });
  });
}
