import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/attendance_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';

// AttendanceProvider.fetchHolidays: HR roles read the Holiday List; the
// Employee role gets 403 there, so holidays come from HRMS's self-service
// calendar instead (weekly offs included).

class _FakeApi extends ApiProvider {
  Object? holidayListError;
  Map<String, dynamic> holidayListDoc = const {};

  /// Calendar events returned by callMethod; null makes callMethod throw.
  Map<String, dynamic>? calendar;
  final calls = <({String method, Map<String, dynamic>? params})>[];

  @override
  Future<Response> getDocument(String doctype, String name) async {
    if (holidayListError != null) throw holidayListError!;
    return Response(
      requestOptions: RequestOptions(path: '/api/resource/$doctype/$name'),
      statusCode: 200,
      data: {'data': holidayListDoc},
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
}
