// app/data/providers/batch_provider.dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class BatchProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  static const List<String> _listFields = [
    'name',
    'item',
    'description',
    'manufacturing_date',
    'expiry_date',
    'custom_packaging_qty',
    'custom_purchase_order',
    'custom_supplier',
    'disabled',
    'modified',
    'creation',
  ];

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
      fields: _listFields,
    );
  }

  Future<Response> getBatch(String name) async {
    return _apiProvider.getDocument('Batch', name);
  }

  Future<Response> createBatch(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Batch', data);
  }

  Future<Response> updateBatch(
      String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Batch', name, data);
  }

  // ── Dropdown / search helpers ─────────────────────────────────────────────

  /// Batch-managed items only.
  Future<Response> searchItems(String query) async {
    return _apiProvider.getDocumentList(
      'Item',
      filters: {
        'item_code': ['like', '%$query%'],
        'disabled': 0,
        'has_variants': 0,
        'has_batch_no': 1,
      },
      fields: ['item_code', 'item_name'],
      limit: 20,
    );
  }

  Future<Response> getItemDetails(String itemCode) async {
    return _apiProvider.getDocument('Item', itemCode);
  }

  /// Search Purchase Orders by name (or supplier for display).
  Future<Response> searchPurchaseOrders(String query) async {
    return _apiProvider.getDocumentList(
      'Purchase Order',
      filters: {
        'name': ['like', '%$query%'],
        'docstatus': ['<', 2],
      },
      fields: ['name', 'supplier', 'transaction_date'],
      limit: 20,
      orderBy: 'modified desc',
    );
  }

  /// Search Batch documents by name — used by the Batch No picker.
  Future<Response> searchBatchNames(String query) async {
    return _apiProvider.getDocumentList(
      'Batch',
      filters: {
        'name': ['like', '%$query%'],
      },
      fields: ['name', 'item'],
      limit: 20,
      orderBy: 'name asc',
    );
  }

  /// Search Supplier list.
  Future<Response> searchSuppliers(String query) async {
    return _apiProvider.getDocumentList(
      'Supplier',
      filters: {
        'supplier_name': ['like', '%$query%'],
        'disabled': 0,
      },
      fields: ['name', 'supplier_name'],
      limit: 20,
      orderBy: 'name asc',
    );
  }
}
