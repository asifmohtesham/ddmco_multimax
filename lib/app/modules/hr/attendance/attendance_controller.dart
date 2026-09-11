import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

/// Drives the Attendance list for one selected day.
///
/// Master data (employees, shift rules, holidays) loads once; the day's
/// punches and ledger rows reload on date change, pull-to-refresh, the refresh
/// icon, and a 60-second poll while today is selected.
class AttendanceController extends GetxController {
  final AttendanceProvider _provider = Get.find<AttendanceProvider>();

  // ── State ─────────────────────────────────────────────────────────────────
  final isLoading = true.obs; // first load of the selected day
  final isRefreshing = false.obs; // silent / icon refresh
  final selectedDate = dateOnly(DateTime.now()).obs;
  final employees = <TrackedEmployee>[].obs;
  final checkins = <EmployeeCheckin>[].obs;
  final ledger = <AttendanceRecord>[].obs;
  /// The shift in focus (in progress, else the day's first): banner copy and
  /// the detail sheet on a single-shift day.
  final shift = Rx<ShiftRules>(ShiftRules.fallback);

  /// Shift Types by name, read as assignments and ledger rows name them.
  final catalog = <String, ShiftRules>{}.obs;

  /// Shift Assignments covering the selected day (two per employee on a
  /// Morning/Afternoon day).
  final assignments = <ShiftAssignmentRow>[].obs;

  /// The shift for days without assignments (before 2026-09-12).
  ShiftRules _defaultShift = ShiftRules.fallback;
  final holidays = <String>{}.obs;
  final loadedAt = Rxn<DateTime>();
  final latestPunch = Rxn<EmployeeCheckin>();
  final loadError = RxnString();

  /// Ticks every minute so the freshness label re-renders.
  final clock = DateTime.now().obs;

  // ── Filters ───────────────────────────────────────────────────────────────
  final searchQuery = ''.obs;
  final activeFilters = <String, dynamic>{}.obs; // header badge + chips
  final departmentCtrl = TextEditingController();
  final statusCtrl = TextEditingController();
  late final Map<String, TextEditingController> filterControllers = {
    'department': departmentCtrl,
    'status': statusCtrl,
  };

  /// Shared by the Scrollbar and the CustomScrollView (list convention).
  final scrollController = ScrollController();

