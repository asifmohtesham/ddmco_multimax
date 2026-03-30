import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class JobCardProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  /// Fetch the Job Card list for list-view screens.
  ///
  /// Returns lightweight fields only — no child tables.
  /// Use [getJobCard] when the full document (including time logs) is needed.
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
        'docstatus',
        'modified',
        'posting_date',
      ],
      orderBy: 'modified desc',
    );
  }

  // ── Single document ────────────────────────────────────────────────────────

  /// Fetch the full Job Card document including the `time_logs` child table.
  Future<Response> getJobCard(String name) async =>
      _apiProvider.getDocument('Job Card', name);

  // ── Time log entry ────────────────────────────────────────────────────────

  /// Add a manual time log entry to a Job Card.
  ///
  /// Calls `make_time_log` via form-urlencoded POST with `args` as a
  /// JSON-encoded string. Sending `args` as a nested Map over GET causes:
  ///   TypeError: make_time_log() missing 1 required positional argument: 'args'
  ///
  /// [status] values accepted by ERPNext:
  ///   `'Work In Progress'` — start / resume a live timer session
  ///   `'Resume Job'`       — pause a running timer
  ///   `'Complete'`         — close the session (requires [completeTime])
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

  // ── Status transitions ────────────────────────────────────────────────────

  /// Transition the Job Card status via `make_time_log`.
  ///
  /// ERPNext ignores a plain REST PATCH/PUT to the `status` field because
  /// that field is controlled exclusively by server-side hooks. The only
  /// supported way to change status programmatically is through
  /// `make_time_log` with the appropriate status string:
  ///
  ///   `'Work In Progress'` — Start (Open → WIP)
  ///   `'Resume Job'`       — Pause (WIP → Open)
  ///   `'Complete'`         — Complete (WIP → Completed)
  ///
  /// For Start and Pause, [startTime] is the current time and
  /// [completeTime] is omitted. For Complete, both times are supplied
  /// so ERPNext can compute `time_in_mins` correctly.
  ///
  /// [employees] is automatically forwarded from the session employee so
  /// the time-log row created by the server carries the correct employee.
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

  // ── Document submission ───────────────────────────────────────────────────

  /// Submit a Job Card document (docstatus 0 → 1).
  Future<Response> submitJobCard(String name) async =>
      _apiProvider.submitDocument('Job Card', name);
}
