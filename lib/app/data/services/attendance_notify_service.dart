/// Reads everything one attendance-notification run needs, as the logged-in
/// user, over the app's persisted session cookies (same jar as ApiProvider,
/// like DigestService). Safe to construct in any isolate.
library;

import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:multimax/app/data/models/attendance_models.dart';

class AttendanceNotifyData {
  final bool authExpired;
  final bool tracked;
  final List<ShiftAssignmentRow> assignments;
  final Map<String, ShiftRules> catalog;
  final List<EmployeeCheckin> punches;

  /// Own Attendance rows from day − 3 to day (recap window + today).
  final List<AttendanceRecord> ledger;
  final bool holiday;
  final bool onLeave;

  /// The organisation's Holiday List (Shift Type → `holiday_list`), read
  /// independently of the employee's own calendar. Only populated when
  /// [fetch] is called with `withOrgHoliday: true`; unreadable ⇒ false (a
  /// working day). For a System Manager's terminal watch, which must not go
  /// dark just because that person is personally off.
  final bool orgHoliday;

  /// Null when the heartbeat document could not be read.
  final SyncStatus? sync;

  const AttendanceNotifyData({
    this.authExpired = false,
    this.tracked = false,
    this.assignments = const [],
    this.catalog = const {},
    this.punches = const [],
    this.ledger = const [],
    this.holiday = false,
    this.onLeave = false,
    this.orgHoliday = false,
    this.sync,
  });

  static const AttendanceNotifyData expired = AttendanceNotifyData(authExpired: true);

  List<AttendanceRecord> ledgerOn(DateTime day) {
    final key = kFrappeDate.format(day);
    return [for (final r in ledger) if (kFrappeDate.format(r.date) == key) r];
  }
}

class AttendanceNotifyService {
  final String baseUrl;

  /// Directory of the app's PersistCookieJar (`<appSupportDir>/.cookies/`).
  final String cookieDir;

  Dio? _dio;

  AttendanceNotifyService({required this.baseUrl, required this.cookieDir});

