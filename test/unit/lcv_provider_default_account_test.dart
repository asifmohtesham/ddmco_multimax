import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';

Response<dynamic> _ok(dynamic data) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': data},
    );

/// Answers the Company and Account reads the way v15 / v16 servers do.
class _FakeApiProvider extends ApiProvider {
  /// The Company document. v15 carries `expenses_included_in_valuation`;
  /// v16 removed the field, so its documents omit the key entirely.
  Map<String, dynamic> company = {'name': 'Multimax'};
  bool companyThrows = false;

  /// Accounts returned by the account_type lookup.
  List<String> valuationAccounts = [];
  bool accountsThrows = false;

  Map<String, dynamic>? lastAccountFilters;

  @override
  Future<Response> getDocument(String doctype, String name) async {
    expect(doctype, 'Company');
    if (companyThrows) throw DioException(requestOptions: RequestOptions());
    return _ok(company);
  }

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
    expect(doctype, 'Account');
    lastAccountFilters = filters;
    if (accountsThrows) throw DioException(requestOptions: RequestOptions());
    return _ok([
      for (final a in valuationAccounts) {'name': a},
    ]);
  }
}

void main() {
  late _FakeApiProvider api;
  late LandedCostVoucherProvider provider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  setUp(() {
    api = Get.put<ApiProvider>(_FakeApiProvider()) as _FakeApiProvider;
    provider = LandedCostVoucherProvider();
  });
  tearDown(() => Get.deleteAll(force: true));

  test('v15: uses the Company default when it is set', () async {
    api.company = {
      'name': 'Multimax',
      'expenses_included_in_valuation': 'Landed Costs - KA',
    };
    api.valuationAccounts = ['Expenses Included In Valuation - KA'];

    expect(await provider.getDefaultChargeAccount('Multimax'),
        'Landed Costs - KA');
  });

  test('v16: the Company field is gone, so the single valuation account '
      'of that company is used', () async {
    api.valuationAccounts = ['Expenses Included In Valuation - KA'];

    expect(await provider.getDefaultChargeAccount('Multimax'),
        'Expenses Included In Valuation - KA');
    expect(api.lastAccountFilters, {
      'company': 'Multimax',
      'account_type': 'Expenses Included In Valuation',
      'is_group': 0,
      'disabled': 0,
    });
  });

  test('an empty Company field falls back to the account lookup', () async {
    api.company = {'name': 'Multimax', 'expenses_included_in_valuation': ''};
    api.valuationAccounts = ['Expenses Included In Valuation - KA'];

    expect(await provider.getDefaultChargeAccount('Multimax'),
        'Expenses Included In Valuation - KA');
  });

  test('several valuation accounts: no guess, the user picks', () async {
    api.valuationAccounts = ['EIIV Freight - KA', 'EIIV Customs - KA'];

    expect(await provider.getDefaultChargeAccount('Multimax'), isNull);
  });

  test('an unreadable Company still falls back to the account lookup',
      () async {
    api.companyThrows = true;
    api.valuationAccounts = ['Expenses Included In Valuation - KA'];

    expect(await provider.getDefaultChargeAccount('Multimax'),
        'Expenses Included In Valuation - KA');
  });

  test('both lookups failing yields no prefill, not an error', () async {
    api.companyThrows = true;
    api.accountsThrows = true;

    expect(await provider.getDefaultChargeAccount('Multimax'), isNull);
  });
}
