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
        'name', 'production_item', 'item_name', 'bom_no',
        'qty', 'produced_qty', 'status', 'planned_start_date',
        'docstatus', 'modified', 'wip_warehouse', 'fg_warehouse',
      ],
      orderBy: 'modified desc',
    );
  }

  Future<Response> getWorkOrder(String name) async =>
      _apiProvider.getDocument('Work Order', name);

  Future<Response> createWorkOrder(Map<String, dynamic> data) async =>
      _apiProvider.createDocument('Work Order', data);

  Future<Response> updateWorkOrder(String name, Map<String, dynamic> data) async =>
      _apiProvider.updateDocument('Work Order', name, data);

  /// Submit the Work Order (docstatus = 1).
  /// ERPNext on_submit hook auto-creates Job Cards when the BOM has operations.
  Future<Response> submitWorkOrder(String name) async =>
      _apiProvider.updateDocument('Work Order', name, {'docstatus': 1});

  /// Fetch existing Job Cards for a Work Order.
  Future<Response> getJobCards(String workOrderName) async =>
      _apiProvider.getDocumentList(
        'Job Card',
        filters: {'work_order': workOrderName},
        fields: [
          'name', 'work_order', 'operation', 'operation_id',
          'workstation', 'status', 'for_quantity',
          'total_completed_qty', 'process_loss_qty',
          'docstatus', 'modified', 'posting_date',
        ],
        limit: 100,
        orderBy: 'modified desc',
      );

  /// Fallback: create Job Cards manually via POST+JSON body.
  /// Only call when getJobCards() returns an empty list after submit.
  /// GET with query-string notation is NOT supported by frappe.form_dict
  /// for nested list/dict arguments — must be POST with JSON body.
  Future<Response> makeJobCard({
    required String workOrderName,
    required List<Map<String, dynamic>> operations,
  }) async {
    return _apiProvider.dio.post(
      '/api/method/erpnext.manufacturing.doctype.work_order.work_order.make_job_card',
      data: {
        'work_order': workOrderName,
        'operations': operations,
      },
    );
  }

  Future<Response> getBom(String bomNo) async =>
      _apiProvider.getDocument('BOM', bomNo);

  Future<Response> searchBoms(String itemCode) async =>
      _apiProvider.getDocumentList(
        'BOM',
        filters: {'item': itemCode, 'is_active': 1, 'is_default': 1},
        fields: ['name', 'item', 'item_name', 'quantity'],
        limit: 20,
      );

  Future<Response> getBomsForItem(String itemCode) async =>
      _apiProvider.getDocumentList(
        'BOM',
        filters: {'item': itemCode, 'is_active': 1},
        fields: ['name', 'item', 'item_name', 'quantity'],
        limit: 50,
      );

  /// Fetch existing Stock Entries of type "Material Transfer for Manufacture"
  /// for this Work Order — used to check if materials have been issued.
  Future<Response> getMaterialTransferForManufacture(String workOrderName) async =>
      _apiProvider.getDocumentList(
        'Stock Entry',
        filters: {
          'work_order': workOrderName,
          'stock_entry_type': 'Material Transfer for Manufacture',
          'docstatus': 1,
        },
        fields: [
          'name', 'work_order', 'stock_entry_type',
          'posting_date', 'docstatus', 'total_amount',
        ],
        limit: 100,
        orderBy: 'modified desc',
      );
}