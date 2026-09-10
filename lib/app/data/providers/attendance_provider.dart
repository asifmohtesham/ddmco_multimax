import 'package:get/get.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// REST reads for the Attendance monitor. Everything goes through the shared
/// session-cookie [ApiProvider]; the logged-in user needs the HR User role to
/// see rows for anyone but themselves.
class AttendanceProvider {
  final ApiProvider _api = Get.find<ApiProvider>();

  List<Map<String, dynamic>> _rows(dynamic data) =>
      ((data is Map ? data['data'] : null) as List? ?? const [])
          .cast<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

  Future<List<TrackedEmployee>> fetchActiveEmployees() async {
    final r = await _api.getDocumentList(
      'Employee',
      fields: [
        'name', 'employee_name', 'attendance_device_id', 'default_shift',
        'status', 'department', 'image',
      ],
      filters: {'status': 'Active'},
      orderBy: 'employee_name asc',
      limit: 0,
    );
    return _rows(r.data).map(TrackedEmployee.fromJson).toList();
  }

  /// Punches with `time` inside [day] (local, naive, as Frappe stores them).
  Future<List<EmployeeCheckin>> fetchCheckins(DateTime day) async {
    final from = kFrappeDateTime.format(dateOnly(day));
    final to = kFrappeDateTime.format(
        dateOnly(day).add(const Duration(days: 1)).subtract(const Duration(seconds: 1)));
    final r = await _api.getDocumentList(
      'Employee Checkin',
      fields: ['name', 'employee', 'employee_name', 'time', 'log_type', 'device_id', 'shift', 'attendance'],
      filters: {'time': ['between', [from, to]]},
      orderBy: 'time asc',
      limit: 0,
    );
    return _rows(r.data).map(EmployeeCheckin.fromJson).toList();
  }

  /// Newest punch on the site, used to say when the terminal last uploaded.
  Future<EmployeeCheckin?> fetchLatestCheckin() async {
    final r = await _api.getDocumentList(
      'Employee Checkin',
      fields: ['name', 'employee', 'time', 'device_id'],
      orderBy: 'time desc',
      limit: 1,
    );
    final rows = _rows(r.data);
    return rows.isEmpty ? null : EmployeeCheckin.fromJson(rows.first);
  }

  /// Submitted Attendance rows for a date range (inclusive), optionally one
  /// employee.
  Future<List<AttendanceRecord>> fetchAttendance(DateTime from, DateTime to,
      {String? employee}) async {
    final r = await _api.getDocumentList(
      'Attendance',
      fields: [
        'name', 'employee', 'employee_name', 'attendance_date', 'status',
        'working_hours', 'in_time', 'out_time', 'late_entry', 'early_exit',
        'shift', 'leave_type',
      ],
      filters: {
        'docstatus': 1,
        'attendance_date': ['between', [kFrappeDate.format(from), kFrappeDate.format(to)]],
        if (employee != null && employee.isNotEmpty) 'employee': employee,
      },
      orderBy: 'attendance_date desc, employee_name asc',
      limit: 0,
    );
    return _rows(r.data).map(AttendanceRecord.fromJson).toList();
  }

  Future<ShiftRules> fetchShiftRules(String shift) async {
    final r = await _api.getDocument('Shift Type', shift);
    final d = (r.data as Map?)?['data'];
    if (d is! Map) return ShiftRules.fallback;
    return ShiftRules.fromJson(Map<String, dynamic>.from(d));
  }

  /// `yyyy-MM-dd` strings of every holiday (weekly offs included).
  ///
  /// HR roles read the Holiday List itself. The Employee role gets 403 there,
  /// so fall back to HRMS's self-service calendar for the logged-in employee;
  /// if that fails too, the original error surfaces.
  Future<Set<String>> fetchHolidays(String holidayList) async {
    if (holidayList.trim().isEmpty) return const {};
    try {
      final r = await _api.getDocument('Holiday List', holidayList);
      final d = (r.data as Map?)?['data'];
      final rows = (d is Map ? d['holidays'] : null) as List? ?? const [];
      return rows
          .whereType<Map>()
          .map((h) => (h['holiday_date'] ?? '').toString().substring(0, 10))
          .where((s) => s.length == 10)
          .toSet();
    } catch (e, st) {
      try {
        return await _fetchOwnHolidays(DateTime.now().year);
      } catch (_) {
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  /// The logged-in employee's holiday dates in [year] (weekly offs included)
  /// from `hrms.api.get_attendance_calendar_events`, which maps each date to
  /// "Holiday" or an Attendance status.
  // ponytail: current year only — as an Employee, months of a previous year
  // show no holiday labels; pass the viewed range if that ever matters.
  Future<Set<String>> _fetchOwnHolidays(int year) async {
    final r = await _api.callMethod(
      'hrms.api.get_attendance_calendar_events',
      params: {'from_date': '$year-01-01', 'to_date': '$year-12-31'},
    );
    final events = (r.data as Map?)?['message'];
    if (events is! Map) return const {};
    return {
      for (final e in events.entries)
        if (e.value == 'Holiday') e.key.toString(),
    };
  }
}
