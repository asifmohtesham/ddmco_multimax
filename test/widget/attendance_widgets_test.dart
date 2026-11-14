import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_screen.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/attendance_summary_strip.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/date_context_row.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  const shift = ShiftRules(
      name: 'General', start: Duration(hours: 8), end: Duration(hours: 20), graceMinutes: 15);
  const emp = TrackedEmployee(
      name: 'HR-EMP-00001', employeeName: 'Ayesha Mohammed', department: 'Warehouse', deviceId: '7');
  final day = DateTime(2026, 9, 9);

  Widget app(Widget child, {Brightness brightness = Brightness.light}) {
    final scheme = brightness == Brightness.dark ? AppScheme.dark : AppScheme.light;
    final theme = buildAppTheme(scheme, brightness);
    return GetMaterialApp(
      theme: theme,
      darkTheme: theme,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: SizedBox(width: 392, child: child)),
    );
  }

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('late row renders pill, flag and In/Out [$b]', (tester) async {
      final row = deriveDayStatus(
        employee: emp,
        day: day,
        now: DateTime(2026, 9, 9, 10),
        shift: shift,
        isHoliday: false,
        punches: [
          EmployeeCheckin(name: 'a', employee: emp.name, time: DateTime(2026, 9, 9, 8, 31)),
        ],
      );
      await tester.pumpWidget(app(EmployeeAttendanceCard(row: row, onTap: () {}), brightness: b));
      expect(find.text('Late'), findsOneWidget);
      expect(find.text('16 min late'), findsOneWidget);
      expect(find.textContaining('08:31', findRichText: true), findsOneWidget);
      expect(find.textContaining('—', findRichText: true), findsOneWidget); // blank Out time

      // Status ink must follow the theme: 700 in light, 300 in dark.
      final (_, ink) = StatusPill.colourForStatus('Late', brightness: b);
      expect(ink, b == Brightness.dark ? AppColors.orange300 : AppColors.orange700);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('summary strip: dash before cut-off, tap toggles filter', (tester) async {
    String? toggled;
    await tester.pumpWidget(app(AttendanceSummaryStrip(
      counts: const AttendanceCounts(present: 6, notIn: 10, tracked: 16),
      isHoliday: false,
      beforeCutoff: true,
      selectedKey: null,
      onToggle: (k) => toggled = k,
    )));
    expect(find.text('—'), findsOneWidget); // Absent not applicable yet
    expect(find.text('10'), findsOneWidget);
    await tester.tap(find.text('Present'));
    expect(toggled, 'Present');
    await tester.tap(find.text('Absent')); // dash tile is not tappable
    expect(toggled, 'Present');
  });

  testWidgets('holiday strip shows only the Holiday count', (tester) async {
    await tester.pumpWidget(app(AttendanceSummaryStrip(
      counts: const AttendanceCounts(holiday: 16, tracked: 16),
      isHoliday: true,
      beforeCutoff: false,
      selectedKey: null,
      onToggle: (_) {},
    )));
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('16'), findsOneWidget);
  });

  testWidgets('date row labels today and disables next; stale label is orange',
      (tester) async {
    final now = DateTime(2026, 9, 9, 10, 42);
    await tester.pumpWidget(app(DateContextRow(
      date: day,
      onPrevious: () {},
      onNext: null,
      onPick: () {},
      loadedAt: now.subtract(const Duration(minutes: 42)),
      now: now,
    )));
    expect(find.text('Today, Wed 9 Sep'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Updated 42 min ago'));
    expect(label.style?.color, AppColors.orange700);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  final latest = EmployeeCheckin(name: 'p', employee: emp.name, time: DateTime(2026, 9, 9, 10, 19));

  testWidgets('no punches: System Manager gets the terminal diagnosis', (tester) async {
    await tester.pumpWidget(
        app(NoPunchesState(latest: latest, isSystemManager: true, onReload: () {})));
    expect(find.text('No punches since 9 Sep'), findsOneWidget);
    expect(find.textContaining('terminal may be offline'), findsOneWidget);
    expect(find.text('Last punch · 9 Sep, 10:19'), findsOneWidget);
  });

  testWidgets('no punches: everyone else gets neutral wording', (tester) async {
    await tester.pumpWidget(
        app(NoPunchesState(latest: latest, isSystemManager: false, onReload: () {})));
    expect(find.text('No check-ins recorded yet today'), findsOneWidget);
    expect(find.text('Statuses will appear as check-ins arrive.'), findsOneWidget);
    expect(find.textContaining('terminal'), findsNothing);
    expect(find.textContaining('Last punch'), findsNothing);
  });

  const morning = ShiftRules(
      name: 'Morning', start: Duration(hours: 8), end: Duration(hours: 12, minutes: 15),
      graceMinutes: 15, earlyExitGraceMinutes: 15, checkInBeforeMinutes: 120, checkOutAfterMinutes: 45);
  const afternoon = ShiftRules(
      name: 'Afternoon', start: Duration(hours: 13, minutes: 30), end: Duration(hours: 20),
      graceMinutes: 15, earlyExitGraceMinutes: 15, checkInBeforeMinutes: 30, checkOutAfterMinutes: 120);

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('two-shift row: a line per shift, No check-out pill [$b]', (tester) async {
      // 13:10 Saturday: in at 07:58, never out, Morning window closed at 13:00.
      final row = deriveDayStatus(
        employee: emp,
        day: DateTime(2026, 9, 12),
        now: DateTime(2026, 9, 12, 13, 10),
        shift: morning,
        shifts: const [morning, afternoon],
        isHoliday: false,
        punches: [
          EmployeeCheckin(
              name: 'a', employee: emp.name, time: DateTime(2026, 9, 12, 7, 58), logType: 'IN'),
        ],
      );
      await tester.pumpWidget(app(EmployeeAttendanceCard(row: row, onTap: () {}), brightness: b));
      expect(find.text('No check-out'), findsOneWidget);
      expect(find.text('Not in yet'), findsOneWidget); // each shift carries its own pill
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);
      expect(find.textContaining('07:58', findRichText: true), findsOneWidget);

      // The pill and the shift needing attention share the yellow ramp: 700 light, 300 dark.
      final (_, ink) = StatusPill.colourForStatus('No check-out', brightness: b);
      expect(ink, b == Brightness.dark ? AppColors.yellow300 : AppColors.yellow700);
      expect(tester.widget<Text>(find.text('Morning')).style?.color, ink);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two-shift row: Morning Present, Afternoon Absent, no day pill [$b]', (tester) async {
      // 13:59 Saturday: in 08:04, out 12:21, nothing since the 13:45 afternoon cut-off.
      final row = deriveDayStatus(
        employee: emp,
        day: DateTime(2026, 9, 12),
        now: DateTime(2026, 9, 12, 13, 59),
        shift: morning,
        shifts: const [morning, afternoon],
        isHoliday: false,
        punches: [
          EmployeeCheckin(
              name: 'a', employee: emp.name, time: DateTime(2026, 9, 12, 8, 4), logType: 'IN'),
          EmployeeCheckin(
              name: 'b', employee: emp.name, time: DateTime(2026, 9, 12, 12, 21), logType: 'OUT'),
        ],
      );
      await tester.pumpWidget(app(EmployeeAttendanceCard(row: row, onTap: () {}), brightness: b));
      expect(find.byType(StatusPill), findsNWidgets(2));
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Absent'), findsOneWidget);
      expect(find.textContaining('so far'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
