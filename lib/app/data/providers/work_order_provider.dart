import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class WorkOrderProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getWorkOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
  }) async {
    return _apiProvider.getDocumentList(
      'Work Order',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orFilters: orFilters,
      fields: [
        'name',
        'production_item',
        'item_name',
        'bom_no',
        'qty',
        'produced_qty',
        'status',
        'planned_start_date',
        'docstatus',
        'modified',
        'wip_warehouse',
        'fg_warehouse',
      ],
      orderBy: 'modified desc',
    );
  }

  Future<Response> getWorkOrder(String name) async =>
      _apiProvider.getDocument('Work Order', name);

  Future<Response> createWorkOrder(Map<String, dynamic> data) async =>
      _apiProvider.createDocument('Work Order', data);

  Future<Response> updateWorkOrder(
          String name, Map<String, dynamic> data) async =>
      _apiProvider.updateDocument('Work Order', name, data);

  /// Fetch BOM details (bom_no, wip_warehouse, fg_warehouse, item_name)
  /// from the BOM document to auto-populate the form.
  Future<Response> getBom(String bomNo) async =>
      _apiProvider.getDocument('BOM', bomNo);

  /// Search BOMs filtered by item code for the typeahead picker.
  Future<Response> searchBoms(String itemCode) async =>
      _apiProvider.getDocumentList(
        'BOM',
        filters: {'item': itemCode, 'is_active': 1, 'is_default': 1},
        fields: ['name', 'item', 'item_name', 'quantity'],
        limit: 20,
      );

  /// Get all active BOMs for an item (for when there is no default).
  Future<Response> getBomsForItem(String itemCode) async =>
      _apiProvider.getDocumentList(
        'BOM',
        filters: {'item': itemCode, 'is_active': 1},
        fields: ['name', 'item', 'item_name', 'quantity'],
        limit: 50,
      );

  // ── Submit & Job Card ───────────────────────────────────────────────────

  /// Submit a Work Order by setting docstatus to 1.
  Future<Response> submitWorkOrder(String name) async =>
      _apiProvider.updateDocument('Work Order', name, {'docstatus': 1});

  // ── Execute: Material Transfer for Manufacture ──────────────────────────

  /// Ask ERPNext to build a pre-filled Material Transfer for Manufacture
  /// Stock Entry for [workOrderName].
  Future<Response> getMaterialTransferForManufacture(
    String workOrderName, {
    required double qty,
  }) async =>
      _apiProvider.callMethod(
        'erpnext.manufacturing.doctype.work_order.work_order.make_stock_entry',
        params: {
          'work_order_id': workOrderName,
          'purpose': 'Material Transfer for Manufacture',
          'qty': qty,
        },
      );

  /// Save a pre-filled Stock Entry document returned by
  /// [getMaterialTransferForManufacture] (or any other SE builder).
  Future<Response> saveStockEntry(Map<String, dynamic> data) async =>
      _apiProvider.createDocument('Stock Entry', data);

  /// Submit a saved Stock Entry (docstatus 0 → 1).
  Future<Response> submitStockEntry(String stockEntryName) async =>
      _apiProvider.updateDocument(
        'Stock Entry',
        stockEntryName,
        {'docstatus': 1},
      );

  /// Create Job Cards for the selected operations on a submitted Work Order.
  Future<Response> makeJobCard(
    String workOrderName,
    List<Map<String, dynamic>> operations,
  ) async =>
      _apiProvider.callMethod(
        'erpnext.manufacturing.doctype.work_order.work_order.make_job_card',
        params: {
          'work_order': workOrderName,
          'operations': operations,
        },
      );
}
