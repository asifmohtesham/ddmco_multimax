import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/attendance_notify_service.dart';

/// Hand-written fake (repo convention): overrides the single HTTP seam.
class _FakeService extends AttendanceNotifyService {
  _FakeService() : super(baseUrl: 'https://erp.test', cookieDir: '/x/');

  String? loggedUser = 'e1@x.com';
  DioException? probeError;

  /// path → response data (List for resource lists, Map for docs / method
  /// messages) or a DioException to throw.
  final Map<String, Object> responses = {};
  final List<String> paths = [];

  static DioException err(int? code) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: code == null ? null : Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
        type: code == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
      );

  Response _ok(Object data) => Response(requestOptions: RequestOptions(path: '/x'), statusCode: 200, data: data);

  @override
  Future<Response> callGet(String path, Map<String, dynamic> query) async {
    paths.add(path);
    if (path == '/api/method/frappe.auth.get_logged_user') {
      if (probeError != null) throw probeError!;
      return _ok({'message': loggedUser});
    }
    final r = responses[path];
    if (r is DioException) throw r;
    if (path.startsWith('/api/method/')) return _ok({'message': r ?? const {}});
    return _ok({'data': r ?? const []});
  }
}

final day = DateTime(2026, 9, 12);

void _seedEmployee(_FakeService f) {
  f.responses['/api/resource/Employee/E1'] = {'name': 'E1', 'attendance_device_id': '7'};
  f.responses['/api/resource/Shift Assignment'] = [
    {'employee': 'E1', 'shift_type': 'Morning', 'start_date': '2026-09-12', 'end_date': '2026-09-17'},
    {'employee': 'E1', 'shift_type': 'Afternoon', 'start_date': '2026-09-12', 'end_date': '2026-09-17'},
  ];
  f.responses['/api/resource/Shift Type'] = [
    {'name': 'Morning', 'start_time': '8:00:00', 'end_time': '12:15:00', 'late_entry_grace_period': 15},
    {'name': 'Afternoon', 'start_time': '13:30:00', 'end_time': '20:00:00', 'late_entry_grace_period': 15},
  ];
  f.responses['/api/resource/Employee Checkin'] = [
    {'name': 'c1', 'employee': 'E1', 'time': '2026-09-12 07:58:00', 'log_type': 'IN'},
  ];
  f.responses['/api/resource/Attendance Sync Status/Attendance Sync Status'] = {
    'terminal_online': 1,
    'terminal_last_seen': '2026-09-12 07:59:00',
    'agent_last_run': '2026-09-12 08:00:00',
  };
}

