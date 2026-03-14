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
}
