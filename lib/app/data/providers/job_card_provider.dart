import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class JobCardProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  static const String _makeTimeLogMethod =
      'erpnext.manufacturing.doctype.job_card.job_card.make_time_log';

  /// Request parameters for `make_time_log`.
  ///
  /// ERPNext v15 declares the payload parameter as `args`; v16 renamed it to
  /// `kwargs`. Frappe drops request keys the target function does not
  /// declare, so sending both lets one request work against either version.
  static Map<String, dynamic> timeLogParams(Map<String, dynamic> payload) {
    final encoded = json.encode(payload);
    return {'args': encoded, 'kwargs': encoded};
  }

  /// Document fields that put a draft Job Card on hold or take it off hold.
  ///
  /// v15 stores the hold in `status`. v16 recomputes `status` on every save
  /// from the `is_paused` flag, so the flag is what has to be written there.
  /// Each server ignores the key it does not use.
  static Map<String, dynamic> pausePayload({required bool paused}) => paused
      ? {'status': 'On Hold', 'is_paused': 1}
      : {'is_paused': 0};

  // ── List ───────────────────────────────────────────────────────────────────

  Future<Response> getJobCards({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String? groupBy = '',
  }) async {
    return _apiProvider.getDocumentList(
      'Job Card',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orFilters: orFilters,
      fields: [
        'name',
        'work_order',
        'operation',
        'operation_id',
        'workstation',
        'status',
        'for_quantity',
        'total_completed_qty',
        'process_loss_qty',
        'docstatus',
        'modified',
        'posting_date',
      ],
      orderBy: 'modified desc',
      groupBy: groupBy
    );
  }

  // ── Single document ──────────────────────────────────────────────────────

  Future<Response> getJobCard(String name) async =>
      _apiProvider.getDocument('Job Card', name);

  // ── Time log: add ────────────────────────────────────────────────────────

  Future<Response> addTimeLog({
    required String jobCardId,
    required String startTime,
    String? completeTime,
    required double completedQty,
    required List<Map<String, dynamic>> employees,
    required String status,
  }) async {
    final Map<String, dynamic> argsMap = {
      'job_card_id':   jobCardId,
      'start_time':    startTime,
      if (completeTime != null) 'complete_time': completeTime,
      'completed_qty': completedQty,
      'employees':     employees,
      'status':        status,
    };
    return _apiProvider.callMethodPost(
      _makeTimeLogMethod,
      params: timeLogParams(argsMap),
    );
  }

  // ── Time log: update ─────────────────────────────────────────────────────

  Future<Response> updateTimeLog({
    required String timeLogName,
    required String toTime,
    required double completedQty,
    String? employee,
  }) async {
    final Map<String, dynamic> payload = {
      'to_time':       toTime,
      'completed_qty': completedQty,
      if (employee != null && employee.isNotEmpty) 'employee': employee,
    };
    return _apiProvider.updateDocument(
      'Job Card Time Log',
      timeLogName,
      payload,
    );
  }

  // ── Time log: delete ─────────────────────────────────────────────────────

  Future<Response> deleteTimeLog(String timeLogName) async =>
      _apiProvider.deleteDocument('Job Card Time Log', timeLogName);

  Future<Response> touchJobCard(String jobCardName) async =>
      _apiProvider.updateDocument('Job Card', jobCardName, {});

  // ── Status transitions ────────────────────────────────────────────────

  Future<Response> updateJobCardStatus({
    required String jobCardId,
    required String status,
    required String startTime,
    String? completeTime,
    double completedQty = 0,
    required List<Map<String, dynamic>> employees,
  }) async {
    final Map<String, dynamic> argsMap = {
      'job_card_id':   jobCardId,
      'start_time':    startTime,
      'complete_time': completeTime ?? '',
      'completed_qty': completedQty,
      'employees':     employees,
      'status':        status,
    };
    return _apiProvider.callMethodPost(
      _makeTimeLogMethod,
      params: timeLogParams(argsMap),
    );
  }

  // ── Header fields update ───────────────────────────────────────────────

  /// Persist one or more header-level fields on a draft Job Card.
  ///
  /// Supported keys: `workstation`, `employee`, `wip_warehouse`.
  /// Pass only the field(s) that changed; ERPNext ignores unknown keys.
  Future<Response> updateJobCardHeaderField({
    required String jobCardName,
    required Map<String, dynamic> data,
  }) async =>
      _apiProvider.updateDocument('Job Card', jobCardName, data);

  // ── Hold / release ─────────────────────────────────────────────────────

  /// Puts the Job Card on hold ([paused] true) or releases it.
  ///
  /// `make_time_log` only closes or opens time log rows; the hold itself
  /// lives on the parent document. See [pausePayload] for the fields sent.
  Future<Response> setJobCardPaused(
    String jobCardName, {
    required bool paused,
  }) async =>
      _apiProvider.updateDocument(
        'Job Card',
        jobCardName,
        pausePayload(paused: paused),
      );

  // ── Submission ─────────────────────────────────────────────────────────

  Future<Response> submitJobCard(String name) async =>
      _apiProvider.submitDocument('Job Card', name);

  /// Fetches all Active employees — used by JobCardFormController
  /// to populate the employee picker sheet.
  Future<Response> getActiveEmployees() async {
    return _apiProvider.getDocumentList(
      'Employee',
      filters: {'status': 'Active'},
      fields: ['name', 'employee_name', 'department'],
      limit: 0,
    );
  }
}
