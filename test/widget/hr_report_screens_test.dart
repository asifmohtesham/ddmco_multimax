import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/link_title_cache.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/hr/attendance/month/attendance_month_screen.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_widgets.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_controller.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_screen.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/widgets/utilization_card.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_controller.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_screen.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/widgets/attendance_sheet_cards.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_controller.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_screen.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/widgets/shift_attendance_card.dart';

import '../support/report_fields_test_kit.dart';

/// Answers `getReport` from a canned response (or error) and records calls.
class _FakeApi extends ApiProvider {
  Object? message;
  Object? error;
  Future<void> Function()? beforeReport;
  final calls = <({String report, Map<String, dynamic>? filters})>[];

  @override
  Future<Response> getReport(
    String reportName, {
    Map<String, dynamic>? filters,
  }) async {
    calls.add((report: reportName, filters: filters));
    final reply = message;
    final failure = error;
    await beforeReport?.call();
    if (failure != null) throw failure;
    return Response(
      requestOptions: RequestOptions(
        path: '/api/method/frappe.desk.query_report.run',
      ),
      statusCode: 200,
      data: {'message': reply},
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

class _FieldsDatabase extends DatabaseService {
  final values = <String, String>{};

  @override
  Future<String?> getConfig(String key) async => values[key];

  @override
  Future<void> saveConfig(String key, String value) async {
    values[key] = value;
  }
}

class _FieldsOwner implements ReportOwnerSource {
  FieldsScope scope = (site: 'https://a.example', user: 'reader@example.com');
  final listeners = <VoidCallback>{};

  @override
  Future<FieldsOwner> resolve() async => (scope: scope, rawUser: scope.user);

  @override
  Unsubscribe watch(VoidCallback listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void switchTo(FieldsScope next) {
    scope = next;
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}

const _shiftDetails = {
  'shift_start': 'Shift Start Time',
  'shift_end': 'Shift End Time',
  'in_time': 'In Time',
  'out_time': 'Out Time',
  'working_hours': 'Total Working Hours',
  'late_entry_hrs': 'Late Entry By',
  'early_exit_hrs': 'Early Exit By',
};

const _utilizationDetails = {
  'department': 'Department',
  'per_util_billed_only': '% Utilization (B / T)',
  'billed_hours': 'Billed Hours (B)',
  'non_billed_hours': 'Non-Billed Hours (NB)',
  'untracked_hours': 'Untracked Hours (U)',
  'total_hours': 'Total Hours (T)',
};

List<Map<String, String>> _columns(Map<String, String> headers) => [
  for (final entry in headers.entries)
    {'fieldname': entry.key, 'label': entry.value},
];

final _shiftMessage = {
  'columns': _columns(const {
    'employee': 'Employee',
    'employee_name': 'Employee Name',
    'shift': 'Shift',
    'attendance_date': 'Attendance Date',
    'status': 'Status',
    ..._shiftDetails,
  }),
  'result': const [
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
  'report_summary': const [
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

DioException _reportException(int statusCode, Map<String, Object> data) {
  final options = RequestOptions(
    path: '/api/method/frappe.desk.query_report.run',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: statusCode,
      data: data,
    ),
  );
}

DioException _forbiddenTimesheet() => _reportException(403, {
  'exception':
      "frappe.exceptions.PermissionError: You don't have permission to get a report on: Timesheet",
  '_server_messages': jsonEncode([
    jsonEncode({
      'message': "You don't have permission to get a report on: Timesheet",
    }),
  ]),
});

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _openFields(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Fields'));
  await tester.pumpAndSettle();
}

Future<Finder> _fieldTile(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey(key));
  final scrollable = find.descendant(
    of: find.byType(DraggableScrollableSheet),
    matching: find.byType(Scrollable),
  );
  if (tile.evaluate().isEmpty) {
    await tester.scrollUntilVisible(tile, 100, scrollable: scrollable.last);
  }
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  return tile;
}

Future<void> _closeFields(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Reset to defaults'))).pop();
  await tester.pumpAndSettle();
}

Finder _cardFor<T extends Widget>(String employee) =>
    find.ancestor(of: find.text(employee), matching: find.byType(T));

Finder _in(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);

Future<void> _toggleField(WidgetTester tester, String key) async {
  await _openFields(tester);
  await tester.tap(await _fieldTile(tester, key));
  await tester.pumpAndSettle();
  await _closeFields(tester);
}

Future<void> _expectFooter(WidgetTester tester, String label) async {
  final footer = find.byType(ListEndFooter);
  final scroll = _in(find.byType(CustomScrollView), find.byType(Scrollable));
  await tester.scrollUntilVisible(footer, 220, scrollable: scroll.first);
  await tester.pumpAndSettle();
  expect(tester.widget<ListEndFooter>(footer).label, label);
  expect(_in(footer, find.text(label)).hitTestable(), findsOneWidget);
}

Future<void> _expectSummary(
  WidgetTester tester,
  Map<String, String> labelValues,
) async {
  final strip = find.byType(ReportSummaryStrip);
  expect(strip, findsOneWidget);
  for (final MapEntry(:key, :value) in labelValues.entries) {
    final caption = _in(strip, find.text(key));
    await tester.ensureVisible(caption);
    await tester.pumpAndSettle();
    final tile = find
        .ancestor(of: caption, matching: find.byType(Column))
        .first;
    expect(caption.hitTestable(), findsOneWidget);
    expect(_in(tile, find.text(value)).hitTestable(), findsOneWidget);
  }
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
      api.message = {..._shiftMessage, 'columns': const []};
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
      expect(find.text('Late Entry By 5m 10s'), findsOneWidget);
      expect(find.text('No check-out'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // End-of-list totals: hours summed, flags counted.
      await tester.scrollUntilVisible(
        find.byType(ListEndFooter),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text(
          'End of list · 2 records · 2 employees · Total Working Hours '
          '3h 55m · 1 late · '
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
      final owner = Get.put<ReportOwnerSource>(_FieldsOwner()) as _FieldsOwner;
      LinkTitleCache.remember('Employee', const [
        LinkOption(name: 'HR-EMP-1', title: 'Test Person One'),
      ], scope: owner.scope);
      api.message = _shiftMessage;
      final controller = ShiftAttendanceController()..onInit();
      addTearDown(controller.onClose);
      await controller.fields.bind();
      controller.employeeController.text = 'HR-EMP-1';
      await controller.runReport();
      expect(controller.activeFilters['employee'], 'Employee: Test Person One');
      expect(api.calls.last.filters!['employee'], 'HR-EMP-1');
    },
  );

  testWidgets('Employee Hours shows a plain permission error', (tester) async {
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
      find.text(
        "You don't have permission to run Employee Hours Utilization "
        'Based On Timesheet. Ask your administrator.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('get a report on:'), findsNothing);
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
        'End of list · 1 employee · Billed Hours (B) 50h · '
        'Non-Billed Hours (NB) 25h · Untracked Hours (U) 25h · '
        'Total Hours (T) 100h',
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

void registerHrReportFieldsTests() {
  group('HR report Fields', () {
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
      Get.put<StorageService>(_FakeStorage(), permanent: true);
      Get.put<ApiProvider>(api, permanent: true);
      Get.put(PermissionService(), permanent: true);
      Get.put(AuthenticationController(), permanent: true);
    });
    tearDown(Get.reset);

    testWidgets('Employee Hours Fields persist per site and user', (
      tester,
    ) async {
      _phone(tester);
      final database = _FieldsDatabase();
      final owner = Get.put<ReportOwnerSource>(_FieldsOwner()) as _FieldsOwner;
      final initialOwner = owner.scope;
      final otherUser = (
        site: initialOwner.site,
        user: 'someone-else@example.com',
      );

      void registerStore() {
        Get.put<ReportFieldsStore>(
          ScopedReportFieldsStore(
            database: database,
            storage: Get.find<StorageService>(),
          ),
        );
      }

      Future<void> mount() async {
        Get.put(EmployeeHoursUtilizationController());
        await tester.pumpWidget(
          const GetMaterialApp(home: EmployeeHoursUtilizationScreen()),
        );
        await tester.pumpAndSettle();
      }

      api.message = {
        'columns': _columns({
          'employee': 'Employee',
          'per_util': '% Utilization (B + NB) / T',
          ..._utilizationDetails,
          'total_hours': 'Available Work Hours',
        }),
        'result': const [
          {
            'employee': 'E-1',
            'employee_name': 'Employee One',
            'department': 'Workshop',
            'total_hours': 10,
            'billed_hours': 12,
            'non_billed_hours': 2,
            'untracked_hours': 0,
            'per_util': 140,
            'per_util_billed_only': 120,
          },
          {'employee': 'E-2', 'employee_name': 'Employee Two'},
        ],
        'report_summary': const [
          {'label': 'Avg Utilization', 'value': '70%'},
          {'label': 'Avg Utilization (Billed Only)', 'value': '60%'},
          {'label': 'Total Billed Hours', 'value': 12},
          {'label': 'Total Non-Billed Hours', 'value': 2},
        ],
      };
      registerStore();
      await mount();
      expect(find.text('E-1 · Workshop'), findsOneWidget);
      expect(find.text('140%'), findsOneWidget);
      final card = _cardFor<UtilizationCard>('Employee One');
      final bar = _in(card, find.byType(ClipRRect));
      const hourLabels = {
        'billed_hours': 'Billed Hours (B)',
        'non_billed_hours': 'Non-Billed Hours (NB)',
        'untracked_hours': 'Untracked Hours (U)',
        'total_hours': 'Available Work Hours',
      };
      expect(bar, findsOneWidget);
      for (final key in hourLabels.keys) {
        await _toggleField(tester, key);
        for (final entry in hourLabels.entries) {
          expect(
            _in(card, find.text('${entry.value} ')),
            entry.key == key ? findsNothing : findsOneWidget,
          );
        }
        expect(bar, findsNothing);
        await _toggleField(tester, key);
        expect(_in(card, find.text('${hourLabels[key]} ')), findsOneWidget);
        expect(bar, findsOneWidget);
      }

      await _openFields(tester);
      for (final entry in _utilizationDetails.entries) {
        final tile = await _fieldTile(tester, entry.key);
        expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
        final label = entry.key == 'total_hours'
            ? 'Available Work Hours'
            : entry.value;
        expect(
          find.descendant(of: tile, matching: find.text(label)),
          findsOneWidget,
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      await _closeFields(tester);
      expect(api.calls, hasLength(1));
      expect(find.text('Employee One'), findsOneWidget);
      expect(find.text('Employee Two'), findsOneWidget);
      expect(find.text('140%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('E-1 · Workshop'), findsNothing);
      expect(find.text('% Utilization (B / T) 120%'), findsNothing);
      for (final label in hourLabels.values) {
        expect(_in(card, find.text('$label ')), findsNothing);
      }
      expect(bar, findsNothing);
      expect(
        tester.getSemantics(_in(card, find.text('140%'))).label,
        contains('% Utilization (B + NB) / T 140%, At or above target'),
      );
      expect(
        tester
            .getSemantics(
              _in(_cardFor<UtilizationCard>('Employee Two'), find.text('0%')),
            )
            .label,
        contains('% Utilization (B + NB) / T 0%, Below target'),
      );
      await _expectSummary(tester, const {
        'Avg Utilization': '70%',
        'Avg Utilization (Billed Only)': '60%',
        'Total Billed Hours': '12',
        'Total Non-Billed Hours': '2',
      });
      await _expectFooter(
        tester,
        'End of list · 2 employees · Billed Hours (B) '
        '12h · Non-Billed Hours (NB) 2h · Untracked Hours (U) 0h · '
        'Available Work Hours 10h',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await Get.delete<EmployeeHoursUtilizationController>(force: true);
      await Get.delete<ReportFieldsStore>(force: true);
      registerStore();
      await mount();
      expect(find.text('E-1 · Workshop'), findsNothing);
      await _openFields(tester);
      for (final scope in [
        otherUser,
        (site: 'https://b.example', user: initialOwner.user),
        initialOwner,
      ]) {
        owner.switchTo(scope);
        await tester.pumpAndSettle();
        final controller = Get.find<EmployeeHoursUtilizationController>();
        expect(controller.reportColumns, isEmpty);
        expect(find.text('Employee One', skipOffstage: false), findsNothing);
        expect(find.text('Avg Utilization', skipOffstage: false), findsNothing);
        expect(find.byType(ListEndFooter, skipOffstage: false), findsNothing);
        final tile = await _fieldTile(tester, 'department');
        expect(
          tester.widget<CheckboxListTile>(tile).value,
          scope != initialOwner,
        );
        if (scope == otherUser) {
          await tester.tap(tile);
          await tester.pumpAndSettle();
        }
        await controller.runReport();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      final tile = await _fieldTile(tester, 'department');
      expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
      await _closeFields(tester);
      expect(find.text('E-1 · Workshop'), findsOneWidget);
      expect(
        database.values,
        containsPair(
          ScopedReportFieldsStore.configKey(
            'employee_hours_utilization',
            initialOwner,
          ),
          '{}',
        ),
      );
      final userControl = ScopedReportFieldsStore.configKey(
        'employee_hours_utilization',
        otherUser,
      );
      expect(database.values[userControl], '{"department":false}');
      expect(api.calls, hasLength(5));
      await tester.pumpWidget(const SizedBox.shrink());
      await Get.delete<EmployeeHoursUtilizationController>(force: true);
      await Get.delete<ReportFieldsStore>(force: true);
      registerStore();
      await mount();
      expect(find.text('E-1 · Workshop'), findsOneWidget);
      for (final label in hourLabels.values) {
        expect(_in(card, find.text('$label ')), findsOneWidget);
      }
      expect(bar, findsOneWidget);
      expect(database.values[userControl], '{"department":false}');
      expect(api.calls, hasLength(6));
    });

    testWidgets(
      'Shift and Monthly choices persist separately by report and owner',
      (tester) async {
        _phone(tester);
        final database = _FieldsDatabase();
        final owner =
            Get.put<ReportOwnerSource>(_FieldsOwner()) as _FieldsOwner;
        final first = owner.scope;
        final otherUser = (site: first.site, user: 'other@example.com');
        final otherSite = (site: 'https://b.example', user: first.user);
        const shiftId = 'shift_attendance';
        const monthlyId = 'monthly_attendance_sheet';
        const details = {
          shiftId: {'in_time': '08:20', 'out_time': '12:15'},
          monthlyId: {
            'sick_leave': 'Sick Leave 1',
            'total_present': 'Total Present 3',
          },
        };
        final defaultMonthly = {
          'columns': [
            ..._columns(const {
              'employee': 'Employee',
              'total_present': 'Total Present',
            }),
            const {
              'fieldname': 'sick_leave',
              'label': 'Sick Leave',
              'fieldtype': 'Float',
            },
          ],
          'result': const [
            {
              'employee': 'E-1',
              'employee_name': 'Employee One',
              'total_present': 3,
              'sick_leave': 1,
            },
          ],
        };

        Future<void> mount(String report, {bool omitSickLeave = false}) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await Get.delete<ShiftAttendanceController>(force: true);
          await Get.delete<MonthlyAttendanceSheetController>(force: true);
          await Get.delete<ReportFieldsStore>(force: true);
          Get.put<ReportFieldsStore>(
            ScopedReportFieldsStore(
              database: database,
              storage: Get.find<StorageService>(),
            ),
          );
          if (report == shiftId) {
            api.message = _shiftMessage;
            Get.put(ShiftAttendanceController());
          } else {
            api.message = omitSickLeave
                ? {
                    'columns': _columns(const {
                      'total_present': 'Total Present',
                    }),
                    'result': const [
                      {
                        'employee': 'E-1',
                        'employee_name': 'Employee One',
                        'total_present': 3,
                      },
                    ],
                  }
                : defaultMonthly;
            Get.put(
              MonthlyAttendanceSheetController(),
            ).summarizedController.text = '1';
          }
          await tester.pumpWidget(
            GetMaterialApp(
              home: report == shiftId
                  ? const ShiftAttendanceScreen()
                  : const MonthlyAttendanceSheetScreen(),
            ),
          );
          await tester.pumpAndSettle();
        }

        void expectChoices(String report, Set<String> hidden) {
          final card = report == shiftId
              ? _cardFor<ShiftAttendanceCard>('Test Person One')
              : _cardFor<SheetSummaryCard>('Employee One');
          expect(card, findsOneWidget);
          for (final entry in details[report]!.entries) {
            expect(
              _in(card, find.text(entry.value)),
              hidden.contains(entry.key) ? findsNothing : findsOneWidget,
            );
          }
        }

        String key(String report, FieldsScope scope) =>
            ScopedReportFieldsStore.configKey(report, scope);

        final edits = {
          first: {shiftId: 'in_time', monthlyId: 'sick_leave'},
          otherUser: {shiftId: 'out_time', monthlyId: 'total_present'},
          otherSite: {shiftId: 'out_time', monthlyId: 'sick_leave'},
        };
        for (final ownerEdits in edits.entries) {
          owner.switchTo(ownerEdits.key);
          for (final edit in ownerEdits.value.entries) {
            await mount(edit.key);
            expectChoices(edit.key, {});
            await _toggleField(tester, edit.value);
            expectChoices(edit.key, {edit.value});
            expect(
              database.values[key(edit.key, ownerEdits.key)],
              jsonEncode({edit.value: false}),
            );
          }
        }

        owner.switchTo(first);
        final editedBytes = Map.of(database.values);
        for (final report in [shiftId, monthlyId]) {
          await mount(report);
          expectChoices(report, {edits[first]![report]!});
          if (report == monthlyId) await mount(report, omitSickLeave: true);
          await _openFields(tester);
          if (report == monthlyId) {
            expect(find.byKey(const ValueKey('sick_leave')), findsNothing);
          }
          await tester.tap(find.text('Reset to defaults'));
          await tester.pumpAndSettle();
          expect(find.text('Reset to defaults'), findsOneWidget);
          expect(database.values, editedBytes..[key(report, first)] = '{}');
          await _closeFields(tester);
          await mount(report);
          expectChoices(report, {});
        }
        for (final scope in [otherUser, otherSite, first]) {
          owner.switchTo(scope);
          for (final report in [shiftId, monthlyId]) {
            await mount(report);
            expectChoices(
              report,
              scope == first ? {} : {edits[scope]![report]!},
            );
          }
        }
      },
    );

    testWidgets(
      'a superseded HR run cannot clear the new owner loading state',
      (tester) async {
        _phone(tester);
        final owner =
            Get.put<ReportOwnerSource>(_FieldsOwner()) as _FieldsOwner;
        api.message = _shiftMessage;
        final a = Completer<void>();
        final b = Completer<void>();
        final waits = [a.future, b.future];
        api.beforeReport = () => waits.removeAt(0);
        final controller = Get.put(ShiftAttendanceController());
        await tester.pumpWidget(
          const GetMaterialApp(home: ShiftAttendanceScreen()),
        );
        await tester.pump();
        expect(controller.isRunning.value, isTrue);

        owner.switchTo((site: 'https://b.example', user: owner.scope.user));
        await tester.pump();
        expect(controller.isRunning.value, isFalse);
        final next = controller.runReport();
        await tester.pump();
        a.complete();
        await tester.pump();
        expect(controller.isRunning.value, isTrue);
        expect(controller.rows, isEmpty);
        expect(controller.summary, isEmpty);
        expect(controller.hasRun.value, isFalse);
        b.complete();
        await next;
        await tester.pumpAndSettle();
        expect(find.text('Test Person One'), findsOneWidget);
        expect(controller.isRunning.value, isFalse);
      },
    );

    for (final shift in [false, true]) {
      testWidgets('${shift ? 'Shift Attendance' : 'Employee Hours'} keeps the '
          'same partly covered employee occurrence after toggle and reset', (
        tester,
      ) async {
        _phone(tester);
        final owner = ReportFieldsTestOwner();
        final driver = WidgetReportFieldsDriver(tester, owner);
        api.message = shift
            ? {
                'columns': _shiftMessage['columns'],
                'result': [
                  for (var i = 0; i < 14; i++)
                    {
                      'name': 'ATT-$i',
                      'employee': 'E-$i',
                      'employee_name': 'Employee $i',
                      'attendance_date': '2026-11-14',
                      'status': 'Present',
                      'in_time': '08:00:00',
                      'out_time': '12:00:00',
                      'working_hours': 4,
                    },
                ],
              }
            : {
                'columns': _columns(_utilizationDetails),
                'result': [
                  for (var i = 0; i < 14; i++)
                    {
                      'employee': 'E-$i',
                      'employee_name': 'Employee $i',
                      'department': 'Workshop',
                      'total_hours': 10,
                      'billed_hours': 4,
                      'non_billed_hours': 2,
                      'untracked_hours': 4,
                    },
                ],
              };
        if (shift) {
          Get.put(ShiftAttendanceController());
        } else {
          Get.put(EmployeeHoursUtilizationController());
        }
        await tester.pumpWidget(
          GetMaterialApp(
            home: shift
                ? const ShiftAttendanceScreen()
                : const EmployeeHoursUtilizationScreen(),
          ),
        );
        await tester.pumpAndSettle();
        final id = (shift ? 'ATT-1' : 'E-1', 1);
        await driver.positionOccurrenceUnderHeader(id);
        expect(
          find.descendant(
            of: find.byKey(ValueKey<Object>(id)),
            matching: find.text('Employee 1'),
          ),
          findsOneWidget,
        );
        await driver.openFields();
        for (final key
            in shift
                ? ['in_time', 'out_time', 'working_hours']
                : [
                    'billed_hours',
                    'non_billed_hours',
                    'untracked_hours',
                    'total_hours',
                  ]) {
          await driver.setVisible(key, false);
        }
        await driver.dismiss();
        expect(driver.readPaintedOffset(id), closeTo(-5, 1));
        await driver.openFields();
        await driver.reset();
        await driver.dismiss();
        expect(driver.readPaintedOffset(id), closeTo(-5, 1));
        expect(api.calls, hasLength(1));
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('Monthly Attendance preserves the expanded Evening offset '
          'and readable headings and holiday counts (${brightness.name})', (
        tester,
      ) async {
        _phone(tester);
        final owner = ReportFieldsTestOwner()
          ..change('https://hr.example', 'reader');
        Get.put<ReportOwnerSource>(owner);
        final driver = WidgetReportFieldsDriver(tester, owner);
        final controller = Get.put(MonthlyAttendanceSheetController());
        api.message = {
          'columns': _columns(const {
            'employee': 'Employee',
            'employee_name': 'Employee Name',
            'shift': 'Shift',
            'department': 'Department',
            '01-09-2026': '1 Tue',
            '02-09-2026': '2 Wed',
          }),
          'result': [
            ['', '', '', 'Workshop', '', ''],
            ['E-1', 'Employee One', 'Morning', 'H', 'H', 'WO'],
            ['E-1', 'Employee One', 'Evening', '', 'H', 'WO'],
            for (var i = 2; i < 14; i++)
              ['E-$i', 'Employee $i', 'Morning', '', 'P', 'P'],
          ],
        };
        controller.groupByController.text = 'Department';
        await tester.pumpWidget(
          GetMaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const MonthlyAttendanceSheetScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Employee One'));
        await tester.pumpAndSettle();
        final scheme = AppScheme.of(brightness);
        Color? ink(String text) =>
            tester.widget<Text>(find.text(text)).style?.color;
        expect(ink('WORKSHOP'), scheme.textMuted);
        expect(ink('Evening'), scheme.textMuted);
        expect(
          ink('H 1'),
          brightness == Brightness.dark ? AppColors.gray300 : AppColors.gray700,
        );
        expect(
          ink('WO 1'),
          brightness == Brightness.dark ? AppColors.gray300 : AppColors.gray700,
        );

        const id = (('employee', false, 'Workshop', 'E-1', 0), 'Evening', 1);
        await driver.positionOccurrenceUnderHeader(id);
        await driver.openFields();
        await driver.setVisible('shift', false);
        await driver.dismiss();
        expect(driver.readPaintedOffset(id), closeTo(-5, 1));
        await driver.openFields();
        await driver.reset();
        await driver.dismiss();
        expect(driver.readPaintedOffset(id), closeTo(-5, 1));
        expect(api.calls, hasLength(1));

        owner.change('https://hr.example', 'other');
        await tester.pumpAndSettle();
        expect(controller.reportColumns, isEmpty);
        expect(find.text('Employee One'), findsNothing);
        expect(find.text('Evening'), findsNothing);
        expect(find.byType(ListEndFooter), findsNothing);
      });
    }

    testWidgets('Shift Attendance Fields preserve warnings and raw totals', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const captions = {
        'shift_start': 'Schichtbeginn',
        'shift_end': 'Schichtende',
        'in_time': 'Kommen',
        'out_time': 'Gehen',
        'working_hours': 'Arbeitsstunden',
        'late_entry_hrs': 'Verspätet um',
        'early_exit_hrs': 'Früher gegangen um',
      };
      const summary = {
        'Present Records': '5',
        'Absent Records': '1',
        'Leave Records': '1',
        'Late Entries': '2',
        'Early Exits': '2',
      };
      const people = [
        ('Duration Warnings', 'Present', '08:20:10', '12:15:00'),
        ('Flag Warnings', 'Present', '08:10:00', '12:10:00'),
        ('Missing Both', 'Present', null, null),
        ('Missing Arrival', 'Present', null, '12:30:00'),
        ('Missing Departure', 'Present', '08:00:00', null),
        ('Excused Absent', 'Absent', null, null),
        ('Excused Leave', 'On Leave', null, null),
      ];
      api.message = {
        'columns': _columns(captions),
        'result': [
          for (final (i, (name, status, inTime, outTime)) in people.indexed)
            {
              'name': 'ATT-$i',
              'employee': 'E-$i',
              'employee_name': name,
              'shift': 'Morning',
              'attendance_date': '2026-11-14',
              'status': status,
              'shift_start': '08:00:00',
              'shift_end': '12:30:00',
              'in_time': inTime,
              'out_time': outTime,
              if (i == 0) ...{
                'working_hours': 3.92,
                'late_entry_hrs': '5m 10s',
                'early_exit_hrs': '15m',
              },
              if (i == 1) ...{
                'working_hours': 4,
                'late_entry': 1,
                'early_exit': 1,
              },
            },
        ],
        'report_summary': [
          for (final MapEntry(:key, :value) in summary.entries)
            {'label': key, 'value': value},
        ],
      };
      Get.put(ShiftAttendanceController());
      await tester.pumpWidget(
        const GetMaterialApp(home: ShiftAttendanceScreen()),
      );
      await tester.pumpAndSettle();

      final duration = _cardFor<ShiftAttendanceCard>('Duration Warnings');
      final flag = _cardFor<ShiftAttendanceCard>('Flag Warnings');
      const details = {
        'shift_start': 'Morning · 08:00–12:30',
        'shift_end': 'Morning · Schichtende 12:30',
        'in_time': '08:20',
        'out_time': '12:15',
        'working_hours': 'Arbeitsstunden',
        'late_entry_hrs': 'Verspätet um 5m 10s',
        'early_exit_hrs': 'Früher gegangen um 15m',
      };
      for (final entry in captions.entries) {
        final detail = _in(duration, find.text(details[entry.key]!));
        expect(detail, findsOneWidget);
        await _openFields(tester);
        final tile = await _fieldTile(tester, entry.key);
        expect(
          find.descendant(of: tile, matching: find.text(entry.value)),
          findsOneWidget,
        );
        expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await _closeFields(tester);
        expect(detail, findsNothing);
        switch (entry.key) {
          case 'shift_start':
            expect(
              _in(duration, find.text('Morning · Schichtende 12:30')),
              findsOneWidget,
            );
          case 'shift_end':
            expect(_in(duration, find.text('Morning')), findsOneWidget);
          case 'in_time':
            expect(_in(duration, find.text('Kommen')), findsNothing);
            expect(
              _in(duration, find.text('Verspätet um 5m 10s')),
              findsOneWidget,
            );
            expect(_in(flag, find.text('08:10')), findsNothing);
            expect(_in(flag, find.text('Late entry')), findsOneWidget);
          case 'out_time':
            expect(_in(duration, find.text('Gehen')), findsNothing);
            expect(
              _in(duration, find.text('Früher gegangen um 15m')),
              findsOneWidget,
            );
            expect(_in(flag, find.text('12:10')), findsNothing);
            expect(_in(flag, find.text('Early exit')), findsOneWidget);
          case 'working_hours':
            expect(_in(duration, find.text('3h 55m')), findsNothing);
          case 'late_entry_hrs':
            expect(_in(duration, find.text('Late entry')), findsOneWidget);
          case 'early_exit_hrs':
            expect(_in(duration, find.text('Early exit')), findsOneWidget);
        }
      }
      expect(api.calls, hasLength(1));
      expect(find.text('SAT 14 NOV 2026'), findsOneWidget);
      for (final (name, status, _, _) in people) {
        final card = _cardFor<ShiftAttendanceCard>(name);
        expect(_in(card, find.text(status)), findsOneWidget);
        expect(_in(card, find.text('Morning')), findsOneWidget);
      }
      for (final card in [duration, flag]) {
        expect(_in(card, find.text('Late entry')), findsOneWidget);
        expect(_in(card, find.text('Early exit')), findsOneWidget);
      }
      for (final (name, cue) in const [
        ('Missing Both', 'No check-ins'),
        ('Missing Arrival', 'No check-in'),
        ('Missing Departure', 'No check-out'),
      ]) {
        expect(
          _in(_cardFor<ShiftAttendanceCard>(name), find.text(cue)),
          findsOneWidget,
        );
      }
      for (final name in ['Excused Absent', 'Excused Leave']) {
        expect(
          _in(
            _cardFor<ShiftAttendanceCard>(name),
            find.textContaining('No check'),
          ),
          findsNothing,
        );
      }
      await _expectSummary(tester, summary);
      await _expectFooter(
        tester,
        'End of list · 7 records · 7 employees · '
        'Arbeitsstunden 7h 55m · 2 late · 2 early exits · 3 missing a punch',
      );
    });

    testWidgets(
      'Shift Attendance Fields retain the submitted period and preset',
      (tester) async {
        _phone(tester);
        api.message = _shiftMessage;
        final controller = Get.put(ShiftAttendanceController());
        await tester.pumpWidget(
          const GetMaterialApp(home: ShiftAttendanceScreen()),
        );
        await tester.pumpAndSettle();
        ReportPeriodBar bar() => tester.widget(find.byType(ReportPeriodBar));
        final submitted = bar().label;
        final submittedPreset = bar().selected;
        expect(submittedPreset, isNotNull);

        controller.fromDateController.text = '2025-01-01';
        controller.toDateController.text = '2025-01-07';
        await _openFields(tester);
        await tester.tap(await _fieldTile(tester, 'in_time'));
        await tester.pumpAndSettle();
        await _closeFields(tester);

        expect(bar().label, submitted);
        expect(bar().selected, submittedPreset);
        expect(find.text('Test Person One'), findsOneWidget);
        await _expectFooter(
          tester,
          'End of list · 2 records · 2 employees · Total Working Hours '
          '3h 55m · 1 late · 1 missing a punch',
        );
        expect(api.calls, hasLength(1));

        controller.scrollController.jumpTo(0);
        await controller.runReport();
        await tester.pumpAndSettle();
        expect(bar().label, periodLabel('2025-01-01', '2025-01-07'));
        expect(bar().selected, isNull);
      },
    );

    testWidgets(
      'Employee Hours Fields retain the submitted period and preset',
      (tester) async {
        _phone(tester);
        api.message = {
          'columns': _columns(_utilizationDetails),
          'result': const [
            {
              'employee': 'E-17',
              'employee_name': 'Test Person',
              'department': 'Warehouse',
              'billed_hours': 5,
            },
          ],
        };
        final controller = Get.put(EmployeeHoursUtilizationController());
        await tester.pumpWidget(
          const GetMaterialApp(home: EmployeeHoursUtilizationScreen()),
        );
        await tester.pumpAndSettle();
        ReportPeriodBar bar() => tester.widget(find.byType(ReportPeriodBar));
        final submitted = bar().label;
        final submittedPreset = bar().selected;
        expect(submittedPreset, isNotNull);

        controller.fromDateController.text = '2025-01-01';
        controller.toDateController.text = '2025-01-07';
        await _openFields(tester);
        await tester.tap(await _fieldTile(tester, 'department'));
        await tester.pumpAndSettle();
        await _closeFields(tester);

        expect(bar().label, submitted);
        expect(bar().selected, submittedPreset);
        expect(find.text('Test Person'), findsOneWidget);
        expect(find.textContaining('Billed Hours (B) 5h'), findsOneWidget);
        expect(api.calls, hasLength(1));
      },
    );

    for (final shift in [false, true]) {
      testWidgets(
        '${shift ? 'Shift Attendance' : 'Employee Hours'} displays an '
        'End of list footer only after a successful empty retry',
        (tester) async {
          _phone(tester);
          final pending = Completer<void>();
          api.beforeReport = () => pending.future;
          api.error = shift
              ? StateError('Shift attendance failed')
              : _reportException(417, {
                  '_server_messages': jsonEncode([
                    jsonEncode({
                      'message':
                          'Please set <b>Standard Working Hours</b> in '
                          '<a href="/app/hr-settings">HR Settings</a>.',
                    }),
                  ]),
                });
          if (shift) {
            Get.put(ShiftAttendanceController());
          } else {
            Get.put(EmployeeHoursUtilizationController());
          }
          await tester.pumpWidget(
            GetMaterialApp(
              home: shift
                  ? const ShiftAttendanceScreen()
                  : const EmployeeHoursUtilizationScreen(),
            ),
          );
          await tester.pump();
          expect(find.byType(ListEndFooter), findsNothing);
          pending.complete();
          await tester.pumpAndSettle();
          expect(
            find.text(
              shift
                  ? 'Could not run Shift Attendance. Try again.'
                  : 'Please set Standard Working Hours in HR Settings.',
            ),
            findsOneWidget,
          );
          expect(find.byType(ListEndFooter), findsNothing);
          await _openFields(tester);
          final captions = shift ? _shiftDetails : _utilizationDetails;
          for (final key in captions.keys) {
            await tester.tap(await _fieldTile(tester, key));
            await tester.pumpAndSettle();
          }
          await _closeFields(tester);

          api.error = null;
          api.message = {'columns': _columns(captions), 'result': const []};
          final retry = Completer<void>();
          api.beforeReport = () => retry.future;
          await tester.tap(find.byTooltip('Run report'));
          await tester.pump();
          expect(api.calls, hasLength(2));
          expect(find.byType(ListEndFooter), findsNothing);
          retry.complete();
          await tester.pumpAndSettle();
          final period = tester
              .widget<ReportPeriodBar>(find.byType(ReportPeriodBar))
              .label;
          final emptyMessage = shift
              ? 'No shift attendance'
              : 'No submitted timesheets';
          expect(find.text('$emptyMessage for $period.'), findsOneWidget);
          await _expectFooter(tester, 'End of list');
        },
      );
    }

    testWidgets('Monthly Attendance Fields retain the submitted empty range', (
      tester,
    ) async {
      _phone(tester);
      const measures = {
        'total_present': 'Total Present',
        'total_leaves': 'Total Leaves',
        'total_absent': 'Total Absent',
        'total_holidays': 'Total Holidays',
        'unmarked_days': 'Unmarked Days',
        'total_late_entries': 'Total Late Entries',
        'total_early_exits': 'Total Early Exits',
      };
      api.message = {'columns': _columns(measures), 'result': const []};
      final controller = Get.put(MonthlyAttendanceSheetController());
      controller.filterBasedOnController.text = 'Date Range';
      controller.summarizedController.text = '1';
      controller.startDateController.text = '2025-01-01';
      controller.endDateController.text = '2025-01-07';
      await tester.pumpWidget(
        const GetMaterialApp(home: MonthlyAttendanceSheetScreen()),
      );
      await tester.pumpAndSettle();
      const submitted = '2025-01-01 → 2025-01-07';
      expect(
        find.text('No attendance records for $submitted.'),
        findsOneWidget,
      );

      controller.startDateController.text = '2025-02-01';
      controller.endDateController.text = '2025-02-07';
      await _openFields(tester);
      for (final key in measures.keys) {
        await tester.tap(await _fieldTile(tester, key));
        await tester.pumpAndSettle();
      }
      await _closeFields(tester);

      expect(find.text(submitted), findsOneWidget);
      expect(
        find.text('No attendance records for $submitted.'),
        findsOneWidget,
      );
      await _expectFooter(tester, 'End of list');
      expect(api.calls, hasLength(1));
    });

    testWidgets('Draft summary leaves the loaded attendance detail in Fields', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      api.message = {
        'columns': _columns(const {
          'employee': 'Employee',
          'employee_name': 'Employee Name',
          'shift': 'Shift',
          '01-09-2026': '1 Tue',
        }),
        'result': const [
          ['E-1', 'Employee One', 'Morning', 'P'],
        ],
      };
      final controller = Get.put(MonthlyAttendanceSheetController());
      await tester.pumpWidget(
        const GetMaterialApp(home: MonthlyAttendanceSheetScreen()),
      );
      await tester.pumpAndSettle();
      final footer = tester.widget<ListEndFooter>(find.byType(ListEndFooter));
      expect(footer.label, contains('1 employee'));

      await tester.tap(find.byTooltip('Filters, 1 active'));
      await tester.pumpAndSettle();
      final summarized = find.text('Summarized');
      await tester.ensureVisible(summarized);
      await tester.pumpAndSettle();
      await tester.tap(summarized);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(summarized)).pop();
      await tester.pumpAndSettle();
      expect(controller.summarizedController.text, '1');

      await _openFields(tester);
      await tester.tap(await _fieldTile(tester, 'shift'));
      await tester.pumpAndSettle();
      await _closeFields(tester);

      expect(find.text('Employee One'), findsOneWidget);
      expect(find.text('E-1 · Morning'), findsNothing);
      expect(find.byTooltip('1 Tue — Present'), findsOneWidget);
      expect(find.textContaining('No attendance records'), findsNothing);
      expect(find.text(footer.label!), findsOneWidget);
      expect(api.calls, hasLength(1));
    });

    testWidgets('Monthly Attendance Fields follow detail and summary shapes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = Get.put(MonthlyAttendanceSheetController());
      controller.groupByController.text = 'Department';
      controller.month.value = DateTime(2020, 9);
      void expectGroups() {
        final training = tester.getTopLeft(find.text('TRAINING')).dy;
        final workshop = tester.getTopLeft(find.text('WORKSHOP')).dy;
        expect(
          training,
          lessThan(tester.getTopLeft(find.text('Employee One')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Employee One')).dy,
          lessThan(workshop),
        );
        expect(
          workshop,
          lessThan(tester.getTopLeft(find.text('Employee Two')).dy),
        );
      }

      final detail = {
        'columns': _columns(const {
          'department': 'Department',
          'employee': 'Employee',
          'employee_name': 'Employee Name',
          'shift': 'Shift',
          '01-09-2020': '1 Tue',
          '02-09-2020': '2 Wed',
        }),
        'result': const [
          ['Training', '', '', '', '', ''],
          ['', 'E-1', 'Employee One', 'Morning', 'P', 'ZZ'],
          ['', 'E-1', 'Employee One', 'Evening', 'A', ''],
          ['Workshop', '', '', '', '', ''],
          ['', 'E-2', 'Employee Two', 'Afternoon', 'L', 'P'],
        ],
      };
      api.message = detail;
      await tester.pumpWidget(
        const GetMaterialApp(home: MonthlyAttendanceSheetScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('E-1 · Morning / Evening'), findsOneWidget);
      await tester.tap(find.text('Employee One'));
      await tester.pumpAndSettle();
      await _openFields(tester);
      await tester.tap(await _fieldTile(tester, 'shift'));
      await tester.pumpAndSettle();
      await _closeFields(tester);
      expect(find.text('E-1 · Morning / Evening'), findsNothing);
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      expect(find.byTooltip('2 Wed — Unmarked'), findsOneWidget);
      final firstEmployee = _cardFor<SheetEmployeeCard>('Employee One');
      final calendars = _in(firstEmployee, find.byType(AttendanceCalendarGrid));
      expect(calendars, findsNWidgets(2));
      Color? firstDayDot(Finder calendar) {
        final day = _in(calendar, find.text('1'));
        final cell = find
            .ancestor(of: day, matching: find.byType(Column))
            .first;
        final dot = tester.widget<Container>(_in(cell, find.byType(Container)));
        return (dot.decoration as BoxDecoration).color;
      }

      expect(firstDayDot(calendars.first), AppColors.green500);
      expect(firstDayDot(calendars.last), AppColors.red500);
      expect(
        _in(firstEmployee, find.byTooltip('1 Tue — Absent')),
        findsOneWidget,
      );
      expectGroups();
      final secondEmployee = _cardFor<SheetEmployeeCard>('Employee Two');
      expect(
        tester
            .widgetList<Tooltip>(_in(secondEmployee, find.byType(Tooltip)))
            .map((tooltip) => tooltip.message),
        containsAll(['1 Tue — On Leave', '2 Wed — Present']),
      );
      await _expectFooter(
        tester,
        'End of list · 2 employees · 1 absent · '
        '1 on leave · 1 present · 1 unmarked',
      );
      expect(api.calls, hasLength(1));

      controller.filterBasedOnController.text = 'Date Range';
      await controller.runReport();
      await tester.pumpAndSettle();
      expect(find.text('E-1 · Morning / Evening'), findsOneWidget);
      await _openFields(tester);
      final locked = await _fieldTile(tester, 'shift');
      expect(tester.widget<CheckboxListTile>(locked).onChanged, isNull);
      expect(tester.widget<CheckboxListTile>(locked).value, isTrue);
      await _closeFields(tester);

      const metrics = {
        'total_present': ('Anwesend gesamt', 2.5, 1.5),
        'total_leaves': ('Urlaub gesamt', 0.5, 0.5),
        'total_absent': ('Abwesend gesamt', 0, 1.5),
        'total_holidays': ('Feiertage gesamt', 2.5, 0),
        'unmarked_days': ('Nicht erfasst', 0.5, 0.5),
        'total_late_entries': ('Verspätungen gesamt', 2, 0),
        'total_early_exits': ('Frühe Abgänge gesamt', 1, 0),
        'sick_leave': ('Krankheitstage', 1, 0),
        'training_leave': ('Fortbildungstage', 0, 2),
      };
      final summarized = {
        'columns': [
          ..._columns(const {
            'department': 'Department',
            'employee': 'Employee',
            'employee_name': 'Employee Name',
          }),
          for (final entry in metrics.entries)
            {
              'fieldname': entry.key,
              'label': entry.value.$1,
              'fieldtype': 'Float',
            },
        ],
        'result': [
          ['Training', '', ''],
          [
            '',
            'E-1',
            'Employee One',
            for (final metric in metrics.values) metric.$2,
          ],
          ['Workshop', '', ''],
          [
            '',
            'E-2',
            'Employee Two',
            for (final metric in metrics.values) metric.$3,
          ],
        ],
      };
      api.message = summarized;
      controller.summarizedController.text = '1';
      await controller.runReport();
      await tester.pumpAndSettle();
      final one = _cardFor<SheetSummaryCard>('Employee One');
      final two = _cardFor<SheetSummaryCard>('Employee Two');
      expectGroups();
      expect(_in(one, find.text('Fortbildungstage 0')), findsNothing);
      expect(_in(two, find.text('Krankheitstage 0')), findsNothing);
      for (final entry in metrics.entries) {
        final (caption, firstValue, secondValue) = entry.value;
        final firstChip = _in(one, find.text('$caption ${firstValue.round()}'));
        final secondChip = _in(
          two,
          find.text('$caption ${secondValue.round()}'),
        );
        expect(
          firstChip,
          entry.key == 'training_leave' ? findsNothing : findsOneWidget,
        );
        expect(
          secondChip,
          entry.key == 'sick_leave' ? findsNothing : findsOneWidget,
        );
        await _openFields(tester);
        final tile = await _fieldTile(tester, entry.key);
        expect(_in(tile, find.text(caption)), findsOneWidget);
        expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await _closeFields(tester);
        expect(firstChip, findsNothing);
        expect(secondChip, findsNothing);
      }
      expectGroups();
      const summaryFooter =
          'End of list · 2 employees · Anwesend gesamt 4 · '
          'Abwesend gesamt 2 · Urlaub gesamt 1 · Nicht erfasst 1';
      await _expectFooter(tester, summaryFooter);

      api.error = StateError('response failed');
      controller.summarizedController.clear();
      await controller.runReport();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not run Monthly Attendance Sheet'),
        findsOneWidget,
      );
      expect(find.textContaining('End of list'), findsNothing);
      api.error = null;
      api.message = summarized;
      controller.summarizedController.text = '1';
      await controller.runReport();
      await tester.pumpAndSettle();
      expect(find.text('Employee One'), findsOneWidget);
      expect(_in(one, find.text('Krankheitstage 1')), findsNothing);
      await _expectFooter(tester, summaryFooter);
    });
  });
}
