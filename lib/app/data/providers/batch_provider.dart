// app/data/providers/batch_provider.dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

/// Data-access layer for the ERPNext **Batch** DocType.
///
/// All methods delegate to [ApiProvider] and return the raw [Response]
/// so callers can inspect `statusCode` and `data` directly.
/// No parsing or error-handling is done here — that responsibility
/// belongs to the calling controller.
class BatchProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  /// Fields fetched for every row in the Batch list view.
  ///
  /// Kept minimal to reduce payload size; the full document is fetched
  /// separately via [getBatch] when the form is opened.
  static const List<String> _listFields = [
    'name',
    'item',
    'description',
    'manufacturing_date',
    'expiry_date',
    'custom_packaging_qty',
    'custom_purchase_order',
    'custom_supplier_name',
    'disabled',
    'modified',
    'creation',
  ];

  /// Returns a paginated list of Batch documents matching [filters].
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

  /// Returns the full Batch document for [name].
  Future<Response> getBatch(String name) async {
    return _apiProvider.getDocument('Batch', name);
  }

  /// Creates a new Batch document with [data].
  Future<Response> createBatch(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Batch', data);
  }

  /// Updates an existing Batch document identified by [name] with [data].
  Future<Response> updateBatch(
      String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Batch', name, data);
  }

  // ── Dropdown / search helpers ─────────────────────────────────────────────

  /// Returns batch-managed items matching [query] against `item_code`.
  ///
  /// Filters: `disabled == 0`, `has_variants == 0`, `has_batch_no == 1`.
  /// Returns fields: `item_code`, `item_name`.  Limit: 20.
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

  /// Returns the full Item document for [itemCode].
  /// Used to resolve `barcodes`, `variant_of`, and other item-master fields.
  Future<Response> getItemDetails(String itemCode) async {
    return _apiProvider.getDocument('Item', itemCode);
  }

  /// Returns Purchase Orders whose `name` matches [query] (LIKE).
  ///
  /// Excludes cancelled documents (`docstatus < 2`).
  /// Returns fields: `name`, `supplier`, `transaction_date`.  Limit: 20.
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

  /// Returns Batch documents whose `name` matches [query] (LIKE).
  /// Used by the Batch No picker in filter and cross-reference contexts.
  /// Returns fields: `name`, `item`.  Ordered `name asc`.  Limit: 20.
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

  /// Returns Supplier documents whose `supplier_name` matches [query] (LIKE).
  ///
  /// Filters: `disabled == 0`.
  /// Returns fields: `name`, `supplier_name`.  Ordered `name asc`.  Limit: 20.
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
