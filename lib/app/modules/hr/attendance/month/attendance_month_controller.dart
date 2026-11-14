import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_controller.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

/// One employee's month: Attendance ledger rows (two per day on a
/// Morning/Afternoon day) plus today's derived status (a shift has no ledger
/// row until its check-out window closes).
class AttendanceMonthController extends GetxController {
  final AttendanceProvider _provider = Get.find<AttendanceProvider>();

  late final TrackedEmployee employee;
  final month = DateTime(DateTime.now().year, DateTime.now().month).obs;
  final records = <AttendanceRecord>[].obs;
  final assignments = <ShiftAssignmentRow>[].obs;
  final isLoading = true.obs;
  final holidays = <String>{}.obs;
  EmployeeDayStatus? today;
  final scrollController = ScrollController();

  /// Shift rules, the Shift Type catalog and holidays come from the route
  /// arguments (Dashboard, detail sheet), else the list screen if it is
  /// underneath us; [load] fetches whatever is still unknown, so every entry
  /// path shows Sundays, both shifts and real late minutes.
  ShiftRules shift = ShiftRules.fallback;
  final catalog = <String, ShiftRules>{};

  @override
  void onInit() {
    super.onInit();
    final args = (Get.arguments as Map?) ?? const {};
    employee = args['employee'] as TrackedEmployee;
    final m = args['month'] as DateTime?;
    if (m != null) month.value = DateTime(m.year, m.month);
    today = args['today'] as EmployeeDayStatus?;
    final list = Get.isRegistered<AttendanceController>()
        ? Get.find<AttendanceController>()
        : null;
    shift = args['shift'] as ShiftRules? ?? list?.shift.value ?? ShiftRules.fallback;
    holidays.assignAll(args['holidays'] as Set<String>? ?? list?.holidays ?? const <String>{});
    catalog
      ..addAll(args['catalog'] as Map<String, ShiftRules>? ??
          list?.catalog ??
          const <String, ShiftRules>{})
      ..putIfAbsent(shift.name, () => shift);
  }

  @override
  void onReady() {
    super.onReady();
    load();
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  DateTime get first => month.value;
  DateTime get last => DateTime(month.value.year, month.value.month + 1, 0);
  bool get isCurrentMonth =>
      month.value.year == DateTime.now().year && month.value.month == DateTime.now().month;

  Future<void> load() async {
    isLoading.value = true;
    try {
      if (holidays.isEmpty && shift.holidayList.isNotEmpty) {
        try {
          holidays.assignAll(await _provider.fetchHolidays(shift.holidayList));
        } catch (_) {} // a month without holiday labels beats no month
      }
      final results = await Future.wait<Object>([
        _provider.fetchAttendance(first, last, employee: employee.name),
        _fetchAssignments(),
      ]);
      final recs = results[0] as List<AttendanceRecord>;
      final asg = results[1] as List<ShiftAssignmentRow>;
      await _ensureCatalog([for (final a in asg) a.shiftType, for (final r in recs) r.shift]);
      assignments.assignAll(asg);
      records.assignAll(recs);
    } catch (e) {
      GlobalSnackbar.error(message: 'Could not load month: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// A failed read leaves the ledger rows to name the shifts.
  Future<List<ShiftAssignmentRow>> _fetchAssignments() async {
    try {
      return await _provider.fetchShiftAssignments(first, last, employee: employee.name);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _ensureCatalog(Iterable<String> names) async {
    final missing = names.where((n) => n.isNotEmpty && !catalog.containsKey(n)).toSet();
    if (missing.isEmpty) return;
    try {
      catalog.addAll(await _provider.fetchShiftTypes(missing));
    } catch (_) {}
  }

  void previousMonth() {
    month.value = DateTime(month.value.year, month.value.month - 1);
    load();
  }

  void nextMonth() {
    if (isCurrentMonth) return;
    month.value = DateTime(month.value.year, month.value.month + 1);
    load();
  }

  bool isHoliday(DateTime d) => holidays.contains(kFrappeDate.format(d));

  List<AttendanceRecord> recordsOn(DateTime d) {
    final key = kFrappeDate.format(d);
    return [for (final r in records) if (kFrappeDate.format(r.date) == key) r];
  }

  /// The shifts of [d], earliest first: those its ledger rows and Shift
  /// Assignments name; the route's shift when neither names one.
  List<ShiftRules> shiftsOn(DateTime d) {
    final names = <String>{
      for (final r in recordsOn(d))
        if (r.shift.isNotEmpty) r.shift,
      for (final a in assignments)
        if (a.employee == employee.name && a.covers(d)) a.shiftType,
    };
    if (names.isEmpty) return [shift];
    return [for (final n in names) catalog[n] ?? ShiftRules.named(n)]
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Status for a calendar day, or null when there is nothing to show. Today
  /// is the live row: a Morning ledger row exists from ~13:00 while the
  /// Afternoon is still running, so the ledger alone would call it absent.
  AttendanceStatus? statusOn(DateTime d) {
    if (today != null && dateOnly(d) == dateOnly(DateTime.now())) return today!.status;
    final recs = recordsOn(d);
    if (recs.isNotEmpty) {
      final shifts = shiftsOn(d);
      return deriveDayStatus(
        employee: employee,
        day: d,
        now: DateTime.now(),
        shift: shifts.first,
        shifts: shifts,
        isHoliday: false,
        ledgers: recs,
      ).status;
    }
    if (isHoliday(d)) return AttendanceStatus.holiday;
    return null;
  }

  /// One ledger row as its own shift: status, in/out, flags. A row with no
  /// out time is No check-out only on a two-shift day.
  ShiftDayStatus ledgerRowStatus(AttendanceRecord r) => deriveShiftStatus(
        shift: catalog[r.shift] ?? (r.shift.isEmpty ? shift : ShiftRules.named(r.shift)),
        day: r.date,
        now: DateTime.now(),
        ledger: r,
        requireCheckOut: shiftsOn(r.date).length > 1,
      );

  /// "8 working days · 6 present · 1 absent" (+ " · 2 no check-out") for the
  /// elapsed part of the month, counted by day.
  String get summary {
    final end = isCurrentMonth ? dateOnly(DateTime.now()) : last;
    var working = 0, present = 0, absent = 0, noOut = 0;
    for (var d = first; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (!isHoliday(d)) working++;
      switch (statusOn(d)) {
        case AttendanceStatus.present || AttendanceStatus.late:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.noCheckOut:
          noOut++;
        default:
          break;
      }
    }
    return '$working working day${working == 1 ? '' : 's'} · $present present · $absent absent'
        '${noOut > 0 ? ' · $noOut no check-out' : ''}';
  }
}
