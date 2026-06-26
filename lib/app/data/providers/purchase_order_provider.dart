import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';

class PurchaseOrderProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPurchaseOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Purchase Order',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status', 'docstatus', 'modified', 'creation'],
      orderBy: orderBy,
    );
  }

  Future<Response> getPurchaseOrder(String name) async {
    return _apiProvider.getDocument('Purchase Order', name);
  }

  Future<Response> createPurchaseOrder(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Purchase Order', data);
  }

  Future<Response> updatePurchaseOrder(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Purchase Order', name, data);
  }

  /// Open (draft, docstatus 0) Purchase Receipts that reference [poName]
  /// through any of their items, summarised for the resume-or-create sheet.
  ///
  /// Two calls: (1) the `Purchase Receipt Item` child rows carrying this PO
  /// (child rows mirror the parent's docstatus, so `docstatus == 0` selects
  /// rows of draft receipts), reduced to distinct parents; (2) those parents'
  /// headers for their posting dates. Returns an empty list when none exist.
  /// Network/parse failures propagate to the caller, which treats them as
  /// fail-open (create-new).
  Future<List<DraftReceiptSummary>> getOpenDraftReceiptsForPo(
      String poName) async {
    final childResp = await _apiProvider.getDocumentList(
      'Purchase Receipt Item',
      limit: 0,
      filters: {
        'purchase_order': poName,
        'docstatus': 0,
      },
      fields: ['parent'],
    );

    final parents = parseDraftReceiptParents(childResp.data);
    if (parents.isEmpty) return const [];

    final headerResp = await _apiProvider.getDocumentList(
      'Purchase Receipt',
      limit: 0,
      filters: {
        'name': ['in', parents],
      },
      fields: ['name', 'posting_date'],
    );

    final data = headerResp.data;
    final rows = (data is Map && data['data'] is List)
        ? data['data'] as List
        : const [];

    return rows
        .whereType<Map>()
        .map((r) => DraftReceiptSummary(
              name: (r['name'] ?? '').toString(),
              postingDate: (r['posting_date'] ?? '').toString(),
            ))
        .where((d) => d.name.isNotEmpty)
        .toList();
  }
}