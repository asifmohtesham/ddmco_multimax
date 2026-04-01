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
    Map<String, dynamic>? orFilters,
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
