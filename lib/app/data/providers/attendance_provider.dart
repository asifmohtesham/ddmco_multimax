import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// REST reads for the Attendance monitor. Everything goes through the shared
/// session-cookie [ApiProvider]; the logged-in user needs the HR User role to
/// see rows for anyone but themselves.
class AttendanceProvider {
  final ApiProvider _api = Get.find<ApiProvider>();

  /// The clocked-hours custom fields on Shift Type (design 3.3).
  static const kShiftTypeClockedFields = [
    'custom_expected_hours', 'custom_expected_hours_friday',
    'custom_break_start', 'custom_break_end',
    'custom_break_start_friday', 'custom_break_end_friday',
  ];

  /// The fields the clocked-hours Server Script stamps on Attendance.
  static const kAttendanceClockedFields = [
    'custom_punch_count', 'custom_missing_punch', 'custom_net_hours',
    'custom_expected_hours', 'custom_shortfall_hours',
  ];

  /// Per doctype: null = not tried yet, false = the site rejected the custom
  /// fields (they do not exist yet), true = they came back.
  final Map<String, bool> _optionalFieldsOk = {};

  /// Whether the last read of [doctype] carried its clocked-hours fields
  /// (null before the first read).
  bool? clockedFieldsAvailable(String doctype) => _optionalFieldsOk[doctype];

  List<Map<String, dynamic>> _rows(dynamic data) =>
      ((data is Map ? data['data'] : null) as List? ?? const [])
          .cast<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

