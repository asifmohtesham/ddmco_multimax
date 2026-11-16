import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';

// AttendanceProvider.fetchHolidays: HR roles read the Holiday List; the
// Employee role gets 403 there, so holidays come from HRMS's self-service
// calendar instead (weekly offs included).

class _FakeApi extends ApiProvider {
  Object? holidayListError;
  Map<String, dynamic> holidayListDoc = const {};

  /// Holiday List docs by name (overrides [holidayListDoc] when set).
  Map<String, Map<String, dynamic>> holidayLists = const {};

  /// When true, a list request naming any `custom_*` field gets the 417 a
  /// site without those fields returns.
  bool rejectCustomFields = false;

  /// Rows per doctype (overrides [listRows]); a doctype in [listErrors] throws.
  Map<String, List<Map<String, dynamic>>> rowsByDoctype = const {};
  Map<String, Object> listErrors = const {};

  /// Every list call's doctype and fields, in order.
  final listCalls = <({String doctype, List<String>? fields})>[];

  /// Calendar events returned by callMethod; null makes callMethod throw.
  Map<String, dynamic>? calendar;
  final calls = <({String method, Map<String, dynamic>? params})>[];

  /// Rows returned by getDocumentList, and the arguments of the last call.
  List<Map<String, dynamic>> listRows = const [];
  ({
    String doctype,
    Map<String, dynamic>? filters,
    List<List<dynamic>>? filterTuples,
    List<List<dynamic>>? orFilterTuples,
  })? lastList;

  @override
  Future<Response> getDocumentList(String doctype,
      {int limit = 20,
      int limitStart = 0,
      List<String>? fields,
      String? groupBy = '',
      Map<String, dynamic>? filters,
      List<List<dynamic>>? filterTuples,
      Map<String, dynamic>? orFilters,
      List<List<dynamic>>? orFilterTuples,
      String orderBy = 'modified desc'}) async {
    lastList = (
      doctype: doctype,
      filters: filters,
      filterTuples: filterTuples,
      orFilterTuples: orFilterTuples,
    );
    listCalls.add((doctype: doctype, fields: fields));
    final req = RequestOptions(path: '/api/resource/$doctype');
    if (listErrors[doctype] != null) throw listErrors[doctype]!;
    if (rejectCustomFields && (fields ?? const []).any((f) => f.startsWith('custom_'))) {
      throw DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: 417, data: {
          'exception': 'frappe.exceptions.DataError: Field not permitted in query: custom_net_hours',
        }),
        type: DioExceptionType.badResponse,
      );
    }
    return Response(
      requestOptions: req,
      statusCode: 200,
      data: {'data': rowsByDoctype[doctype] ?? listRows},
    );
  }

  final docCalls = <String>[];

  @override
  Future<Response> getDocument(String doctype, String name) async {
    docCalls.add('$doctype/$name');
    if (holidayListError != null) throw holidayListError!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype/$name'),
      statusCode: 200,
      data: {'data': holidayLists[name] ?? holidayListDoc},
    );
  }

  @override
  Future<Response> callMethod(String method,
      {Map<String, dynamic>? params}) async {
    calls.add((method: method, params: params));
    if (calendar == null) throw Exception('calendar unavailable');
    return Response(
      requestOptions: RequestOptions(path: '/api/method/$method'),
      statusCode: 200,
      data: {'message': calendar},
    );
  }
}

/// Never touches GetStorage; ApiProvider._initDio only reads getBaseUrl.
class _FakeStorage extends StorageService {
  _FakeStorage() : super.withStorage(null);

  @override
  String? getBaseUrl() => null;
}

