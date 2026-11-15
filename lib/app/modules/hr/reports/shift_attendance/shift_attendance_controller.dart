import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_logic.dart';

/// Controller for the HRMS **Shift Attendance** script report.
///
/// Run server-side through `frappe.desk.query_report.run`; the app never
/// re-derives lateness or hours. Parsing lives in `shift_attendance_logic.dart`.
class ShiftAttendanceController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const String reportName = 'Shift Attendance';

  static const List<ReportPeriod> periods = [
    ReportPeriod.today,
    ReportPeriod.yesterday,
    ReportPeriod.last7Days,
    ReportPeriod.thisMonth,
    ReportPeriod.lastMonth,
  ];

  // ── Filter state ──────────────────────────────────────────────────────────

  final fromDateController = TextEditingController();
  final toDateController = TextEditingController();
  final companyController = TextEditingController();
  final employeeController = TextEditingController();
  final shiftController = TextEditingController();
  final departmentController = TextEditingController();

  /// Check filters: `'1'` on, empty off (see [ReportFilterToggle]).
  final lateEntryController = TextEditingController();
  final earlyExitController = TextEditingController();

  /// Desk defaults this on: lateness is measured from start + grace.
  final gracePeriodController = TextEditingController(text: '1');
  final withoutCheckinsController = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── Result state ──────────────────────────────────────────────────────────

  final isRunning = false.obs;
  final hasRun = false.obs;
  final errorMessage = RxnString();

  final rows = <ShiftAttendanceRow>[].obs;
  final summary = <ReportSummaryItem>[].obs;
  final activeFilters = <String, String>{}.obs;

  /// Mirrors the date controllers so the period bar repaints on change.
  final period = ''.obs;

  final scrollController = ScrollController();

  bool _rerunRequested = false;

  // ── Derived ───────────────────────────────────────────────────────────────

  String get fromDate => fromDateController.text.trim();
  String get toDate => toDateController.text.trim();

  String get periodText => periodLabel(fromDate, toDate);

  ReportPeriod? get selectedPeriod =>
      matchingPeriod(periods, fromDate, toDate, DateTime.now());

  ShiftAttendanceTotals get totals => ShiftAttendanceTotals.of(rows);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    companyController.text = Get.find<StorageService>().getCompany();
    _setPeriod(ReportPeriod.thisMonth);
    filterControllers = {
      'company': companyController,
      'from_date': fromDateController,
      'to_date': toDateController,
      'employee': employeeController,
      'shift': shiftController,
      'department': departmentController,
      'late_entry': lateEntryController,
      'early_exit': earlyExitController,
      'consider_grace_period': gracePeriodController,
      'include_attendance_without_checkins': withoutCheckinsController,
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
      key: 'from_date',
      label: 'From Date',
      type: ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
      required: true,
    ),
    ReportFilterField(
      key: 'to_date',
      label: 'To Date',
      type: ReportFilterType.datePicker,
      prefixIcon: Icons.event_outlined,
      required: true,
    ),
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
      key: 'shift',
      label: 'Shift Type',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.schedule_outlined,
      linkDoctype: 'Shift Type',
    ),
    ReportFilterField(
      key: 'department',
      label: 'Department',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.account_tree_outlined,
      linkDoctype: 'Department',
    ),
  ];

  Map<String, String> get filterSectionLabels => const {
    'from_date': 'Period',
    'company': 'Scope',
  };

  List<ReportFilterToggle> get filterToggles => const [
    ReportFilterToggle(
      key: 'late_entry',
      label: 'Late entry',
      icon: Icons.login,
    ),
    ReportFilterToggle(
      key: 'early_exit',
      label: 'Early exit',
      icon: Icons.logout,
    ),
    ReportFilterToggle(
      key: 'consider_grace_period',
      label: 'Consider grace period',
      icon: Icons.timer_outlined,
    ),
    ReportFilterToggle(
      key: 'include_attendance_without_checkins',
      label: 'Include records without check-ins',
      icon: Icons.person_off_outlined,
    ),
  ];

  // ── Actions ───────────────────────────────────────────────────────────────

  void applyPeriod(ReportPeriod preset) {
    _setPeriod(preset);
    runReport();
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    if (key == 'company') {
      companyController.text = Get.find<StorageService>().getCompany();
    }
    // Its chip reads "No grace period": removing it restores the default.
    if (key == 'consider_grace_period') gracePeriodController.text = '1';
    runReport();
  }

  void clearFilters() {
    employeeController.clear();
    shiftController.clear();
    departmentController.clear();
    lateEntryController.clear();
    earlyExitController.clear();
    withoutCheckinsController.clear();
    gracePeriodController.text = '1';
    companyController.text = Get.find<StorageService>().getCompany();
    runReport();
  }

  /// The exact `filters` payload the Desk sends for this report. Any key the
  /// server does not treat specially is an equality filter on Attendance, so
  /// optional filters are left out rather than sent blank.
  Map<String, dynamic> buildFilters() => {
    'company': companyController.text.trim(),
    'from_date': fromDate,
    'to_date': toDate,
    if (employeeController.text.trim().isNotEmpty)
      'employee': employeeController.text.trim(),
    if (shiftController.text.trim().isNotEmpty)
      'shift': shiftController.text.trim(),
    if (departmentController.text.trim().isNotEmpty)
      'department': departmentController.text.trim(),
    if (_on(lateEntryController)) 'late_entry': 1,
    if (_on(earlyExitController)) 'early_exit': 1,
    'consider_grace_period': _on(gracePeriodController) ? 1 : 0,
    'include_attendance_without_checkins': _on(withoutCheckinsController)
        ? 1
        : 0,
  };

  /// A message that stops the run before it reaches the server, or null.
  String? validate(Map<String, dynamic> filters) {
    if ((filters['company'] as String).isEmpty) {
      return 'Select a company to run the report.';
    }
    final from = DateTime.tryParse(filters['from_date'] as String);
    final to = DateTime.tryParse(filters['to_date'] as String);
    if (from == null || to == null) return 'Set a from and to date.';
    if (to.isBefore(from)) return 'From Date must be on or before To Date.';
    return null;
  }

  Future<void> runReport() async {
    if (isRunning.value) {
      // A filter change mid-run: run again with it once this one lands.
      _rerunRequested = true;
      return;
    }

    final filters = buildFilters();
    period.value = '$fromDate|$toDate';
    _rebuildActiveFilters();

    final invalid = validate(filters);
    if (invalid != null) {
      errorMessage.value = invalid;
      rows.clear();
      summary.clear();
      hasRun.value = true;
      return;
    }

    isRunning.value = true;
    try {
      final response = await _api.getReport(reportName, filters: filters);
      final message = response.data is Map ? response.data['message'] : null;
      rows.assignAll(
        parseShiftAttendance(message is Map ? message['result'] : null),
      );
      summary.assignAll(
        parseReportSummary(message is Map ? message['report_summary'] : null),
      );
      errorMessage.value = null;
    } catch (e) {
      rows.clear();
      summary.clear();
      errorMessage.value = readableReportError(e);
    } finally {
      hasRun.value = true;
      isRunning.value = false;
    }

    if (_rerunRequested) {
      _rerunRequested = false;
      await runReport();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _on(TextEditingController controller) =>
      controller.text.trim().isNotEmpty;

  void _setPeriod(ReportPeriod preset) {
    final (from, to) = preset.rangeFor(DateTime.now());
    fromDateController.text = kReportDate.format(from);
    toDateController.text = kReportDate.format(to);
    period.value = '$fromDate|$toDate';
  }

  static const _filterLabels = {
    'company': 'Company',
    'employee': 'Employee',
    'shift': 'Shift',
    'department': 'Dept',
  };

  /// The period bar owns the dates, so they are not chips. Grace period is
  /// a chip only when switched off — on is the default.
  void _rebuildActiveFilters() {
    activeFilters.clear();
    _filterLabels.forEach((key, label) {
      final value = filterControllers[key]?.text.trim() ?? '';
      if (value.isNotEmpty) activeFilters[key] = '$label: $value';
    });
    if (_on(lateEntryController)) activeFilters['late_entry'] = 'Late entry';
    if (_on(earlyExitController)) activeFilters['early_exit'] = 'Early exit';
    if (!_on(gracePeriodController)) {
      activeFilters['consider_grace_period'] = 'No grace period';
    }
    if (_on(withoutCheckinsController)) {
      activeFilters['include_attendance_without_checkins'] =
          'Incl. without check-ins';
    }
  }
}
