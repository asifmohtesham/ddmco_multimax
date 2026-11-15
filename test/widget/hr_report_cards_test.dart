import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_widgets.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_logic.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/widgets/utilization_card.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/shift_attendance_logic.dart';
import 'package:multimax/app/modules/hr/reports/shift_attendance/widgets/shift_attendance_card.dart';
import 'package:multimax/main.dart';

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: buildAppTheme(AppScheme.of(brightness), brightness),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

final _late = parseShiftAttendance(const [
  {
    'name': 'HR-ATT-2026-02678',
    'employee': 'HR-EMP-00007',
    'employee_name': 'Jawwad Bilgi',
    'shift': 'Morning (Fri)',
    'attendance_date': '2026-11-13',
    'status': 'Present',
    'in_time': '08:05:33',
    'out_time': null,
    'working_hours': 0.0,
    'late_entry': 1,
    'late_entry_hrs': '5m 33s',
    'shift_start': '08:00:00',
    'shift_end': '12:00:00',
  },
]).single;

final _util = parseUtilization(const [
  {
    'employee': 'HR-EMP-00007',
    'employee_name': 'Jawwad Bilgi',
    'department': 'Warehouse - MM',
    'total_hours': 240.0,
    'billed_hours': 0.0,
    'non_billed_hours': 100.5,
    'untracked_hours': 139.5,
    'per_util': 41.88,
    'per_util_billed_only': 0.0,
  },
]).single;

void main() {
  for (final brightness in Brightness.values) {
    final isDark = brightness == Brightness.dark;
    final mode = isDark ? 'dark' : 'light';

    testWidgets('shift attendance card in $mode mode', (tester) async {
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: ShiftAttendanceCard(row: _late),
        ),
      );

      expect(find.text('Jawwad Bilgi'), findsOneWidget);
      expect(find.text('Morning (Fri) · 08:00–12:00'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('08:05'), findsOneWidget);
      expect(find.text('late 5m 33s'), findsOneWidget);
      expect(find.text('—'), findsOneWidget); // no check-out
      expect(find.text('0h'), findsOneWidget);
      expect(find.text('No check-out'), findsOneWidget);

      // Late in-time inks with the AA status ramp, never the x500 base.
      expect(
        _colorOf(tester, '08:05'),
        isDark ? AppColors.orange300 : AppColors.orange700,
      );
      expect(
        _colorOf(tester, 'No check-out'),
        isDark ? AppColors.yellow300 : AppColors.yellow700,
      );

      // The card surface is the theme's, not a hardcoded white.
      final card = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(AppRadius.lg),
        ),
      );
      expect(
        (card.decoration as BoxDecoration).color,
        AppScheme.of(brightness).fg,
      );
    });

    testWidgets('utilisation card in $mode mode', (tester) async {
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: UtilizationCard(row: _util),
        ),
      );

      expect(find.text('Jawwad Bilgi'), findsOneWidget);
      expect(find.text('HR-EMP-00007 · Warehouse - MM'), findsOneWidget);
      expect(find.text('41.9%'), findsOneWidget);
      expect(find.text('billed 0%'), findsOneWidget);
      expect(find.text('100h 30m'), findsOneWidget);
      expect(find.text('139h 30m'), findsOneWidget);
      expect(find.text('240h'), findsOneWidget);

      // Below the 70% target → red ramp ink.
      expect(
        _colorOf(tester, '41.9%'),
        isDark ? AppColors.red300 : AppColors.red700,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('summary strip and period bar in $mode mode', (tester) async {
      ReportPeriod? tapped;
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: Column(
            children: [
              ReportPeriodBar(
                label: '1 Nov → 15 Nov 2026',
                presets: const [ReportPeriod.today, ReportPeriod.thisMonth],
                selected: ReportPeriod.thisMonth,
                onPreset: (p) => tapped = p,
                count: 314,
              ),
              ReportSummaryStrip(
                items: parseReportSummary(const [
                  {
                    'value': 314,
                    'indicator': 'Green',
                    'label': 'Present Records',
                  },
                  {'value': 6, 'indicator': 'Red', 'label': 'Late Entries'},
                ]),
              ),
            ],
          ),
        ),
      );

      expect(find.text('314 records'), findsOneWidget);
      expect(find.text('Present Records'), findsOneWidget);
      expect(
        _colorOf(tester, '6'),
        isDark ? AppColors.red300 : AppColors.red700,
      );

      await tester.tap(find.text('Today'));
      expect(tapped, ReportPeriod.today);
    });
  }
}
