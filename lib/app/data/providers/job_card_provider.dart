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
        'operation_id',
      ],
      orderBy: 'modified desc',
    );
  }

  // ── Single document ────────────────────────────────────────────────────────────

  /// Fetch the full Job Card document including the `time_logs` child table.
  ///
  /// The response is deserialised by [JobCard.fromJson] in the controller.
  /// Child table rows (`time_logs`) are included automatically by
  /// ERPNext's `GET /api/resource/Job Card/{name}` endpoint.
  Future<Response> getJobCard(String name) async =>
      _apiProvider.getDocument('Job Card', name);

  // ── Time log entry ───────────────────────────────────────────────────────────

  /// Add a time log entry to a Job Card.
  ///
  /// Calls the whitelisted server method:
  ///   `erpnext.manufacturing.doctype.job_card.job_card.make_time_log`
  ///
  /// **Manual entry (primary mode)**
  ///   Pass both [startTime] and [completeTime] as ISO 8601 datetime strings.
  ///   The server computes `time_in_mins` from the difference.
  ///
  /// **Live timer (secondary mode)**
  ///   `startTime` is recorded when the timer starts (via [addTimeLog] with
  ///   `status: "Work In Progress"`). When the timer stops the controller
  ///   calls [addTimeLog] again with both times and `status: "Complete"`.
  ///
  /// [jobCardId]    — Job Card document name.
  /// [startTime]    — Session start datetime (ISO 8601).
  /// [completeTime] — Session end datetime (ISO 8601). Null when only
  ///                   starting a live-timer session.
  /// [completedQty] — Finished-good qty completed in this session.
  /// [employees]    — List of employee maps: `[{"employee": "HR-EMP-00001"}]`.
  ///                   Pass an empty list when no employee is assigned.
  /// [status]       — `"Work In Progress"` | `"Complete"` | `"Resume Job"`.
  Future<Response> addTimeLog({
    required String jobCardId,
    required String startTime,
    String? completeTime,
    required double completedQty,
    required List<Map<String, String>> employees,
    required String status,
  }) async =>
      _apiProvider.callMethod(
        'erpnext.manufacturing.doctype.job_card.job_card.make_time_log',
        params: {
                'args': {
          'job_card_id':   jobCardId,
          'start_time':    startTime,
          if (completeTime != null) 'complete_time': completeTime,
          'completed_qty': completedQty,
          'employees':     employees,
          'status':        status,
                        },
        },
      );

  // ── Status update ─────────────────────────────────────────────────────────────

  /// Update the status field of a Job Card via PATCH.
  ///
  /// Used by the controller to transition the card between:
  ///   `Open` → `Work In Progress` → `Completed`
  ///
  /// Note: final submission (docstatus 0 → 1) is a separate operation
  /// performed via [submitJobCard] if needed in a future step.
  Future<Response> updateJobCardStatus(
    String name,
    String status,
  ) async =>
      _apiProvider.updateDocument('Job Card', name, {'status': status});

    // ── Document submission ─────────────────────────────────────────────────────

  /// Submit a Job Card document (change docstatus from 0 to 1).
  ///
  /// ERPNext requires submission to finalize a document and prevent further edits.
  /// This is typically done after all time logs are recorded and the Job Card
  /// status is set to "Completed".
  ///
  /// [name] — Job Card document name.
  Future<Response> submitJobCard(String name) async =>
      _apiProvider.submitDocument('Job Card', name);
}