  Timer? _poll;
  bool _masterLoaded = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      clock.value = DateTime.now();
      if (isToday && !isLoading.value) reload(silent: true);
    });
  }

  @override
  void onReady() {
    super.onReady();
    loadDay();
  }

  @override
  void onClose() {
    _poll?.cancel();
    scrollController.dispose();
    departmentCtrl.dispose();
    statusCtrl.dispose();
    super.onClose();
  }

  // ── Derived ───────────────────────────────────────────────────────────────
  bool get isToday => selectedDate.value == dateOnly(DateTime.now());
  bool get isHoliday => holidays.contains(kFrappeDate.format(selectedDate.value));
  DateTime get now => clock.value;

  /// One derived row per active employee, attention-first.
  List<EmployeeDayStatus> get rows {
    final day = selectedDate.value;
    final byEmp = <String, List<EmployeeCheckin>>{};
    for (final c in checkins) {
      byEmp.putIfAbsent(c.employee, () => []).add(c);
    }
    // Two ledger rows per employee on a Morning/Afternoon day.
    final ledgerByEmp = <String, List<AttendanceRecord>>{};
    for (final r in ledger) {
      ledgerByEmp.putIfAbsent(r.employee, () => []).add(r);
    }
    final hol = isHoliday;
    final now = DateTime.now();
    final list = employees.map((e) {
      final shifts = shiftsFor(e);
      return deriveDayStatus(
        employee: e,
        day: day,
        now: now,
        shift: shifts.first,
        shifts: shifts,
        isHoliday: hol,
        punches: byEmp[e.name] ?? const [],
        ledgers: ledgerByEmp[e.name] ?? const [],
      );
    }).toList()
      ..sort(compareDayStatus);
    return list;
  }

  /// [e]'s shifts on the selected day (two on a Morning/Afternoon day).
  List<ShiftRules> shiftsFor(TrackedEmployee e) => resolveShifts(
        employee: e,
        day: selectedDate.value,
        assignments: assignments,
        catalog: catalog,
        fallback: _defaultShift,
      );

  /// Every shift worked on the selected day, earliest first.
  List<ShiftRules> get dayShifts {
    final l = distinctShifts(employees.where((e) => e.isTracked).map(shiftsFor));
    return l.isEmpty ? [_defaultShift] : l;
  }

  List<EmployeeDayStatus> get visibleRows => filterRows(
        rows,
        query: searchQuery.value,
        department: departmentCtrl.text.trim().isEmpty ? null : departmentCtrl.text,
        statusKey: statusCtrl.text.trim().isEmpty ? null : statusCtrl.text,
      );

  AttendanceCounts get counts => AttendanceCounts.of(rows);

  List<String> get departments => employees
      .map((e) => e.department)
      .where((d) => d.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  bool get hasFilters => activeFilters.isNotEmpty || searchQuery.value.isNotEmpty;

  /// Before the day's first cut-off nobody can be absent yet; on a holiday
  /// nobody is counted at all. Drives the "—" tile states.
  bool get beforeCutoff =>
      isToday && DateTime.now().isBefore(dayShifts.first.cutoffOn(selectedDate.value));

  /// Today, past the cut-off, with zero punches for anyone: the terminal has
  /// most likely not uploaded. Before the cut-off an empty list is normal.
  bool get looksOffline =>
      isToday && !isHoliday && !beforeCutoff && checkins.isEmpty && employees.any((e) => e.isTracked);

  /// Only a System Manager is told the terminal may be offline; everyone else
  /// can't tell a dead terminal from nobody punching (spec §2).
  bool get isSystemManager =>
      Get.isRegistered<AuthenticationController>() &&
      (Get.find<AuthenticationController>().currentUser.value?.hasRole('System Manager') ??
          false);

  /// Active employees with no terminal ID — HRMS marks them Absent every day.
  int get untrackedCount => employees.where((e) => !e.isTracked).length;

  String? get selectedStatusKey => statusCtrl.text.trim().isEmpty ? null : statusCtrl.text;

  // ── Loading ───────────────────────────────────────────────────────────────
  Future<void> _loadMaster() async {
    if (_masterLoaded) return;
    final emps = await _provider.fetchActiveEmployees();
    employees.assignAll(emps);
    final shiftName = emps
            .map((e) => e.defaultShift ?? '')
            .firstWhere((s) => s.isNotEmpty, orElse: () => '')
            .trim();
    try {
      _defaultShift = await _provider.fetchShiftRules(
          shiftName.isEmpty ? ShiftRules.fallback.name : shiftName);
    } catch (_) {
      _defaultShift = ShiftRules.fallback; // ponytail: fixed 08:00/08:15 if Shift Type is unreadable
    }
    catalog[_defaultShift.name] = _defaultShift;
    shift.value = _defaultShift;
    try {
      holidays.assignAll(await _provider.fetchHolidays(_defaultShift.holidayList));
    } catch (_) {}
    _masterLoaded = true;
  }

  /// Reads the Shift Types among [names] not cached yet. On failure they fall
  /// back to [ShiftRules.named] in [resolveShifts].
  Future<void> _ensureCatalog(Iterable<String> names) async {
    final missing = names.where((n) => n.isNotEmpty && !catalog.containsKey(n)).toSet();
    if (missing.isEmpty) return;
    try {
      catalog.addAll(await _provider.fetchShiftTypes(missing));
    } catch (_) {}
  }

  /// A failed read falls back to default shifts rather than failing the day.
  Future<List<ShiftAssignmentRow>> _fetchAssignments(DateTime day) async {
    try {
      return await _provider.fetchShiftAssignments(day, day);
    } catch (_) {
      return const [];
    }
  }

  /// Full reload of the selected day. [silent] keeps the list on screen
  /// (poll / icon); otherwise the skeleton shows.
  Future<void> loadDay({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    loadError.value = null;
    try {
      await _loadMaster();
      final day = selectedDate.value;
      final results = await Future.wait<Object>([
        _provider.fetchCheckins(day),
        _provider.fetchAttendance(day, day),
        _fetchAssignments(day),
      ]);
      final dayLedger = results[1] as List<AttendanceRecord>;
      final dayAssignments = results[2] as List<ShiftAssignmentRow>;
      await _ensureCatalog([
        for (final a in dayAssignments) a.shiftType,
        for (final r in dayLedger) r.shift,
      ]);
      assignments.assignAll(dayAssignments);
      checkins.assignAll(results[0] as List<EmployeeCheckin>);
      ledger.assignAll(dayLedger);
      shift.value = focusShift(dayShifts, day, DateTime.now());
      if (checkins.isEmpty) {
        try {
          latestPunch.value = await _provider.fetchLatestCheckin();
        } catch (_) {}
      }
      loadedAt.value = DateTime.now();
      clock.value = loadedAt.value!;
    } catch (e) {
      loadError.value = e.toString();
      if (!silent) GlobalSnackbar.error(message: 'Could not load attendance: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Re-entrancy-guarded refresh for the header icon and the poll.
  Future<void> reload({bool silent = false}) async {
    if (isRefreshing.value) return;
    isRefreshing.value = true;
    try {
      await loadDay(silent: true);
    } finally {
      isRefreshing.value = false;
    }
  }

  // ── Date navigation ───────────────────────────────────────────────────────
  void goToDay(DateTime day) {
    final d = dateOnly(day);
    if (d.isAfter(dateOnly(DateTime.now()))) return;
    if (d == selectedDate.value) return;
    selectedDate.value = d;
    loadDay();
  }

  void previousDay() => goToDay(selectedDate.value.subtract(const Duration(days: 1)));
  void nextDay() => goToDay(selectedDate.value.add(const Duration(days: 1)));

  Future<void> pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate.value,
      firstDate: DateTime(2020),
      lastDate: dateOnly(DateTime.now()),
    );
    if (picked != null) goToDay(picked);
  }

  // ── Filters ───────────────────────────────────────────────────────────────
  void onSearchChanged(String q) => searchQuery.value = q;

  /// Rebuilds [activeFilters] from the sheet controllers (called by the sheet's
  /// Run action and by the summary tiles).
  void applyFilters() {
    final next = <String, dynamic>{};
    if (departmentCtrl.text.trim().isNotEmpty) next['department'] = 'Dept: ${departmentCtrl.text}';
    if (statusCtrl.text.trim().isNotEmpty) next['status'] = 'Status: ${statusCtrl.text}';
    activeFilters.assignAll(next);
  }

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    applyFilters();
  }

  void clearFilters() {
    for (final c in filterControllers.values) {
      c.clear();
    }
    searchQuery.value = '';
    applyFilters();
  }

  /// Summary tile tap: toggles that status as the active status filter.
  void toggleStatusFilter(String key) {
    statusCtrl.text = statusCtrl.text == key ? '' : key;
    applyFilters();
  }
}
