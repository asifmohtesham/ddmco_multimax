import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/work_order_model.dart';
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
          'docstatus', 'modified', 'posting_date','owner',
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

  /// Fetches the most recently modified Work Orders with no status/owner filter.
  /// Used by report filter sheets to pre-populate a picker without requiring search input.
  Future<List<WorkOrder>> fetchRecent({int limit = 20}) async {
    try {
      final response = await _apiProvider.getList(
        'Work Order',
        doctype: 'Work Order',
        fields: ['name', 'production_item', 'item_name', 'status', 'planned_start_date'],
        filters: null,            // no filters — all statuses, all owners
        orderBy: 'creation desc',
        // limitPageLength: limit,
        // limitStart: 0,
      );
      final data = response as List<dynamic>? ?? [];
      return data.map((e) => WorkOrder.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch the first open Job Card linked to a Work Order.
  Future<String?> fetchOpenJobCardName(String workOrderName) async {
    final res = await _apiProvider.getDocumentList(
      'Job Card',
      filters: {
        'work_order': workOrderName,
        'docstatus': 0,
      },
      fields: ['name'],
      limit: 1,
    );
    if (res.statusCode == 200 && (res.data['data'] as List).isNotEmpty) {
      return (res.data['data'] as List).first['name'] as String;
    }
    return null;
  }

  /// Create a Material Transfer for Manufacture Stock Entry linked to a Job Card.
  Future<Response> createStockEntry(Map<String, dynamic> data) async =>
      _apiProvider.createDocument('Stock Entry', data);

  /// Submit a saved Stock Entry (docstatus 0 → 1).
  Future<Response> submitStockEntry(String name) async =>
      _apiProvider.updateDocument('Stock Entry', name, {'docstatus': 1});

  /// Fetch a single Job Card document (including its items child table).
  Future<Response> getJobCard(String name) async =>
      _apiProvider.getDocument('Job Card', name);

  /// Call the Job Card's make_stock_entry whitelisted method.
  /// Returns a draft Stock Entry with job_card_item set on every item row.
  /// Must be used instead of manually building item rows — ERP's
  /// validate_job_card_item() rejects manually-constructed rows.
  Future<Response> makeStockEntryFromJobCard(String jobCardName) async =>
      _apiProvider.dio.post(
        '/api/method/erpnext.manufacturing.doctype.job_card.job_card.make_stock_entry',
        data: {'source_name': jobCardName},
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

  Future<Response> updateWorkOrderOperationWorkstation({
    required String workOrderName,
    required String operationRowName,
    required String workstation,
  }) {
    return _apiProvider.dio.put(
      '/api/resource/Work Order Operation/$operationRowName',
      data: {'workstation': workstation},
    );
  }

  // ── Workstation Type ────────────────────────────────────────────────────────
  Future<Response> updateOperationWorkstationType({
    required String operationRowName,
    required String workstationType,
  }) => _apiProvider.dio.put(
    '/api/resource/Work Order Operation/$operationRowName',
    data: {'workstation_type': workstationType},
  );

  // ── Planned Start Time ─────────────────────────────────────────────────────
  Future<Response> updateOperationPlannedStartTime({
    required String operationRowName,
    required String plannedStartTime,   // ISO 8601: "yyyy-MM-dd HH:mm:ss"
  }) => _apiProvider.dio.put(
    '/api/resource/Work Order Operation/$operationRowName',
    data: {'planned_start_time': plannedStartTime},
  );

  // ── Planned End Time ───────────────────────────────────────────────────────
  Future<Response> updateOperationPlannedEndTime({
    required String operationRowName,
    required String plannedEndTime,
  }) => _apiProvider.dio.put(
    '/api/resource/Work Order Operation/$operationRowName',
    data: {'planned_end_time': plannedEndTime},
  );

  Future<Response> updateOperationSourceWarehouse({
    required String operationRowName,
    required String sourceWarehouse,
  }) {
    return _apiProvider.dio.put(
      '/api/resource/Work Order Operation/$operationRowName',
      data: {'source_warehouse': sourceWarehouse},
    );
  }
}
