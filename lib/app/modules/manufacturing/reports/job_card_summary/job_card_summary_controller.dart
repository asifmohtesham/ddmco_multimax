import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/utils/report_error.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'job_card_summary_fields.dart';

class JobCardSummaryController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter controllers ────────────────────────────────────────────────────
  final fromDateController = TextEditingController();
  final toDateController = TextEditingController();
  final workOrderController = TextEditingController();
  final productionItemController = TextEditingController();
  final workstationController = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── State ─────────────────────────────────────────────────────────────────
  final isLoading = false.obs;
  final reportData = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;
  final hasResult = false.obs;
  final errorMessage = RxnString();
  final resultRevision = 0.obs;
  final scrollController = ScrollController();
  final fields = ScopedReportFieldsController.forReport(jobCardSummaryFields);
  List<DeskColumn> reportColumns = const [];
  late final Worker _fieldsOwnerWorker;
  var _requestId = 0;

  final RxList<WorkOrder> recentWorkOrders = <WorkOrder>[].obs;
  final RxBool isLoadingWorkOrders = false.obs;

  final WorkOrderProvider _workOrderProvider = Get.find<WorkOrderProvider>();

  // ── Filter field descriptors (passed to ReportFilterSheet) ────────────────
  List<ReportFilterField> get filterFields => [
    const ReportFilterField(
      key: 'from_date',
      label: 'From Date',
      type: ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
      required: true,
    ),
    const ReportFilterField(
      key: 'to_date',
      label: 'To Date',
      type: ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
      required: true,
    ),
    const ReportFilterField(
      key: 'work_order',
      label: 'Work Order',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.precision_manufacturing_outlined,
      linkDoctype: 'Work Order',
    ),
    const ReportFilterField(
      key: 'production_item',
      label: 'Production Item',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.category_outlined,
      linkDoctype: 'Item',
    ),
    const ReportFilterField(
      key: 'workstation',
      label: 'Workstation',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.category_outlined,
      linkDoctype: 'Workstation',
    ),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    filterControllers = {
      'from_date': fromDateController,
      'to_date': toDateController,
      'work_order': workOrderController,
      'production_item': productionItemController,
      'workstation': workstationController,
    };
    // Pre-fill: today → today (auto-run on load shows today's cards by default)
    final now = DateTime.now();
    fromDateController.text = _fmt(now);
    toDateController.text = _fmt(now);
    _rebuildActiveFilters();
    var owner = fields.ownerGeneration;
    _fieldsOwnerWorker = ever(fields.state, (_) {
      if (owner == fields.ownerGeneration) return;
      owner = fields.ownerGeneration;
      reportColumns = const [];
      clearFilters();
      recentWorkOrders.clear();
      isLoadingWorkOrders.value = false;
      isLoading.value = false;
    });
    fields.bind();
    _loadRecentWorkOrders();
  }

  @override
  void onReady() {
    super.onReady();
    runReport(); // Auto-run with today's default date range
  }

  @override
  void onClose() {
    _fieldsOwnerWorker.dispose();
    fields.dispose();
    scrollController.dispose();
    for (final c in filterControllers.values) c.dispose();
    super.onClose();
  }

  Future<void> _loadRecentWorkOrders() async {
    isLoadingWorkOrders.value = true;
    final owner = fields.ownerGeneration;
    try {
      final list = await _workOrderProvider.fetchRecent(limit: 20);
      if (!isClosed && owner == fields.ownerGeneration) {
        recentWorkOrders.assignAll(list);
      }
    } finally {
      if (!isClosed && owner == fields.ownerGeneration) {
        isLoadingWorkOrders.value = false;
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────
  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilters() {
    workOrderController.clear();
    productionItemController.clear();
    workstationController.clear();
    final now = DateTime.now();
    fromDateController.text = _fmt(now);
    toDateController.text = _fmt(now);
    _rebuildActiveFilters();
    reportData.clear();
    hasResult.value = false;
    errorMessage.value = null;
    resultRevision.value++;
    _requestId++;
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    if (key == 'from_date') {
      filterControllers[key]!.text = _fmt(DateTime.now());
    }
    if (key == 'to_date') {
      filterControllers[key]!.text = _fmt(DateTime.now());
    }
    _rebuildActiveFilters();
    resultRevision.value++;
  }

  Future<void> runReport() async {
    if (isLoading.value) return;
    final from = fromDateController.text.trim();
    final to = toDateController.text.trim();

    if (from.isEmpty || to.isEmpty) {
      GlobalSnackbar.warning(
        title: 'Dates Required',
        message: 'Please set From Date and To Date to run the report.',
      );
      return;
    }

    _rebuildActiveFilters();
    final owner = fields.ownerGeneration;
    final request = ++_requestId;
    resultRevision.value++;
    isLoading.value = true;
    hasResult.value = false;
    errorMessage.value = null;
    reportData.clear();

    try {
      final response = await _api.getJobCardSummary(
        fromDate: from,
        toDate: to,
        workOrder: workOrderController.text.trim(),
        productionItem: productionItemController.text.trim(),
        workstation: workstationController.text.trim(),
      );

      if (isClosed ||
          owner != fields.ownerGeneration ||
          request != _requestId) {
        return;
      }
      final message = response.data is Map ? response.data['message'] : null;
      if (response.statusCode != 200 || message is! Map) {
        throw StateError('Missing report response');
      }
      final rawRows = message['result'];
      if (_reportFlag(message['prepared_report'])) {
        final doc = message['doc'];
        if (doc is Map && doc['status'] == 'Error') {
          final serverError = message['error'];
          _showReportError(
            serverError is String && serverError.trim().isNotEmpty
                ? serverError.trim()
                : 'The prepared Job Card Summary failed. Try again.',
          );
          return;
        }
        if (rawRows is! List) {
          _showReportError(
            'The prepared Job Card Summary is not available yet. Try again.',
          );
          return;
        }
      }
      if (rawRows is! List) {
        throw StateError('Missing Job Card Summary result list');
      }
      final rawColumns = message['columns'];
      reportColumns = decodeDeskColumns(rawColumns);
      fields.replaceDefinition(
        jobCardSummaryFields.withColumns(
          rawColumns is List ? reportColumns : null,
          aliases: jobCardSummaryFieldsAliases,
        ),
      );
      reportData.assignAll(
        parseRows(
          rawRows,
          reportColumns,
          hasTotalRow: _reportFlag(message['add_total_row']),
        ),
      );
      hasResult.value = true;
    } catch (e) {
      if (isClosed ||
          owner != fields.ownerGeneration ||
          request != _requestId) {
        return;
      }
      _showReportError(readableReportError(e, reportName: 'Job Card Summary'));
    } finally {
      if (!isClosed && owner == fields.ownerGeneration) {
        isLoading.value = false;
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showReportError(String error) {
    errorMessage.value = error;
    GlobalSnackbar.error(title: 'Report Error', message: error);
  }

  static bool _reportFlag(Object? value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  static List<Map<String, dynamic>> parseRows(
    List<Object?> result,
    List<DeskColumn> columns, {
    required bool hasTotalRow,
  }) {
    final rows = <Map<String, dynamic>>[];
    for (final (index, raw) in result.indexed) {
      // Frappe appends a positional row with a localized first cell and only
      // aggregate values after it. Actual Job Cards can have that same ID.
      if (hasTotalRow &&
          result.length > 1 &&
          index == result.length - 1 &&
          raw is List &&
          raw.length == columns.length &&
          raw.isNotEmpty &&
          raw
              .skip(1)
              .every((cell) => cell == null || cell == '' || cell is num)) {
        continue;
      }
      final row = decodeDeskRow(raw, columns);
      if (row == null || row.isEmpty) continue;
      if (!row.containsKey('name') && row.containsKey('id')) {
        row['name'] = row['id'];
      }
      if (!row.containsKey('total_time_in_mins') &&
          row.containsKey('time_required_(in_mins)')) {
        row['total_time_in_mins'] = row['time_required_(in_mins)'];
      }
      rows.add(row);
    }
    return rows;
  }

  static num? measure(Object? value) {
    final number = value is num ? value : num.tryParse(value?.toString() ?? '');
    return number?.isFinite == true ? number : null;
  }

  num get totalCompletedQty => reportData.fold<num>(
    0,
    (sum, row) => sum + (measure(row['total_completed_qty']) ?? 0),
  );

  static const _filterLabels = {
    'from_date': 'From',
    'to_date': 'To',
    'work_order': 'WO',
    'production_item': 'Item',
    'workstation': 'Workstation',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) activeFilters[key] = '${_filterLabels[key] ?? key}: $v';
    });
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ── Chart data ─────────────────────────────────────────────────────────────
  // Groups reportData rows by posting_date, summing total_completed_qty per day.
  // `for_quantity` is not in the summary API response, so planned = completed
  // (single bar per day showing throughput). Sorted ascending by date.
  List<DailyProduction> get dailyProductionData {
    final map = <String, double>{};
    for (final row in reportData) {
      final date = row['posting_date']?.toString() ?? '';
      if (date.isEmpty) continue;
      final qty = measure(row['total_completed_qty'])?.toDouble() ?? 0.0;
      map[date] = (map[date] ?? 0.0) + qty;
    }
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => DailyProduction(date: e.key, completed: e.value))
        .toList();
  }
}

// ── Value object ──────────────────────────────────────────────────────────────
class DailyProduction {
  final String date; // 'YYYY-MM-DD'
  final double completed; // total_completed_qty summed for the day
  const DailyProduction({required this.date, required this.completed});
}
