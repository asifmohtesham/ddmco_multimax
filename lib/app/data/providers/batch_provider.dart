// app/data/providers/batch_provider.dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class BatchProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getBatches({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Batch',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: ['name', 'item', 'description', 'manufacturing_date', 'expiry_date', 'custom_packaging_qty', 'custom_purchase_order', 'modified', 'creation'],
    );
  }

  Future<Response> getBatch(String name) async {
    return _apiProvider.getDocument('Batch', name);
  }

  Future<Response> createBatch(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Batch', data);
  }

  Future<Response> updateBatch(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Batch', name, data);
  }

  // --- Helpers for Dropdowns ---

  Future<Response> searchItems(String query) async {
    return _apiProvider.getDocumentList(
      'Item',
      filters: {
        'item_code': ['like', '%$query%'],
        'disabled': 0,
        'has_batch_no': 1 // Only fetch batch-managed items
      },
      fields: ['item_code', 'item_name', 'barcodes'], // Fetch barcodes child table or field
      limit: 20,
    );
  }

  Future<Response> getItemDetails(String itemCode) async {
    return _apiProvider.getDocument('Item', itemCode);
  }

  Future<Response> searchPurchaseOrders(String query) async {
    return _apiProvider.getDocumentList(
        'Purchase Order',
        filters: {
          'name': ['like', '%$query%'],
          'docstatus': ['<', 2] // Draft (0) and Submitted (1)
        },
        fields: ['name', 'supplier', 'transaction_date'],
        limit: 20,
        orderBy: 'modified desc'
    );
  }
}