  /// A list read with [optional] fields that may not exist on the site:
  /// Frappe refuses the whole request when a field is unknown, so on an
  /// error response the read is retried with [base] alone. When that works
  /// the fields are remembered as absent and not asked for again in this
  /// session; when it fails too, the original error surfaces. A connection
  /// error (no response) is not retried — it says nothing about the fields.
  Future<List<Map<String, dynamic>>> _listWithOptional(
    String doctype, {
    required List<String> base,
    required List<String> optional,
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    required String orderBy,
  }) async {
    Future<List<Map<String, dynamic>>> read(List<String> fields) async => _rows((await _api.getDocumentList(
          doctype,
          fields: fields,
          filters: filters,
          filterTuples: filterTuples,
          orderBy: orderBy,
          limit: 0,
        ))
        .data);

    if (_optionalFieldsOk[doctype] == false) return read(base);
    try {
      final rows = await read([...base, ...optional]);
      _optionalFieldsOk[doctype] = true;
      return rows;
    } on DioException catch (e, st) {
      if (e.response == null) rethrow;
      try {
        final rows = await read(base);
        _optionalFieldsOk[doctype] = false;
        return rows;
      } catch (_) {
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  Future<List<TrackedEmployee>> fetchActiveEmployees() async {
    final r = await _api.getDocumentList(
      'Employee',
      fields: [
        'name', 'employee_name', 'attendance_device_id', 'default_shift',
        'status', 'department', 'image', 'company',
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
  /// The clocked-hours fields are read when the site has them
  /// ([kAttendanceClockedFields]); without them the rows are as before.
  Future<List<AttendanceRecord>> fetchAttendance(DateTime from, DateTime to,
      {String? employee}) async {
    final rows = await _listWithOptional(
      'Attendance',
      base: const [
        'name', 'employee', 'employee_name', 'attendance_date', 'status',
        'working_hours', 'in_time', 'out_time', 'late_entry', 'early_exit',
        'shift', 'leave_type',
      ],
      optional: kAttendanceClockedFields,
      filters: {
        'docstatus': 1,
        'attendance_date': ['between', [kFrappeDate.format(from), kFrappeDate.format(to)]],
        if (employee != null && employee.isNotEmpty) 'employee': employee,
      },
      orderBy: 'attendance_date desc, employee_name asc',
    );
    return rows.map(AttendanceRecord.fromJson).toList();
  }

  /// Active, submitted Shift Assignments overlapping [from]..[to] (inclusive),
  /// optionally for one employee. Open-ended assignments have no end_date, so
  /// the end bound is an OR: ends on/after [from], or never ends.
  Future<List<ShiftAssignmentRow>> fetchShiftAssignments(DateTime from, DateTime to,
      {String? employee}) async {
    final r = await _api.getDocumentList(
      'Shift Assignment',
      fields: ['employee', 'shift_type', 'start_date', 'end_date'],
      filterTuples: [
        ['Shift Assignment', 'docstatus', '=', 1],
        ['Shift Assignment', 'status', '=', 'Active'],
        ['Shift Assignment', 'start_date', '<=', kFrappeDate.format(to)],
        if (employee != null && employee.isNotEmpty)
          ['Shift Assignment', 'employee', '=', employee],
      ],
      orFilterTuples: [
        ['Shift Assignment', 'end_date', '>=', kFrappeDate.format(from)],
        ['Shift Assignment', 'end_date', 'is', 'not set'],
      ],
      orderBy: 'start_date asc',
      limit: 0,
    );
    return _rows(r.data).map(ShiftAssignmentRow.fromJson).toList();
  }

  /// Shift Types by name, keyed by name. Names that do not come back are
  /// simply missing from the map. The clocked-hours fields are read when the
  /// site has them ([kShiftTypeClockedFields]).
  Future<Map<String, ShiftRules>> fetchShiftTypes(Iterable<String> names) async {
    final list = names.where((n) => n.trim().isNotEmpty).toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _listWithOptional(
      'Shift Type',
      base: const [
        'name', 'start_time', 'end_time', 'late_entry_grace_period',
        'early_exit_grace_period', 'begin_check_in_before_shift_start_time',
        'allow_check_out_after_shift_end_time', 'holiday_list',
      ],
      optional: kShiftTypeClockedFields,
      filters: {'name': ['in', list]},
      orderBy: 'start_time asc',
    );
    return {
      for (final j in rows) (j['name'] ?? '').toString(): ShiftRules.fromJson(j),
    };
  }

  Future<ShiftRules> fetchShiftRules(String shift) async {
    final r = await _api.getDocument('Shift Type', shift);
    final d = (r.data as Map?)?['data'];
    if (d is! Map) return ShiftRules.fallback;
    return ShiftRules.fromJson(Map<String, dynamic>.from(d));
  }

  /// `yyyy-MM-dd` strings of every holiday (weekly offs included).
  ///
  /// With a [holidayList] (the Shift Type names one): HR roles read that list
  /// itself. With none (HRMS 16 then resolves the list per date from the dated
  /// Holiday List Assignments, design 3.5): the company's assignments for
  /// [from]..[to] — the latest one starting on or before each date — and
  /// their lists. Either read is 403 for the Employee role, so both fall back
  /// to HRMS's self-service calendar for the logged-in employee; if that fails
  /// too, the original error surfaces. [from]/[to] default to the current
  /// year.
  Future<Set<String>> fetchHolidays(String holidayList,
      {DateTime? from, DateTime? to, String company = ''}) async {
    final year = DateTime.now().year;
    final rangeFrom = dateOnly(from ?? DateTime(year));
    final rangeTo = dateOnly(to ?? DateTime(year, 12, 31));
    try {
      if (holidayList.trim().isNotEmpty) return await _holidayListDates(holidayList);
      return await _assignedHolidays(rangeFrom, rangeTo, company);
    } catch (e, st) {
      try {
        return await _fetchOwnHolidays(rangeFrom, rangeTo);
      } catch (_) {
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  Future<Set<String>> _holidayListDates(String holidayList) async {
    final r = await _api.getDocument('Holiday List', holidayList);
    final d = (r.data as Map?)?['data'];
    final rows = (d is Map ? d['holidays'] : null) as List? ?? const [];
    return rows
        .whereType<Map>()
        .map((h) => (h['holiday_date'] ?? '').toString())
        .where((s) => s.length >= 10)
        .map((s) => s.substring(0, 10))
        .toSet();
  }

  /// Holidays for [from]..[to] from the submitted company Holiday List
  /// Assignments: each assignment's list applies from its `from_date` until
  /// the next assignment starts (HRMS `resolve_holiday_list_assignment`).
  /// No assignment → no holidays. Employee-level assignments are not read:
  /// one set of holidays serves the whole list screen.
  Future<Set<String>> _assignedHolidays(DateTime from, DateTime to, String company) async {
    const dt = 'Holiday List Assignment';
    final r = await _api.getDocumentList(
      dt,
      fields: ['holiday_list', 'from_date'],
      filterTuples: [
        [dt, 'docstatus', '=', 1],
        [dt, 'applicable_for', '=', 'Company'],
        if (company.trim().isNotEmpty) [dt, 'assigned_to', '=', company.trim()],
        [dt, 'from_date', '<=', kFrappeDate.format(to)],
      ],
      orderBy: 'from_date asc',
      limit: 0,
    );
    final periods = holidayListPeriods([
      for (final j in _rows(r.data))
        if ('${j['holiday_list'] ?? ''}'.trim().isNotEmpty &&
            DateTime.tryParse('${j['from_date'] ?? ''}') != null)
          (list: '${j['holiday_list']}'.trim(), from: DateTime.parse('${j['from_date']}')),
    ], from, to);
    final out = <String>{};
    final cache = <String, Set<String>>{};
    for (final p in periods) {
      final dates = cache[p.list] ??= await _holidayListDates(p.list);
      for (final s in dates) {
        final d = DateTime.tryParse(s);
        if (d != null && !d.isBefore(p.from) && !d.isAfter(p.to)) out.add(s);
      }
    }
    return out;
  }

  /// The logged-in employee's holiday dates in [from]..[to] (weekly offs
  /// included) from `hrms.api.get_attendance_calendar_events`, which maps
  /// each date to "Holiday" or an Attendance status.
  Future<Set<String>> _fetchOwnHolidays(DateTime from, DateTime to) async {
    final r = await _api.callMethod(
      'hrms.api.get_attendance_calendar_events',
      params: {'from_date': kFrappeDate.format(from), 'to_date': kFrappeDate.format(to)},
    );
    final events = (r.data as Map?)?['message'];
    if (events is! Map) return const {};
    return {
      for (final e in events.entries)
        if (e.value == 'Holiday') e.key.toString(),
    };
  }
}

/// Which Holiday List applies when within [from]..[to], given dated
/// assignments (any order): each runs from its own start until the day before
/// the next one starts; days before the first assignment have none. Pure, for
/// tests.
List<({String list, DateTime from, DateTime to})> holidayListPeriods(
    List<({String list, DateTime from})> assignments, DateTime from, DateTime to) {
  final sorted = [...assignments]..sort((a, b) => a.from.compareTo(b.from));
  final out = <({String list, DateTime from, DateTime to})>[];
  for (var i = 0; i < sorted.length; i++) {
    final start = dateOnly(sorted[i].from);
    final end = i + 1 < sorted.length
        ? dateOnly(sorted[i + 1].from).subtract(const Duration(days: 1))
        : dateOnly(to);
    final lo = start.isBefore(dateOnly(from)) ? dateOnly(from) : start;
    final hi = end.isAfter(dateOnly(to)) ? dateOnly(to) : end;
    if (!hi.isBefore(lo)) out.add((list: sorted[i].list, from: lo, to: hi));
  }
  return out;
}
