import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/link_title_cache.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_logic.dart';

/// Controller for the HRMS **Employee Hours Utilization Based On Timesheet**
/// script report, run server-side through `frappe.desk.query_report.run`.
class EmployeeHoursUtilizationController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  static const String reportName =
      'Employee Hours Utilization Based On Timesheet';

  /// Single-day presets are left out: the report needs From strictly before
  /// To, and measures the span without the end day.
  static const List<ReportPeriod> periods = [
    ReportPeriod.last7Days,
    ReportPeriod.thisMonth,
    ReportPeriod.lastMonth,
    ReportPeriod.last30Days,
  ];

  // ── Filter state ──────────────────────────────────────────────────────────

  final fromDateController = TextEditingController();
  final toDateController = TextEditingController();
  final companyController = TextEditingController();
  final employeeController = TextEditingController();
  final departmentController = TextEditingController();
  final projectController = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── Result state ──────────────────────────────────────────────────────────

  final isRunning = false.obs;
  final hasRun = false.obs;
  final errorMessage = RxnString();

  final rows = <EmployeeUtilizationRow>[].obs;
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

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    companyController.text = Get.find<StorageService>().getCompany();
    _setPeriod(ReportPeriod.last30Days);
    filterControllers = {
      'company': companyController,
      'from_date': fromDateController,
      'to_date': toDateController,
      'employee': employeeController,
      'department': departmentController,
      'project': projectController,
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
      linkTitleField: 'employee_name',
    ),
    ReportFilterField(
      key: 'department',
      label: 'Department',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.account_tree_outlined,
      linkDoctype: 'Department',
    ),
    ReportFilterField(
      key: 'project',
      label: 'Project',
      type: ReportFilterType.doctypeLink,
      prefixIcon: Icons.work_outline,
      linkDoctype: 'Project',
    ),
  ];

  Map<String, String> get filterSectionLabels => const {
    'from_date': 'Period',
    'company': 'Scope',
  };

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
    runReport();
  }

  void clearFilters() {
    employeeController.clear();
    departmentController.clear();
    projectController.clear();
    companyController.text = Get.find<StorageService>().getCompany();
    runReport();
  }

  /// The exact `filters` payload the Desk sends for this report.
  Map<String, dynamic> buildFilters() => {
    'company': companyController.text.trim(),
    'from_date': fromDate,
    'to_date': toDate,
    if (employeeController.text.trim().isNotEmpty)
      'employee': employeeController.text.trim(),
    if (departmentController.text.trim().isNotEmpty)
      'department': departmentController.text.trim(),
    if (projectController.text.trim().isNotEmpty)
      'project': projectController.text.trim(),
  };

  /// A message that stops the run before it reaches the server, or null.
  String? validate(Map<String, dynamic> filters) {
    if ((filters['company'] as String).isEmpty) {
      return 'Select a company to run the report.';
    }
    final from = DateTime.tryParse(filters['from_date'] as String);
    final to = DateTime.tryParse(filters['to_date'] as String);
    if (from == null || to == null) return 'Set a from and to date.';
    if (!from.isBefore(to)) {
      return 'From Date must come before To Date — the report measures '
          'whole days between them.';
    }
    return null;
  }

  Future<void> runReport() async {
    if (isRunning.value) {
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
        parseUtilization(message is Map ? message['result'] : null),
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

  void _setPeriod(ReportPeriod preset) {
    final (from, to) = preset.rangeFor(DateTime.now());
    fromDateController.text = kReportDate.format(from);
    toDateController.text = kReportDate.format(to);
    period.value = '$fromDate|$toDate';
  }

  static const _filterLabels = {
    'company': 'Company',
    'employee': 'Employee',
    'department': 'Dept',
    'project': 'Project',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    _resolveEmployeeTitle();
    _filterLabels.forEach((key, label) {
      final value = filterControllers[key]?.text.trim() ?? '';
      if (value.isEmpty) return;
      activeFilters[key] = key == 'employee'
          ? '$label: ${linkChipValue('Employee', value)}'
          : '$label: $value';
    });
  }

  /// An employee set without the picker (e.g. kept from an earlier run) has
  /// no remembered name yet: look it up once, then relabel the chip.
  void _resolveEmployeeTitle() {
    final id = employeeController.text.trim();
    if (id.isEmpty || LinkTitleCache.peek('Employee', id) != null) return;
    LinkTitleCache.resolve('Employee', 'employee_name', id, _api).then((title) {
      if (title == null || isClosed) return;
      if (employeeController.text.trim() == id) {
        activeFilters['employee'] = 'Employee: $title';
      }
    });
  }
}
