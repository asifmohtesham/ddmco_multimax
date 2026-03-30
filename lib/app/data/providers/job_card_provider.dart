import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class JobCardProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── List ───────────────────────────────────────────────────────────────────

  Future<Response> getJobCards({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
  }) async {
    return _apiProvider.getDocumentList(
      'Job Card',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: [
        'name',
        'work_order',
        'operation',
        'operation_id',
        'workstation',
        'status',
        'for_quantity',
        'total_completed_qty',
        'process_loss_qty',   // needed for _autoSubmitIfComplete check
        'docstatus',
        'modified',
        'posting_date',
      ],
      orderBy: 'modified desc',
    );
  }

  // ── Single document ──────────────────────────────────────────────────────

  Future<Response> getJobCard(String name) async =>
      _apiProvider.getDocument('Job Card', name);

  // ── Time log: add ────────────────────────────────────────────────────────

  /// Add a manual time log entry to a Job Card via `make_time_log`.
  ///
  /// [status] values:
  ///   `'Work In Progress'` — start / resume
  ///   `'Resume Job'`       — pause
  ///   `'Complete'`         — close session (requires [completeTime])
  Future<Response> addTimeLog({
    required String jobCardId,
    required String startTime,
    String? completeTime,
    required double completedQty,
    required List<Map<String, String>> employees,
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
      'erpnext.manufacturing.doctype.job_card.job_card.make_time_log',
      params: {'args': json.encode(argsMap)},
    );
  }

  // ── Time log: update (PATCH child-table row) ─────────────────────────────

  /// Update an existing **Job Card Time Log** child row.
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

  /// Delete a **Job Card Time Log** child row.
  Future<Response> deleteTimeLog(String timeLogName) async =>
      _apiProvider.deleteDocument('Job Card Time Log', timeLogName);

  /// Touch the parent Job Card (empty PUT) so the server recalculates
  /// `total_completed_qty` after a child-row edit or deletion.
  Future<Response> touchJobCard(String jobCardName) async =>
      _apiProvider.updateDocument('Job Card', jobCardName, {});

  // ── Status transitions ────────────────────────────────────────────────

  Future<Response> updateJobCardStatus({
    required String jobCardId,
    required String erpNextStatus,
    required String startTime,
    String? completeTime,
    required List<Map<String, String>> employees,
  }) async {
    final Map<String, dynamic> argsMap = {
      'job_card_id': jobCardId,
      'start_time':  startTime,
      if (completeTime != null) 'complete_time': completeTime,
      'completed_qty': 0,
      'employees':   employees,
      'status':      erpNextStatus,
    };
    return _apiProvider.callMethodPost(
      'erpnext.manufacturing.doctype.job_card.job_card.make_time_log',
      params: {'args': json.encode(argsMap)},
    );
  }

  // ── Submission ─────────────────────────────────────────────────────────

  Future<Response> submitJobCard(String name) async =>
      _apiProvider.submitDocument('Job Card', name);
}
