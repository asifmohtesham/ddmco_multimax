// test/helpers/fake_lcv_provider.dart
//
// In-memory LandedCostVoucherProvider shared by the LCV tests. Save calls
// record their payload and echo it back the way ERPNext would (items are
// rebuilt only when the payload sends an empty table).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';

Map<String, dynamic> sampleLcv({int docstatus = 1, String distribute = 'Qty'}) => {
      'name': 'MAT-LCV-2026-00001',
      'company': 'KA',
      'docstatus': docstatus,
      'status': docstatus == 1 ? 'Submitted' : 'Draft',
      'modified': '2026-09-26 10:00:00.000',
      'posting_date': '2026-09-26',
      'distribute_charges_based_on': distribute,
      'total_taxes_and_charges': 150.0,
      'purchase_receipts': [
        {
          'name': 'row-pr-1',
          'receipt_document_type': 'Purchase Receipt',
          'receipt_document': 'MAT-PRE-0001',
          'supplier': 'Acme',
          'grand_total': 1000.0,
        },
      ],
      'items': [
        {
          'name': 'row-item-1',
          'item_code': 'WATCH-001',
          'description': 'Steel watch',
          'receipt_document_type': 'Purchase Receipt',
          'receipt_document': 'MAT-PRE-0001',
          'qty': 10,
          'rate': 100.0,
          'amount': 1000.0,
          'applicable_charges': 150.0,
        },
      ],
      'taxes': [
        {
          'name': 'row-tax-1',
          'description': 'Freight',
          'amount': 150.0,
          'expense_account': 'Freight - KA',
        },
      ],
    };

Response<dynamic> _ok(dynamic data) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': data},
    );

class FakeLcvProvider implements LandedCostVoucherProvider {
  FakeLcvProvider({Map<String, dynamic>? voucher})
      : voucher = voucher ?? sampleLcv();

  Map<String, dynamic> voucher;

  /// Purchase Receipt summaries by name, for [getReceiptSummary].
  final Map<String, Map<String, dynamic>> receipts = {};

  /// Every create/update payload, in order.
  final List<Map<String, dynamic>> saved = [];
  int submitCalls = 0;
  bool submitAllowed = true;

  /// When set, create/update wait on it — lets a test hold a save in flight.
  Completer<void>? saveGate;

  Future<Response> _save(Map<String, dynamic> data, {String? newName}) async {
    saved.add(data);
    await saveGate?.future;
    voucher = {
      ...voucher,
      ...data,
      if (newName != null) 'name': newName,
      'docstatus': 0,
      'status': 'Draft',
      'modified': '2026-09-28 12:00:0${saved.length}.000',
    };
    return _ok(voucher);
  }

  @override
  Future<Response> getLandedCostVouchers({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async =>
      _ok([voucher]);

  @override
  Future<Response> getLandedCostVoucher(String name) async => _ok(voucher);

  @override
  Future<Response> createLandedCostVoucher(Map<String, dynamic> data) =>
      _save(data, newName: 'MAT-LCV-2026-00002');

  @override
  Future<Response> updateLandedCostVoucher(
          String name, Map<String, dynamic> data) =>
      _save(data);

  @override
  Future<Response> submitLandedCostVoucher(String name) async {
    submitCalls++;
    voucher = {...voucher, 'docstatus': 1, 'status': 'Submitted'};
    return _ok(voucher);
  }

  @override
  Future<bool> canSubmit(String name) async => submitAllowed;

  @override
  Future<Map<String, dynamic>?> getReceiptSummary(String receiptName) async =>
      receipts[receiptName];

  @override
  Future<String?> getDefaultChargeAccount(String company) async =>
      'Expenses Included In Valuation - $company';
}
