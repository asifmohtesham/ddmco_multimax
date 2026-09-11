import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_controller.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

/// One employee's month: Attendance ledger rows plus today's derived status
/// (there is no ledger row for today until the shift closes).
class AttendanceMonthController extends GetxController {
  final AttendanceProvider _provider = Get.find<AttendanceProvider>();

  late final TrackedEmployee employee;
  final month = DateTime(DateTime.now().year, DateTime.now().month).obs;
  final records = <AttendanceRecord>[].obs;
  final isLoading = true.obs;
  final holidays = <String>{}.obs;
  EmployeeDayStatus? today;
  final scrollController = ScrollController();

  /// Shift rules and holidays come from the route arguments (Dashboard,
  /// detail sheet), else the list screen if it is underneath us; [load]
  /// fetches holidays itself if still unknown, so every entry path shows
  /// Sundays and real late minutes.
  ShiftRules shift = ShiftRules.fallback;

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
      records.assignAll(await _provider.fetchAttendance(first, last, employee: employee.name));
    } catch (e) {
      GlobalSnackbar.error(message: 'Could not load month: $e');
    } finally {
      isLoading.value = false;
    }
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

  /// Status for a calendar day, or null when there is nothing to show.
  AttendanceStatus? statusOn(DateTime d) {
    final key = kFrappeDate.format(d);
    for (final r in records) {
      if (kFrappeDate.format(r.date) == key) {
        return deriveDayStatus(
          employee: employee,
          day: d,
          now: DateTime.now(),
          shift: shift,
          isHoliday: false,
          ledger: r,
        ).status;
      }
    }
    if (today != null && dateOnly(d) == dateOnly(DateTime.now())) return today!.status;
    if (isHoliday(d)) return AttendanceStatus.holiday;
    return null;
  }

  /// "8 working days · 6 present · 1 absent" for the elapsed part of the month.
  String get summary {
    final end = isCurrentMonth ? dateOnly(DateTime.now()) : last;
    var working = 0;
    for (var d = first; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (!isHoliday(d)) working++;
    }
    var present = 0, absent = 0;
    for (final r in records) {
      if (r.status == 'Present') present++;
      if (r.status == 'Absent') absent++;
    }
    if (today != null && isCurrentMonth) {
      if (today!.status == AttendanceStatus.present || today!.status == AttendanceStatus.late) present++;
      if (today!.status.isAbsent) absent++;
    }
    return '$working working day${working == 1 ? '' : 's'} · $present present · $absent absent';
  }
}
