import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/hr/attendance/month/attendance_month_screen.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/monthly_attendance_sheet_logic.dart';
import 'package:multimax/app/modules/hr/reports/monthly_attendance_sheet/widgets/attendance_sheet_cards.dart';
import 'package:multimax/main.dart';

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

const _twoShiftRows = [
  {
    'shift': 'Morning',
    'employee': 'HR-EMP-00001',
    'employee_name': 'Asif Mohtesham',
    '01-09-2026': 'P',
    '02-09-2026': 'A',
    '03-09-2026': 'WO',
  },
  {
    'shift': 'Afternoon',
    'employee': 'HR-EMP-00001',
    'employee_name': 'Asif Mohtesham',
    '01-09-2026': 'P',
    '02-09-2026': 'P',
    '03-09-2026': 'WO',
  },
];

final _days = parseDayColumns(const [
  {'label': 'Employee', 'fieldname': 'employee', 'fieldtype': 'Link'},
  {'label': '1 Tue', 'fieldtype': 'Data', 'fieldname': '01-09-2026'},
  {'label': '2 Wed', 'fieldtype': 'Data', 'fieldname': '02-09-2026'},
  {'label': '3 Thu', 'fieldtype': 'Data', 'fieldname': '03-09-2026'},
]);

void main() {
  for (final brightness in Brightness.values) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('employee card renders collapsed in $mode mode',
        (tester) async {
      final employee = parseDetailed(_twoShiftRows).single;

      await tester.pumpWidget(_host(
        brightness: brightness,
        child: SheetEmployeeCard(
          employee: employee,
          days: _days,
          month: DateTime(2026, 9),
          expanded: false,
          onTap: () {},
        ),
      ));

      expect(find.text('Asif Mohtesham'), findsOneWidget);
      expect(find.text('HR-EMP-00001 · Morning / Afternoon'), findsOneWidget);
      // Merged counts: 1 absent (Morning loses to Afternoon), 1 present, 1 WO.
      expect(find.text('A 1'), findsOneWidget);
      expect(find.text('P 1'), findsOneWidget);
      expect(find.text('WO 1'), findsOneWidget);
      expect(find.byType(AttendanceCalendarGrid), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('summary card renders in $mode mode', (tester) async {
      final summary = parseSummarized(const [
        {
          'employee': 'HR-EMP-00001',
          'employee_name': 'Asif Mohtesham',
          'total_present': 1,
          'total_leaves': 0,
          'total_absent': 2,
          'total_holidays': 4,
          'unmarked_days': 23,
          'sick_leave': 3,
          'total_late_entries': 1,
          'total_early_exits': 0,
        },
      ]).single;

      await tester.pumpWidget(_host(
        brightness: brightness,
        child: SheetSummaryCard(
          summary: summary,
          leaveTypes: const [
            SheetSummaryColumn(fieldname: 'sick_leave', label: 'Sick Leave'),
            SheetSummaryColumn(
                fieldname: 'casual_leave', label: 'Casual Leave'),
          ],
        ),
      ));

      expect(find.text('Absent 2'), findsOneWidget);
      expect(find.text('Unmarked 23'), findsOneWidget);
      // Only leave types with a non-zero count are shown.
      expect(find.text('Sick Leave 3'), findsOneWidget);
      expect(find.text('Casual Leave 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expanding shows one calendar per shift', (tester) async {
    final employee = parseDetailed(_twoShiftRows).single;

    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: SheetEmployeeCard(
        employee: employee,
        days: _days,
        month: DateTime(2026, 9),
        expanded: true,
        onTap: () {},
      ),
    ));

    expect(find.byType(AttendanceCalendarGrid), findsNWidgets(2));
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Afternoon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the card reports the toggle', (tester) async {
    var tapped = false;
    final employee = parseDetailed(_twoShiftRows).single;

    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: SheetEmployeeCard(
        employee: employee,
        days: _days,
        month: DateTime(2026, 9),
        expanded: false,
        onTap: () => tapped = true,
      ),
    ));

    await tester.tap(find.text('Asif Mohtesham'));
    expect(tapped, isTrue);
  });

  testWidgets('a Date Range run offers no expansion', (tester) async {
    final employee = parseDetailed(_twoShiftRows).single;

    await tester.pumpWidget(_host(
      brightness: Brightness.light,
      child: SheetEmployeeCard(
        employee: employee,
        days: _days,
        month: DateTime(2026, 9),
        expanded: false,
        canExpand: false,
        onTap: () {},
      ),
    ));

    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
