import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/link_title_cache.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_controller.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_screen.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_controller.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_screen.dart';

/// Answers `getReport` from a canned response (or error) and records calls.
class _FakeApi extends ApiProvider {
  Object? message;
  Object? error;
  final calls = <({String report, Map<String, dynamic>? filters})>[];

  @override
  Future<Response> getReport(
    String reportName, {
    Map<String, dynamic>? filters,
  }) async {
    calls.add((report: reportName, filters: filters));
    if (error != null) throw error!;
    return Response(
      requestOptions: RequestOptions(
        path: '/api/method/frappe.desk.query_report.run',
      ),
      statusCode: 200,
      data: {'message': message},
    );
  }
}

class _FakeStorage extends StorageService {
  _FakeStorage() : super.withStorage(null);

  @override
  String? getBaseUrl() => null;

  @override
  String getCompany() => 'Multimax';
}

const _shiftMessage = {
  'columns': [],
  'result': [
    {
      'name': 'HR-ATT-1',
      'employee': 'HR-EMP-1',
      'employee_name': 'Test Person One',
      'shift': 'Morning',
      'attendance_date': '2026-11-14',
      'status': 'Present',
      'in_time': '08:20:10',
      'out_time': '12:15:00',
      'working_hours': 3.92,
      'late_entry': 1,
      'early_exit': 0,
      'late_entry_hrs': '5m 10s',
      'shift_start': '08:00:00',
      'shift_end': '12:15:00',
    },
    {
      'name': 'HR-ATT-2',
      'employee': 'HR-EMP-2',
      'employee_name': 'Test Person Two',
      'shift': 'Afternoon',
      'attendance_date': '2026-11-13',
      'status': 'Present',
      'in_time': '13:30:00',
      'out_time': null,
      'working_hours': 0.0,
      'late_entry': 0,
      'early_exit': 0,
      'shift_start': '13:30:00',
      'shift_end': '20:00:00',
    },
  ],
  'report_summary': [
    {
      'value': 2,
      'indicator': 'Green',
      'label': 'Present Records',
      'datatype': 'Int',
    },
    {
      'value': 1,
      'indicator': 'Red',
      'label': 'Late Entries',
      'datatype': 'Int',
    },
  ],
};

DioException _forbiddenTimesheet() {
  final options = RequestOptions(
    path: '/api/method/frappe.desk.query_report.run',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: 403,
      data: {
        'exception':
            "frappe.exceptions.PermissionError: You don't have permission to get a report on: Timesheet",
        '_server_messages': jsonEncode([
          jsonEncode({
            'message':
                "You don't have permission to get a report on: Timesheet",
          }),
        ]),
      },
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeApi api;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => r'C:\temp\test_cookies',
        );
  });

  setUp(() {
    Get.testMode = true;
    api = _FakeApi();
    Get.put<StorageService>(_FakeStorage());
    Get.put<ApiProvider>(api);
    Get.put(PermissionService());
    Get.put(AuthenticationController());
  });
  tearDown(Get.reset);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Shift Attendance runs on open and renders the result '
        '(${mode.name})', (tester) async {
      _phone(tester);
      api.message = _shiftMessage;
      Get.put(ShiftAttendanceController());

      await tester.pumpWidget(
        GetMaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: const ShiftAttendanceScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final call = api.calls.single;
      expect(call.report, 'Shift Attendance');
      final (from, to) = ReportPeriod.thisMonth.rangeFor(DateTime.now());
      expect(call.filters, {
        'company': 'Multimax',
        'from_date': kReportDate.format(from),
        'to_date': kReportDate.format(to),
        'consider_grace_period': 1,
        'include_attendance_without_checkins': 0,
      });

      // Server summary, day headings (newest first), cards.
      expect(find.text('Present Records'), findsOneWidget);
      expect(find.text('SAT 14 NOV 2026'), findsOneWidget);
      expect(find.text('FRI 13 NOV 2026'), findsOneWidget);
      expect(find.text('Test Person One'), findsOneWidget);
      expect(find.text('late 5m 10s'), findsOneWidget);
      expect(find.text('No check-out'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // End-of-list totals: hours summed, flags counted.
      expect(
        find.text(
          '2 records · 2 employees · 3h 55m worked · 1 late · '
          '1 missing a punch',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('Shift Attendance preset re-runs with the preset dates', (
    tester,
  ) async {
    _phone(tester);
    api.message = _shiftMessage;
    Get.put(ShiftAttendanceController());
    await tester.pumpWidget(
      const GetMaterialApp(home: ShiftAttendanceScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();

    final (day, _) = ReportPeriod.yesterday.rangeFor(DateTime.now());
    expect(api.calls, hasLength(2));
    expect(api.calls.last.filters!['from_date'], kReportDate.format(day));
    expect(api.calls.last.filters!['to_date'], kReportDate.format(day));
  });

  test(
    'the Employee filter chip reads the employee name, sends the ID',
    () async {
      LinkTitleCache.clear();
      LinkTitleCache.remember('Employee', const [
        LinkOption(name: 'HR-EMP-1', title: 'Test Person One'),
      ]);
      api.message = _shiftMessage;
      final controller = ShiftAttendanceController()..onInit();
      controller.employeeController.text = 'HR-EMP-1';
      await controller.runReport();
      expect(controller.activeFilters['employee'], 'Employee: Test Person One');
      expect(api.calls.last.filters!['employee'], 'HR-EMP-1');
    },
  );

  testWidgets('Employee Hours shows the server permission error', (
    tester,
  ) async {
    _phone(tester);
    api.error = _forbiddenTimesheet();
    Get.put(EmployeeHoursUtilizationController());
    await tester.pumpWidget(
      const GetMaterialApp(home: EmployeeHoursUtilizationScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      api.calls.single.report,
      'Employee Hours Utilization Based On Timesheet',
    );
    expect(
      find.text("You don't have permission to get a report on: Timesheet"),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Employee Hours renders rows and sums only hour columns', (
    tester,
  ) async {
    _phone(tester);
    api.message = {
      'result': [
        {
          'employee': 'HR-EMP-1',
          'employee_name': 'Test Person One',
          'total_hours': 100.0,
          'billed_hours': 50.0,
          'non_billed_hours': 25.0,
          'untracked_hours': 25.0,
          'per_util': 75.0,
          'per_util_billed_only': 50.0,
        },
      ],
      'report_summary': [
        {'value': '75.0%', 'indicator': 'Green', 'label': 'Avg Utilization'},
      ],
    };
    Get.put(EmployeeHoursUtilizationController());
    await tester.pumpWidget(
      const GetMaterialApp(home: EmployeeHoursUtilizationScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Avg Utilization'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(
      find.text(
        '1 employee · 50h billed · 25h non-billed · 25h untracked · '
        'of 100h',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('Employee Hours refuses a range the server would reject', () {
    final controller = EmployeeHoursUtilizationController()..onInit();
    controller.fromDateController.text = '2026-11-15';
    controller.toDateController.text = '2026-11-15';
    expect(
      controller.validate(controller.buildFilters()),
      startsWith('From Date must come before To Date'),
    );
    controller.toDateController.text = '2026-11-16';
    expect(controller.validate(controller.buildFilters()), isNull);
  });
}
