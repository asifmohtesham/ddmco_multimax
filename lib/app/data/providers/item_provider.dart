import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';

class ItemProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getItems({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Item',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: ['name', 'item_name', 'item_code', 'item_group', 'image', 'variant_of', 'country_of_origin', 'description', 'stock_uom'],
    );
  }

  // ... (Item Groups, Templates, Attributes methods remain the same) ...

  Future<Response> getItemGroups() async {
    return _apiProvider.getDocumentList(
      'Item Group',
      limit: 0,
      fields: ['name'],
      orderBy: 'name asc',
    );
  }

  Future<Response> getTemplateItems() async {
    return _apiProvider.getDocumentList(
      'Item',
      limit: 0,
      filters: {'has_variants': 1},
      fields: ['name'],
      orderBy: 'name asc',
    );
  }

  Future<Response> getItemAttributes() async {
    return _apiProvider.getDocumentList(
      'Item Attribute',
      limit: 0,
      fields: ['name'],
      orderBy: 'name asc',
    );
  }

  Future<Response> getItemAttributeDetails(String name) async {
    return _apiProvider.getDocument('Item Attribute', name);
  }

  Future<Response> getItemVariantsByAttribute(String attribute, String value) async {
    return _apiProvider.getDocumentList(
      'Item Variant Attribute',
      filters: {
        'attribute': attribute,
        'attribute_value': value
      },
      fields: ['parent'],
      limit: 5000,
    );
  }

  Future<Response> getStockLevels(String itemCode) async {
    return _apiProvider.getReport('Stock Balance', filters: {'item_code': itemCode});
  }

  // NEW: Fetch Stock Balance by Warehouse (used for Rack lookup)
  Future<Response> getWarehouseStock(String warehouse) async {
    return _apiProvider.getReport('Stock Balance', filters: {'warehouse': warehouse});
  }

  Future<Response> getStockLedger(String itemCode, {DateTime? fromDate, DateTime? toDate}) async {
    final Map<String, dynamic> filters = {'item_code': itemCode};

    if (fromDate != null && toDate != null) {
      filters['posting_date'] = ['between', [
        DateFormat('yyyy-MM-dd').format(fromDate),
        DateFormat('yyyy-MM-dd').format(toDate)
      ]];
    }

    return _apiProvider.getDocumentList(
      'Stock Ledger Entry',
      filters: filters,
      fields: ['posting_date', 'posting_time', 'warehouse', 'actual_qty', 'qty_after_transaction', 'voucher_type', 'voucher_no', 'batch_no'],
      orderBy: 'posting_date desc, posting_time desc',
      limit: 50,
    );
  }

  Future<Response> getBatchWiseHistory(String itemCode) async {
    final fromDate = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 365)));
    final toDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return _apiProvider.getReport('Batch-Wise Balance History', filters: {
      'item_code': itemCode,
      'from_date': fromDate,
      'to_date': toDate,
    });
  }
}