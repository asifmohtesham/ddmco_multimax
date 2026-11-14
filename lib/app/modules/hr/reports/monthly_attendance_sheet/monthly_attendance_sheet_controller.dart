import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_logic.dart';

/// Controller for the HRMS **Monthly Attendance Sheet** script report.
///
/// The report is run server-side through `frappe.desk.query_report.run`; the
/// app never re-derives attendance status. Parsing lives in
/// `monthly_attendance_sheet_logic.dart` so it unit-tests without GetX.
class MonthlyAttendanceSheetController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const String reportName = 'Monthly Attendance Sheet';

  static const String modeMonth = 'Month';
  static const String modeDateRange = 'Date Range';

  // ── Filter state ──────────────────────────────────────────────────────────

  /// `filter_based_on`: the month stepper drives the report in [modeMonth];
  /// [modeDateRange] hands over to the two date fields in the sheet.
  final filterBasedOn = modeMonth.obs;

  /// First of the selected month, for [modeMonth].
  final month = DateTime(DateTime.now().year, DateTime.now().month).obs;

  final startDateController = TextEditingController();
  final endDateController = TextEditingController();
  final companyController = TextEditingController();
  final employeeController = TextEditingController();
  final departmentController = TextEditingController();
  final branchController = TextEditingController();

  /// Chip-group controllers — empty string means "not set" (see
  /// [ReportFilterChipGroup]).
  final filterBasedOnController = TextEditingController(text: modeMonth);
  final groupByController = TextEditingController();
  final summarizedController = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── Result state ──────────────────────────────────────────────────────────

  final isRunning = false.obs;
  final hasRun = false.obs;
  final errorMessage = RxnString();

  /// Detailed view.
  final days = <SheetDay>[].obs;
  final employees = <SheetEmployee>[].obs;

  /// Summarized view.
  final summaries = <SheetSummary>[].obs;
  final leaveTypes = <SheetSummaryColumn>[].obs;

  /// Employees whose per-shift calendars are open.
  final expanded = <String>{}.obs;

  final activeFilters = <String, String>{}.obs;

  final scrollController = ScrollController();

  // ── Derived ───────────────────────────────────────────────────────────────

  bool get isMonthMode => filterBasedOn.value == modeMonth;

  bool get isSummarized => summarizedController.text.trim().isNotEmpty;

  String get groupBy => groupByController.text.trim();

  /// `frappe.scrub(group_by)` — the fieldname the marker rows are keyed by.
  String? get groupByField =>
      groupBy.isEmpty ? null : groupBy.toLowerCase().replaceAll(' ', '_');

  bool get isEmpty => isSummarized ? summaries.isEmpty : employees.isEmpty;

  String get periodLabel => isMonthMode
      ? DateFormat('MMMM yyyy').format(month.value)
      : '${startDateController.text} → ${endDateController.text}';

  /// Next month is only reachable up to the current one — the report has
  /// nothing to say about a month that has not started.
  bool get isCurrentMonth =>
      month.value.year == DateTime.now().year &&
      month.value.month == DateTime.now().month;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    companyController.text = Get.find<StorageService>().getCompany();
    final now = DateTime.now();
    startDateController.text = _fmt(DateTime(now.year, now.month));
    endDateController.text = _fmt(now);
    filterControllers = {
      'filter_based_on': filterBasedOnController,
      'start_date': startDateController,
      'end_date': endDateController,
      'company': companyController,
      'employee': employeeController,
      'department': departmentController,
      'branch': branchController,
      'group_by': groupByController,
      'summarized_view': summarizedController,
    };
    _rebuildActiveFilters();
  }

  @override
  void onReady() {
    super.onReady();
    runReport();
  }

  @override
  void onClose() {
    for (final controller in filterControllers.values) {
      controller.dispose();
    }
    scrollController.dispose();
    super.onClose();
  }

  // ── Filter descriptors ────────────────────────────────────────────────────

  List<ReportFilterField> get filterFields => const [
        ReportFilterField(
          key: 'company',
          label: 'Company',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.business_outlined,
          linkDoctype: 'Company',
          required: true,
        ),
        ReportFilterField(
          key: 'employee',
          label: 'Employee',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.badge_outlined,
          linkDoctype: 'Employee',
        ),
        ReportFilterField(
          key: 'department',
          label: 'Department',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.account_tree_outlined,
          linkDoctype: 'Department',
        ),
        ReportFilterField(
          key: 'branch',
          label: 'Branch',
          type: ReportFilterType.doctypeLink,
          prefixIcon: Icons.location_city_outlined,
          linkDoctype: 'Branch',
        ),
        ReportFilterField(
          key: 'start_date',
          label: 'Start Date',
          type: ReportFilterType.datePicker,
          prefixIcon: Icons.calendar_today_outlined,
        ),
        ReportFilterField(
          key: 'end_date',
          label: 'End Date',
          type: ReportFilterType.datePicker,
          prefixIcon: Icons.event_outlined,
        ),
      ];

  Map<String, String> get filterSectionLabels => const {
        'company': 'Scope',
        'start_date': 'Date range (used when Period is "Date Range")',
      };

  List<ReportFilterChipGroup> get filterChipGroups => const [
        ReportFilterChipGroup(
          key: 'filter_based_on',
          label: 'Period',
          options: [
            ReportFilterChipOption(
                value: modeMonth, label: 'Month', icon: Icons.calendar_month),
            ReportFilterChipOption(
                value: modeDateRange,
                label: 'Date Range',
                icon: Icons.date_range),
          ],
        ),
        ReportFilterChipGroup(
          key: 'group_by',
          label: 'Group By',
          options: [
            ReportFilterChipOption(value: 'Branch', label: 'Branch'),
            ReportFilterChipOption(value: 'Grade', label: 'Grade'),
            ReportFilterChipOption(value: 'Department', label: 'Department'),
            ReportFilterChipOption(value: 'Designation', label: 'Designation'),
          ],
        ),
        ReportFilterChipGroup(
          key: 'summarized_view',
          label: 'View',
          options: [
            ReportFilterChipOption(
                value: '1', label: 'Summarized', icon: Icons.functions),
          ],
        ),
      ];

  // ── Actions ───────────────────────────────────────────────────────────────

  void previousMonth() {
    month.value = DateTime(month.value.year, month.value.month - 1);
    runReport();
  }

  void nextMonth() {
    if (isCurrentMonth) return;
    month.value = DateTime(month.value.year, month.value.month + 1);
    runReport();
  }

  void toggleExpanded(String employee) {
    if (expanded.contains(employee)) {
      expanded.remove(employee);
    } else {
      expanded.add(employee);
    }
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    if (key == 'company') {
      companyController.text = Get.find<StorageService>().getCompany();
    }
    if (key == 'filter_based_on') filterBasedOnController.text = modeMonth;
    _syncMode();
    runReport();
  }

  void clearFilters() {
    employeeController.clear();
    departmentController.clear();
    branchController.clear();
    groupByController.clear();
    summarizedController.clear();
    filterBasedOnController.text = modeMonth;
    companyController.text = Get.find<StorageService>().getCompany();
    _syncMode();
    runReport();
  }

  /// The exact `filters` payload the Desk sends for this report.
  Map<String, dynamic> buildFilters() {
    _syncMode();
    return {
      'filter_based_on': filterBasedOn.value,
      if (isMonthMode) ...{
        'month': month.value.month.toString(),
        'year': month.value.year.toString(),
      } else ...{
        'start_date': startDateController.text.trim(),
        'end_date': endDateController.text.trim(),
      },
      'company': companyController.text.trim(),
      // ponytail: single-company site — descendants pinned on rather than
      // spent as a filter row. Expose it if a second company is ever added.
      'include_company_descendants': 1,
      if (employeeController.text.trim().isNotEmpty)
        'employee': employeeController.text.trim(),
      if (departmentController.text.trim().isNotEmpty)
        'department': departmentController.text.trim(),
      if (branchController.text.trim().isNotEmpty)
        'branch': branchController.text.trim(),
      if (groupBy.isNotEmpty) 'group_by': groupBy,
      'summarized_view': isSummarized ? 1 : 0,
    };
  }

  Future<void> runReport() async {
    if (isRunning.value) return;

    final filters = buildFilters();
    if ((filters['company'] as String).isEmpty) {
      errorMessage.value = 'Select a company to run the report.';
      hasRun.value = true;
      _clearResults();
      return;
    }
    if (!isMonthMode &&
        ((filters['start_date'] as String).isEmpty ||
            (filters['end_date'] as String).isEmpty)) {
      errorMessage.value = 'Set a start and end date, or switch Period to Month.';
      hasRun.value = true;
      _clearResults();
      return;
    }

    isRunning.value = true;
    _rebuildActiveFilters();
    try {
      final response = await _api.getReport(reportName, filters: filters);
      final message = response.data is Map ? response.data['message'] : null;
      final columns = message is Map ? message['columns'] : null;
      final result = message is Map ? message['result'] : null;

      if (isSummarized) {
        leaveTypes.assignAll(parseLeaveTypeColumns(columns));
        summaries.assignAll(parseSummarized(result, groupByField: groupByField));
        days.clear();
        employees.clear();
      } else {
        days.assignAll(parseDayColumns(columns));
        employees.assignAll(parseDetailed(result, groupByField: groupByField));
        summaries.clear();
        leaveTypes.clear();
      }
      expanded.clear();
      errorMessage.value = null;
    } catch (e) {
      _clearResults();
      errorMessage.value = _readableError(e);
    } finally {
      hasRun.value = true;
      isRunning.value = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _clearResults() {
    days.clear();
    employees.clear();
    summaries.clear();
    leaveTypes.clear();
    expanded.clear();
  }

  /// Mirrors the chip controller into the observable the UI switches on.
  void _syncMode() {
    final chosen = filterBasedOnController.text.trim();
    filterBasedOn.value = chosen.isEmpty ? modeMonth : chosen;
  }

  static const _filterLabels = {
    'company': 'Company',
    'employee': 'Employee',
    'department': 'Dept',
    'branch': 'Branch',
    'group_by': 'Group by',
  };

  /// The period bar owns the month/range, so it is deliberately not a chip.
  void _rebuildActiveFilters() {
    activeFilters.clear();
    _filterLabels.forEach((key, label) {
      final value = filterControllers[key]?.text.trim() ?? '';
      if (value.isNotEmpty) activeFilters[key] = '$label: $value';
    });
    if (isSummarized) activeFilters['summarized_view'] = 'Summarized';
  }

  /// Frappe puts the useful part of a script-report failure in the response
  /// body, not the status line.
  String _readableError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final messages = data['_server_messages'];
        if (messages is String && messages.isNotEmpty) {
          // A JSON array of JSON strings; the human text is the last one.
          final text = messages
              .replaceAll(RegExp(r'[\[\]\\"]'), '')
              .replaceAll(RegExp(r'\{.*?:\s*'), '')
              .replaceAll('}', '')
              .trim();
          if (text.isNotEmpty) return text;
        }
        final exception = data['exception']?.toString();
        if (exception != null && exception.isNotEmpty) return exception;
      }
      return error.message ?? 'Could not run the report.';
    }
    return error.toString();
  }

  String _fmt(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
}
