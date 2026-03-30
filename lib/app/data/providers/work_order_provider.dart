import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class WorkOrderProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getWorkOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
  }) async {
    return _apiProvider.getDocumentList(
      'Work Order',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
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

  // ── Submit, Execute & Job Card ────────────────────────────────────────────────

  /// Submit a Work Order by setting docstatus to 1.
  ///
  /// ERPNext validates submission server-side (required qty, BOM active,
  /// warehouses set). Any validation error is returned as a 417/400 with
  /// `exc_type` in the response body — the controller handles this.
  Future<Response> submitWorkOrder(String name) async =>
      _apiProvider.updateDocument('Work Order', name, {'docstatus': 1});

  /// Execute a submitted Work Order: transitions status from
  /// "Not Started" → "In Progress" via the ERPNext whitelisted method.
  ///
  /// Internally calls `set_work_order_ops` server method which validates
  /// that the Work Order is submitted (docstatus == 1) and updates the
  /// `status` field to "In Progress" along with resetting planned times.
  Future<Response> executeWorkOrder(String name) async =>
      _apiProvider.callMethod(
        'erpnext.manufacturing.doctype.work_order.work_order.update_work_order_status',
        params: {
          'work_order': name,
          'status': 'In Progress',
        },
      );

  /// Create Job Cards for the selected operations on a submitted Work Order.
  ///
  /// Calls the whitelisted server method:
  ///   `erpnext.manufacturing.doctype.work_order.work_order.make_job_card`
  ///
  /// [workOrderName] — the Work Order document name.
  /// [operations] — list of operation row payloads built via
  ///   `WorkOrderOperation.toJobCardPayload(qty: pendingQty)`. Each map
  ///   must include: `name`, `operation`, `qty`, `pending_qty`,
  ///   `sequence_id`, `batch_size`, and optionally `workstation`.
  ///
  /// Returns the list of created Job Card names in `message`.
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