DioException _forbidden() {
  final req = RequestOptions(path: '/api/resource/Holiday List/Multimax 2026');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: 403),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ApiProvider's constructor touches path_provider for the cookie jar.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  late _FakeApi api;
  late AttendanceProvider provider;

  setUp(() {
    Get.put<StorageService>(_FakeStorage());
    api = _FakeApi();
    Get.put<ApiProvider>(api);
    provider = AttendanceProvider();
  });

  tearDown(() => Get.deleteAll(force: true));

  test('HR roles read the Holiday List directly', () async {
    api.holidayListDoc = {
      'holidays': [
        {'holiday_date': '2026-09-06', 'weekly_off': 1},
        {'holiday_date': '2026-09-13', 'weekly_off': 1},
      ],
    };
    expect(await provider.fetchHolidays('Multimax 2026'),
        {'2026-09-06', '2026-09-13'});
    expect(api.calls, isEmpty);
  });

  test('Employee role (403) falls back to the HRMS calendar, Sundays included',
      () async {
    api.holidayListError = _forbidden();
    api.calendar = {
      '2026-09-06': 'Holiday',
      '2026-09-09': 'Present',
      '2026-09-13': 'Holiday',
    };
    expect(await provider.fetchHolidays('Multimax 2026'),
        {'2026-09-06', '2026-09-13'});
    final year = DateTime.now().year;
    expect(api.calls.single.method, 'hrms.api.get_attendance_calendar_events');
    expect(api.calls.single.params,
        {'from_date': '$year-01-01', 'to_date': '$year-12-31'});
  });

  test('when the fallback fails too, the original error surfaces', () async {
    final err = _forbidden();
    api.holidayListError = err;
    await expectLater(
        provider.fetchHolidays('Multimax 2026'), throwsA(same(err)));
  });

  test('shift assignments: open-ended OR on end_date, rows parsed', () async {
    api.listRows = [
      {'employee': 'HR-EMP-00001', 'shift_type': 'Morning', 'start_date': '2026-09-12', 'end_date': null},
    ];
    final rows = await provider.fetchShiftAssignments(
        DateTime(2026, 9, 12), DateTime(2026, 9, 12), employee: 'HR-EMP-00001');
    expect(rows.single.shiftType, 'Morning');
    expect(rows.single.endDate, isNull);
    expect(rows.single.covers(DateTime(2027, 1, 1)), isTrue);
    expect(api.lastList!.doctype, 'Shift Assignment');
    expect(api.lastList!.filterTuples, containsAll([
      ['Shift Assignment', 'start_date', '<=', '2026-09-12'],
      ['Shift Assignment', 'employee', '=', 'HR-EMP-00001'],
    ]));
    expect(api.lastList!.orFilterTuples, [
      ['Shift Assignment', 'end_date', '>=', '2026-09-12'],
      ['Shift Assignment', 'end_date', 'is', 'not set'],
    ]);
  });

  test('shift types keyed by name; nothing to fetch, no request', () async {
    api.listRows = [
      {'name': 'Morning', 'start_time': '8:00:00', 'end_time': '12:15:00',
       'allow_check_out_after_shift_end_time': 45},
    ];
    final m = await provider.fetchShiftTypes(['Morning', '']);
    expect(m['Morning']!.checkOutAfterMinutes, 45);
    expect(m['Morning']!.startLabel, '08:00');
    expect(api.lastList!.filters, {'name': ['in', ['Morning']]});
    api.lastList = null;
    expect(await provider.fetchShiftTypes(const []), isEmpty);
    expect(api.lastList, isNull);
  });

  group('clocked-hours fields', () {
    test('read when the site has them, parsed into ShiftRules and the record', () async {
      api.rowsByDoctype = {
        'Shift Type': [
          {'name': 'Standard', 'start_time': '8:00:00', 'end_time': '20:00:00',
           'custom_expected_hours': 10, 'custom_break_start': '12:15:00',
           'custom_break_end': '13:30:00', 'custom_break_start_friday': '12:00:00',
           'custom_break_end_friday': '14:30:00'},
        ],
        'Attendance': [
          {'name': 'A', 'employee': 'E', 'attendance_date': '2026-11-30', 'status': 'Present',
           'custom_punch_count': 3, 'custom_missing_punch': 1, 'custom_net_hours': 4.25,
           'custom_expected_hours': 10, 'custom_shortfall_hours': 5.75},
        ],
      };
      final st = (await provider.fetchShiftTypes(['Standard']))['Standard']!;
      expect(st.isClocked, isTrue);
      expect(st.breakLabelOn(DateTime(2026, 12, 4)), '12:00–14:30');
      expect(api.listCalls.last.fields, containsAll(AttendanceProvider.kShiftTypeClockedFields));

      final rec = (await provider.fetchAttendance(DateTime(2026, 11, 30), DateTime(2026, 11, 30))).single;
      expect((rec.isClocked, rec.missingPunch, rec.shortfallHours), (true, true, 5.75));
      expect(api.listCalls.last.fields, containsAll(AttendanceProvider.kAttendanceClockedFields));
      expect(provider.clockedFieldsAvailable('Attendance'), isTrue);
    });

    test('a site without them: retried with the old fields, then not asked again', () async {
      api.rejectCustomFields = true;
      api.rowsByDoctype = {
        'Attendance': [
          {'name': 'A', 'employee': 'E', 'attendance_date': '2026-11-20', 'status': 'Present',
           'shift': 'Morning', 'working_hours': 4},
        ],
        'Shift Type': [
          {'name': 'Morning', 'start_time': '8:00:00', 'end_time': '12:15:00'},
        ],
      };
      final recs = await provider.fetchAttendance(DateTime(2026, 11, 20), DateTime(2026, 11, 20));
      expect(recs.single.workingHours, 4);
      expect(recs.single.isClocked, isFalse);
      expect(api.listCalls.map((c) => c.doctype), ['Attendance', 'Attendance']);
      expect(api.listCalls.last.fields!.any((f) => f.startsWith('custom_')), isFalse);
      expect(provider.clockedFieldsAvailable('Attendance'), isFalse);

      await provider.fetchAttendance(DateTime(2026, 11, 21), DateTime(2026, 11, 21));
      expect(api.listCalls.length, 3); // remembered: one request, no custom fields
      expect(api.listCalls.last.fields!.any((f) => f.startsWith('custom_')), isFalse);

      final st = await provider.fetchShiftTypes(['Morning']);
      expect(st['Morning']!.isClocked, isFalse);
    });

    test('a connection error is not mistaken for missing fields', () async {
      final req = RequestOptions(path: '/api/resource/Attendance');
      api.listErrors = {
        'Attendance': DioException(requestOptions: req, type: DioExceptionType.connectionError),
      };
      await expectLater(provider.fetchAttendance(DateTime(2026, 11, 20), DateTime(2026, 11, 20)),
          throwsA(isA<DioException>()));
      expect(api.listCalls.length, 1);
      expect(provider.clockedFieldsAvailable('Attendance'), isNull);
    });

    test('employees carry their company', () async {
      api.rowsByDoctype = {
        'Employee': [
          {'name': 'E', 'employee_name': 'x', 'default_shift': 'Late Start', 'company': 'Multimax'},
        ],
      };
      final e = (await provider.fetchActiveEmployees()).single;
      expect((e.defaultShift, e.company), ('Late Start', 'Multimax'));
      expect(api.listCalls.last.fields, contains('company'));
    });
  });

  group('holidays with no Holiday List on the shift', () {
    test('HR roles: the company assignments decide, each until the next starts', () async {
      api.rowsByDoctype = {
        'Holiday List Assignment': [
          {'holiday_list': 'Multimax 2026', 'from_date': '2026-01-01'},
          {'holiday_list': 'Multimax 2027', 'from_date': '2027-01-01'},
        ],
      };
      api.holidayLists = {
        'Multimax 2026': {
          'holidays': [
            {'holiday_date': '2026-12-27'},
            {'holiday_date': '2027-01-03'}, // a stray row past its own period
          ],
        },
        'Multimax 2027': {
          'holidays': [
            {'holiday_date': '2027-01-03'},
            {'holiday_date': '2027-01-10'},
          ],
        },
      };
      final h = await provider.fetchHolidays('',
          from: DateTime(2026, 12, 1), to: DateTime(2027, 1, 5), company: 'Multimax');
      expect(h, {'2026-12-27', '2027-01-03'});
      expect(api.lastList!.doctype, 'Holiday List Assignment');
      expect(api.lastList!.filterTuples, containsAll([
        ['Holiday List Assignment', 'docstatus', '=', 1],
        ['Holiday List Assignment', 'applicable_for', '=', 'Company'],
        ['Holiday List Assignment', 'assigned_to', '=', 'Multimax'],
        ['Holiday List Assignment', 'from_date', '<=', '2027-01-05'],
      ]));
      expect(api.calls, isEmpty);
    });

    test('no assignment: no holidays, no error', () async {
      api.rowsByDoctype = {'Holiday List Assignment': const []};
      expect(await provider.fetchHolidays(''), isEmpty);
      expect(api.docCalls, isEmpty);
    });

    test('Employee role: assignments unreadable → own calendar for the range', () async {
      api.listErrors = {'Holiday List Assignment': _forbidden()};
      api.calendar = {'2026-12-06': 'Holiday', '2026-12-07': 'Present'};
      final h = await provider.fetchHolidays('',
          from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 31));
      expect(h, {'2026-12-06'});
      expect(api.calls.single.params, {'from_date': '2026-12-01', 'to_date': '2026-12-31'});
    });

    test('holidayListPeriods: clipped to the range, nothing before the first', () {
      final p = holidayListPeriods([
        (list: 'B', from: DateTime(2027, 1, 1)),
        (list: 'A', from: DateTime(2026, 1, 1)),
      ], DateTime(2025, 12, 20), DateTime(2027, 1, 31));
      expect(p.map((e) => (e.list, kFrappeDate.format(e.from), kFrappeDate.format(e.to))), [
        ('A', '2026-01-01', '2026-12-31'),
        ('B', '2027-01-01', '2027-01-31'),
      ]);
      expect(holidayListPeriods([(list: 'B', from: DateTime(2027, 1, 1))],
          DateTime(2026, 12, 1), DateTime(2026, 12, 31)), isEmpty);
    });
  });
}
