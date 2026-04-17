import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class StockEntryProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getStockEntries({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Stock Entry',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: [
        'name',
        'purpose',
        'total_amount',
        'custom_total_qty',
        'modified',
        'modified_by',
        'docstatus',
        'creation',
        'owner',
        'stock_entry_type',
        'from_warehouse',
        'to_warehouse',
        'posting_date',
      ],
    );
  }

  Future<Response> getStockEntryTypes() async {
    return _apiProvider.getDocumentList(
      'Stock Entry Type',
      limit: 0,
      fields: ['name'],
      orderBy: 'name asc',
    );
  }

  Future<Response> getStockEntry(String name) async {
    return _apiProvider.getStockEntry(name);
  }

  Future<Response> createStockEntry(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Stock Entry', data);
  }

  Future<Response> updateStockEntry(
      String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Stock Entry', name, data);
  }

  /// Calls ERP's whitelisted helper to fetch the pre-populated items
  /// list for a Manufacture Stock Entry linked to [workOrderName].
  ///
  /// Returns the full SE document payload including items (required_items
  /// components as source rows + production_item as the target row).
  /// Calls ERP's whitelisted helper to fetch the pre-populated items
  /// list for a Manufacture Stock Entry linked to [workOrderName].
  Future<Response> getItemsForManufactureEntry({
    required String workOrderName,
    required double fgCompletedQty,
  }) async {
    return await _apiProvider.dio.post(
      '/api/method/erpnext.manufacturing.doctype.work_order.work_order.make_stock_entry',
      data: {
        'work_order_id': workOrderName,
        'purpose':       'Manufacture',
        'qty':           fgCompletedQty,
      },
    );
  }

  /// Finds the most recent submitted "Material Transfer for Manufacture"
  /// Stock Entry linked to [workOrderName].
  /// Returns the SE name, or null if none exists.
  Future<String?> getLinkedTransferSE(String workOrderName) async {
    final res = await _apiProvider.getDocumentList(
      'Stock Entry',
      filters: {
        'work_order':       ['=', workOrderName],
        'stock_entry_type': ['=', 'Material Transfer for Manufacture'],
        'docstatus':        ['=', 1],
      },
      fields: ['name'],
      orderBy: 'creation desc',
      limit: 1,
    );
    if (res.statusCode == 200 && res.data['data'] != null) {
      final list = res.data['data'] as List;
      if (list.isNotEmpty) return list.first['name'] as String?;
    }
    return null;
  }

  /// Fetches all items from [seName] and returns a lookup map of
  /// item_code → {batch_no, rack} using your custom rack field name.
  Future<Map<String, TransferRow>> getTransferSEItemLookup(
      String seName) async {
    final res = await _apiProvider.getDocument('Stock Entry', seName);
    if (res.statusCode != 200 || res.data['data'] == null) return {};
    final items = res.data['data']['items'] as List? ?? [];
    final lookup = <String, TransferRow>{};
    for (final row in items) {
      final code = row['item_code'] as String? ?? '';
      if (code.isEmpty) continue;
      lookup[code] = TransferRow(
        batchNo: row['batch_no'] as String?,
        rack:    row['rack'] as String?,
      );
    }
    return lookup;
  }
}

// ── Private data carrier ───────────────────────────────────────────────────────
class TransferRow {
  final String? batchNo;
  final String? rack;
  const TransferRow({this.batchNo, this.rack});
}