  Dio _client() {
    if (_dio != null) return _dio!;
    final jar = PersistCookieJar(ignoreExpires: true, storage: FileStorage(cookieDir));
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ))
      ..interceptors.add(CookieManager(jar));
    return _dio!;
  }

  /// Single HTTP seam — tests subclass and override this.
  Future<Response> callGet(String path, Map<String, dynamic> query) =>
      _client().get(path, queryParameters: query);

  Future<List<Map<String, dynamic>>> _list(
    String doctype, {
    required List<String> fields,
    List<List<dynamic>> filters = const [],
    List<List<dynamic>> orFilters = const [],
    String orderBy = 'modified desc',
  }) async {
    final res = await callGet('/api/resource/$doctype', {
      'fields': jsonEncode(fields),
      'filters': jsonEncode(filters),
      if (orFilters.isNotEmpty) 'or_filters': jsonEncode(orFilters),
      'order_by': orderBy,
      'limit_page_length': 0,
    });
    final data = res.data is Map ? res.data['data'] : null;
    return (data is List ? data : const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// One document, or null when it can't be read (403 / 404 / network).
  /// Fully tolerant — for reads the brief marks tolerant on purpose (the
  /// heartbeat, the Holiday List).
  Future<Map<String, dynamic>?> _doc(String doctype, String name) async {
    try {
      final res = await callGet('/api/resource/$doctype/$name', const {});
      final data = res.data is Map ? res.data['data'] : null;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on DioException {
      return null;
    }
  }

  /// The Employee doc, narrowly tolerant: only 403 (no read permission) and
  /// 404 (no such Employee) are treated as "the document isn't there" and
  /// return null. Any other DioException (a 500, a connection error with no
  /// response, a timeout) or non-Dio throw propagates, so [fetch]'s outer
  /// catch turns a failed Employee read into a failed run rather than a
  /// false "not tracked" — same narrow-tolerance shape as
  /// DigestService.fetchDigest.
  Future<Map<String, dynamic>?> _employeeDoc(String name) async {
    try {
      final res = await callGet('/api/resource/Employee/$name', const {});
      final data = res.data is Map ? res.data['data'] : null;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) return null;
      rethrow;
    }
  }

  /// Everything for [employee] (empty for a System Manager without one) on
  /// [day]. `expired` when the session probe says so; null when a required
  /// read fails — the worker then posts nothing and retries soon.
  Future<AttendanceNotifyData?> fetch(
      {required String employee, required DateTime day, bool withOrgHoliday = false}) async {
    try {
      final res = await callGet('/api/method/frappe.auth.get_logged_user', const {});
      final who = res.data is Map ? res.data['message'] : null;
      if (who == null || who == 'Guest') return AttendanceNotifyData.expired;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return AttendanceNotifyData.expired;
      return null;
    } catch (_) {
      return null;
    }

    try {
      final d = kFrappeDate.format(day);
      final from = kFrappeDate.format(dateOnly(day).subtract(const Duration(days: 3)));
      var tracked = false;
      var assignments = <ShiftAssignmentRow>[];
      var ledger = <AttendanceRecord>[];
      var punches = <EmployeeCheckin>[];
      var onLeave = false;

      if (employee.isNotEmpty) {
        // 403/404 on the Employee read means "not tracked"; anything else
        // (500, connection error, timeout) is a failed run — propagates to
        // the outer catch below, which turns it into null.
        final emp = await _employeeDoc(employee);
        tracked = '${emp?['attendance_device_id'] ?? ''}'.trim().isNotEmpty;
      }
      if (tracked) {
        assignments = (await _list('Shift Assignment',
                fields: ['employee', 'shift_type', 'start_date', 'end_date'],
                filters: [
                  ['Shift Assignment', 'employee', '=', employee],
                  ['Shift Assignment', 'docstatus', '=', 1],
                  ['Shift Assignment', 'status', '=', 'Active'],
                  ['Shift Assignment', 'start_date', '<=', d],
                ],
                orFilters: [
                  ['Shift Assignment', 'end_date', '>=', d],
                  ['Shift Assignment', 'end_date', 'is', 'not set'],
                ],
                orderBy: 'start_date asc'))
            .map(ShiftAssignmentRow.fromJson)
            .toList();
        ledger = (await _list('Attendance',
                fields: [
                  'name', 'employee', 'employee_name', 'attendance_date', 'status',
                  'working_hours', 'in_time', 'out_time', 'late_entry', 'early_exit',
                  'shift', 'leave_type',
                ],
                filters: [
                  ['Attendance', 'employee', '=', employee],
                  ['Attendance', 'docstatus', '=', 1],
                  ['Attendance', 'attendance_date', 'between', [from, d]],
                ],
                orderBy: 'attendance_date desc'))
            .map(AttendanceRecord.fromJson)
            .toList();
        punches = (await _list('Employee Checkin',
                fields: ['name', 'employee', 'time', 'log_type', 'device_id', 'shift'],
                filters: [
                  ['Employee Checkin', 'employee', '=', employee],
                  ['Employee Checkin', 'time', 'between', ['$d 00:00:00', '$d 23:59:59']],
                ],
                orderBy: 'time asc'))
            .map(EmployeeCheckin.fromJson)
            .toList();
        onLeave = await _onLeave(employee, d);
      }

      final names = <String>{
        for (final a in assignments) a.shiftType,
        for (final r in ledger)
          if (r.shift.trim().isNotEmpty) r.shift,
      };
      final catalog = <String, ShiftRules>{};
      if (names.isNotEmpty) {
        final rows = await _list('Shift Type',
            fields: [
              'name', 'start_time', 'end_time', 'late_entry_grace_period',
              'early_exit_grace_period', 'begin_check_in_before_shift_start_time',
              'allow_check_out_after_shift_end_time', 'holiday_list',
            ],
            filters: [
              ['Shift Type', 'name', 'in', names.toList()],
            ]);
        for (final j in rows) {
          catalog['${j['name'] ?? ''}'] = ShiftRules.fromJson(j);
        }
      }

      final holiday = await _isHoliday(d, employee: tracked ? employee : '', catalog: catalog);
      final orgHoliday =
          withOrgHoliday ? await _isHoliday(d, employee: '', catalog: catalog) : false;
      final syncDoc = await _doc('Attendance Sync Status', 'Attendance Sync Status');
      return AttendanceNotifyData(
        tracked: tracked,
        assignments: assignments,
        catalog: catalog,
        punches: punches,
        ledger: ledger,
        holiday: holiday,
        onLeave: onLeave,
        orgHoliday: orgHoliday,
        sync: syncDoc == null ? null : SyncStatus.fromJson(syncDoc),
      );
    } catch (_) {
      return null;
    }
  }

  /// An approved Leave Application covering [d]. Unreadable (e.g. 403 for the
  /// Employee role) ⇒ false; the Attendance row's On Leave still silences.
  Future<bool> _onLeave(String employee, String d) async {
    try {
      final rows = await _list('Leave Application', fields: ['name'], filters: [
        ['Leave Application', 'employee', '=', employee],
        ['Leave Application', 'status', '=', 'Approved'],
        ['Leave Application', 'docstatus', '=', 1],
        ['Leave Application', 'from_date', '<=', d],
        ['Leave Application', 'to_date', '>=', d],
      ]);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Employees read HRMS's own calendar (Holiday List is 403 for them); a
  /// System Manager without an employee reads the shifts' Holiday List.
  /// Unreadable ⇒ a working day.
  Future<bool> _isHoliday(String d,
      {required String employee, required Map<String, ShiftRules> catalog}) async {
    try {
      if (employee.isNotEmpty) {
        final res = await callGet('/api/method/hrms.api.get_attendance_calendar_events',
            {'from_date': d, 'to_date': d});
        final msg = res.data is Map ? res.data['message'] : null;
        return msg is Map && msg[d] == 'Holiday';
      }
      // No employee ⇒ not tracked ⇒ catalog is always empty (it's built
      // from assignment/ledger shift names, only read when tracked) — so
      // the only source for a holiday list here is a fresh Shift Type read.
      var list = '';
      final rows = await _list('Shift Type', fields: ['name', 'holiday_list']);
      for (final j in rows) {
        final h = '${j['holiday_list'] ?? ''}'.trim();
        if (h.isNotEmpty) {
          list = h;
          break;
        }
      }
      if (list.isEmpty) return false;
      final doc = await _doc('Holiday List', list);
      final holidays = doc?['holidays'];
      return holidays is List &&
          holidays.whereType<Map>().any((h) => '${h['holiday_date'] ?? ''}'.startsWith(d));
    } catch (_) {
      return false;
    }
  }
}
