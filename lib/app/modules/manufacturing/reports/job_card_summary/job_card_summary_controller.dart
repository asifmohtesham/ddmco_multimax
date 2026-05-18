import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class JobCardSummaryController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter controllers ────────────────────────────────────────────────────
  final fromDateController      = TextEditingController();
  final toDateController        = TextEditingController();
  final workOrderController     = TextEditingController();
  final productionItemController = TextEditingController();
  final workstationController = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── State ─────────────────────────────────────────────────────────────────
  final isLoading     = false.obs;
  final reportData    = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;

  final RxList<WorkOrder> recentWorkOrders = <WorkOrder>[].obs;
  final RxBool isLoadingWorkOrders = false.obs;

  final WorkOrderProvider _workOrderProvider = Get.find<WorkOrderProvider>();

  // ── Filter field descriptors (passed to ReportFilterSheet) ────────────────
  List<ReportFilterField> get filterFields => [
    const ReportFilterField(
      key:        'from_date',
      label:      'From Date',
      type:       ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
      required:   true,
    ),
    const ReportFilterField(
      key:        'to_date',
      label:      'To Date',
      type:       ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
      required:   true,
    ),
    const ReportFilterField(
      key:        'work_order',
      label:      'Work Order',
      type:       ReportFilterType.doctypeLink,
      prefixIcon: Icons.precision_manufacturing_outlined,
      linkDoctype: 'Work Order',
    ),
    const ReportFilterField(
      key:         'production_item',
      label:       'Production Item',
      type:        ReportFilterType.doctypeLink,
      prefixIcon:  Icons.category_outlined,
      linkDoctype: 'Item',
    ),
    const ReportFilterField(
      key:         'workstation',
      label:       'Workstation',
      type:        ReportFilterType.doctypeLink,
      prefixIcon:  Icons.category_outlined,
      linkDoctype: 'Workstation',
    ),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    _loadRecentWorkOrders();
    filterControllers = {
      'from_date'       : fromDateController,
      'to_date'         : toDateController,
      'work_order'      : workOrderController,
      'production_item' : productionItemController,
      'workstation'     : workstationController,
    };
    // Pre-fill: today → today (auto-run on load shows today's cards by default)
    final now = DateTime.now();
    fromDateController.text = _fmt(now);
    toDateController.text   = _fmt(now);
    _rebuildActiveFilters();
  }

  @override
  void onReady() {
    super.onReady();
    runReport(); // Auto-run with today's default date range
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) c.dispose();
    super.onClose();
  }

  Future<void> _loadRecentWorkOrders() async {
    isLoadingWorkOrders.value = true;
    try {
      final list = await _workOrderProvider.fetchRecent(limit: 20);
      recentWorkOrders.assignAll(list);
    } finally {
      isLoadingWorkOrders.value = false;
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────
  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilters() {
    workOrderController.clear();
    productionItemController.clear();
    workstationController.clear();
    final now  = DateTime.now();
    fromDateController.text = _fmt(now);
    toDateController.text   = _fmt(now);
    _rebuildActiveFilters();
    reportData.clear();
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
  }

  Future<void> runReport() async {
    final from = fromDateController.text.trim();
    final to   = toDateController.text.trim();

    if (from.isEmpty || to.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Dates Required',
        message: 'Please set From Date and To Date to run the report.',
      );
      return;
    }

    _rebuildActiveFilters();
    isLoading.value = true;
    reportData.clear();

    try {
      final response = await _api.getJobCardSummary(
        fromDate:       from,
        toDate:         to,
        workOrder:      workOrderController.text.trim(),
        productionItem: productionItemController.text.trim(),
        workstation:    workstationController.text.trim(),
      );

      if (response.statusCode == 200) {
        final message = response.data['message'] as Map<String, dynamic>?;
        if (message != null) {
          final rawRows = message['result'] as List<dynamic>? ?? [];
          // The last row is an ERPNext totals array — filter it out
          reportData.assignAll(
            rawRows.whereType<Map<String, dynamic>>().toList(),
          );
        }
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to load Job Card Summary: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static const _filterLabels = {
    'from_date'       : 'From',
    'to_date'         : 'To',
    'work_order'      : 'WO',
    'production_item' : 'Item',
    'workstation'     : 'Workstation',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) activeFilters[key] = '${_filterLabels[key] ?? key}: $v';
    });
  }

  String _fmt(DateTime d) =>
      DateFormat('yyyy-MM-dd').format(d);

  // ── Chart data ─────────────────────────────────────────────────────────────
  // Groups reportData rows by posting_date, summing total_completed_qty per day.
  // `for_quantity` is not in the summary API response, so planned = completed
  // (single bar per day showing throughput). Sorted ascending by date.
  List<DailyProduction> get dailyProductionData {
    final map = <String, double>{};
    for (final row in reportData) {
      final date = row['posting_date']?.toString() ?? '';
      if (date.isEmpty) continue;
      final qty = (row['total_completed_qty'] as num?)?.toDouble() ?? 0.0;
      map[date] = (map[date] ?? 0.0) + qty;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => DailyProduction(date: e.key, completed: e.value))
        .toList();
  }
}

// ── Value object ──────────────────────────────────────────────────────────────
class DailyProduction {
  final String date;       // 'YYYY-MM-DD'
  final double completed;  // total_completed_qty summed for the day
  const DailyProduction({required this.date, required this.completed});
}
