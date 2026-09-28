import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class LandedCostVoucherProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getLandedCostVouchers({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Landed Cost Voucher',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: [
        'name',
        'company',
        'docstatus',
        'posting_date',
        'total_taxes_and_charges'
      ],
    );
  }

  Future<Response> getLandedCostVoucher(String name) async {
    return _apiProvider.getDocument('Landed Cost Voucher', name);
  }

  Future<Response> createLandedCostVoucher(Map<String, dynamic> data) =>
      _apiProvider.createDocument('Landed Cost Voucher', data);

  Future<Response> updateLandedCostVoucher(
          String name, Map<String, dynamic> data) =>
      _apiProvider.updateDocument('Landed Cost Voucher', name, data);

  /// Submits with the loaded `modified` timestamp so ERPNext rejects the
  /// submit (TimestampMismatchError) if the document was edited in Desk
  /// after the app loaded it. [ApiProvider.submitDocument] sends no
  /// timestamp, so it can't be used here.
  Future<Response> submitLandedCostVoucher(String name,
          {required String modified}) =>
      _apiProvider.updateDocument('Landed Cost Voucher', name,
          {'docstatus': 1, 'modified': modified});

  Future<bool> canSubmit(String name) async {
    try {
      final res = await _apiProvider.hasDocPermission(
          'Landed Cost Voucher', name, 'submit');
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }

  /// The fields Desk copies onto a receipt row (supplier, posting date,
  /// grand total) plus what the app needs to validate the pick. The server
  /// does not fill these, so the app must send them.
  Future<Map<String, dynamic>?> getReceiptSummary(String receiptName) async {
    final res = await _apiProvider.getDocumentList(
      'Purchase Receipt',
      filters: {'name': receiptName},
      fields: const [
        'name',
        'supplier',
        'posting_date',
        'grand_total',
        'company',
        'docstatus',
      ],
      limit: 1,
    );
    final rows = res.data?['data'] as List?;
    if (res.statusCode != 200 || rows == null || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  /// The company's "Expenses Included In Valuation" account — the usual
  /// home for landed costs — used to prefill a new charge.
  ///
  /// Works on ERPNext v15 and v16: v15 keeps it as the Company field
  /// `expenses_included_in_valuation`; v16 removed that field, so fall back
  /// to the company's only non-group account of that account type. Null
  /// (the user picks) when neither lookup yields exactly one account.
  Future<String?> getDefaultChargeAccount(String company) async {
    try {
      final res = await _apiProvider.getDocument('Company', company);
      final account =
          res.data?['data']?['expenses_included_in_valuation'] as String?;
      if (account != null && account.isNotEmpty) return account;
    } catch (_) {
      // Unreadable Company: the account lookup below may still answer.
    }
    try {
      final res = await _apiProvider.getDocumentList(
        'Account',
        filters: {
          'company': company,
          'account_type': 'Expenses Included In Valuation',
          'is_group': 0,
          'disabled': 0,
        },
        fields: const ['name'],
        limit: 2,
      );
      final rows = res.data?['data'] as List?;
      // Two or more candidates: don't guess which one the user wants.
      if (rows == null || rows.length != 1) return null;
      return rows.first['name'] as String?;
    } catch (_) {
      return null;
    }
  }
}