void main() {
  test('Guest or 401 at the probe: session expired', () async {
    final f = _FakeService()..loggedUser = 'Guest';
    expect((await f.fetch(employee: 'E1', day: day))!.authExpired, isTrue);
    final g = _FakeService()..probeError = _FakeService.err(401);
    expect((await g.fetch(employee: 'E1', day: day))!.authExpired, isTrue);
  });

  test('network error at the probe: null (post nothing)', () async {
    final f = _FakeService()..probeError = _FakeService.err(null);
    expect(await f.fetch(employee: 'E1', day: day), isNull);
  });

  test('tracked employee: assignments, catalog, punches, heartbeat', () async {
    final f = _FakeService();
    _seedEmployee(f);
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.authExpired, isFalse);
    expect(d.tracked, isTrue);
    expect(d.assignments.map((a) => a.shiftType), ['Morning', 'Afternoon']);
    expect(d.catalog.keys.toSet(), {'Morning', 'Afternoon'});
    expect(d.punches.single.time, DateTime(2026, 9, 12, 7, 58));
    expect(d.holiday, isFalse);
    expect(d.onLeave, isFalse);
    expect(d.sync!.terminalOnline, isTrue);
  });

  test('untracked employee: no shift reads', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Employee/E1'] = {'name': 'E1', 'attendance_device_id': ''};
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.tracked, isFalse);
    expect(f.paths, isNot(contains('/api/resource/Shift Assignment')));
  });

  test('approved leave, holiday and an unreadable heartbeat', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Leave Application'] = [
      {'name': 'HR-LAP-0001'},
    ];
    f.responses['/api/method/hrms.api.get_attendance_calendar_events'] = {'2026-09-12': 'Holiday'};
    f.responses['/api/resource/Attendance Sync Status/Attendance Sync Status'] = _FakeService.err(403);
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.onLeave, isTrue);
    expect(d.holiday, isTrue);
    expect(d.sync, isNull);
  });

  test('Leave Application 403 is tolerated', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Leave Application'] = _FakeService.err(403);
    final d = await f.fetch(employee: 'E1', day: day);
    expect(d, isNotNull);
    expect(d!.onLeave, isFalse);
  });

  test('a failed required read: null', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Shift Assignment'] = _FakeService.err(500);
    expect(await f.fetch(employee: 'E1', day: day), isNull);
  });

  test('a 500 on the Employee read fails the run', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Employee/E1'] = _FakeService.err(500);
    expect(await f.fetch(employee: 'E1', day: day), isNull);
  });

  test('a connection error on the Employee read fails the run', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Employee/E1'] = _FakeService.err(null);
    expect(await f.fetch(employee: 'E1', day: day), isNull);
  });

  test('404 on the Employee read means not tracked', () async {
    final f = _FakeService();
    _seedEmployee(f);
    f.responses['/api/resource/Employee/E1'] = _FakeService.err(404);
    final d = await f.fetch(employee: 'E1', day: day);
    expect(d, isNotNull);
    expect(d!.tracked, isFalse);
    expect(f.paths, isNot(contains('/api/resource/Shift Assignment')));
  });

  test('withOrgHoliday reads the organisation holiday list', () async {
    final f = _FakeService();
    _seedEmployee(f);
    // The employee's own calendar says nothing for the day (default hrms
    // response is {}), but the Shift Type points at an org Holiday List
    // that does cover it.
    f.responses['/api/resource/Shift Type'] = [
      {'name': 'Morning', 'start_time': '8:00:00', 'end_time': '12:15:00',
        'late_entry_grace_period': 15, 'holiday_list': 'Multimax 2026'},
      {'name': 'Afternoon', 'start_time': '13:30:00', 'end_time': '20:00:00', 'late_entry_grace_period': 15},
    ];
    f.responses['/api/resource/Holiday List/Multimax 2026'] = {
      'holidays': [
        {'holiday_date': '2026-09-12'},
      ],
    };
    final d = (await f.fetch(employee: 'E1', day: day, withOrgHoliday: true))!;
    expect(d.holiday, isFalse);
    expect(d.orgHoliday, isTrue);
  });

  test('withOrgHoliday: false (the default) never requests the Holiday List path', () async {
    final f = _FakeService();
    _seedEmployee(f);
    final d = (await f.fetch(employee: 'E1', day: day))!;
    expect(d.orgHoliday, isFalse);
    expect(f.paths.where((p) => p.startsWith('/api/resource/Holiday List/')), isEmpty);
  });

  test('System Manager without an employee: holiday from the shift holiday list', () async {
    final f = _FakeService();
    f.responses['/api/resource/Shift Type'] = [
      {'name': 'Morning', 'holiday_list': 'Multimax 2026'},
    ];
    f.responses['/api/resource/Holiday List/Multimax 2026'] = {
      'holidays': [
        {'holiday_date': '2026-09-13'},
      ],
    };
    f.responses['/api/resource/Attendance Sync Status/Attendance Sync Status'] = {'terminal_online': 0};
    final d = (await f.fetch(employee: '', day: DateTime(2026, 9, 13)))!;
    expect(d.tracked, isFalse);
    expect(d.holiday, isTrue);
    expect(d.sync!.terminalOnline, isFalse);
  });
}
