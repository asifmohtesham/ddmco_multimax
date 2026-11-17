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
import 'package:multimax/app/modules/hr/attendance/widgets/employee_detail_sheet.dart';
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

  // Clocked hours (from 2026-11-30): one row per day, net against expected.
  const standard = ShiftRules(
      name: 'Standard', start: Duration(hours: 8), end: Duration(hours: 20), graceMinutes: 15,
      checkInBeforeMinutes: 120, checkOutAfterMinutes: 120, expectedHours: 10,
      breakStart: Duration(hours: 12, minutes: 15), breakEnd: Duration(hours: 13, minutes: 30),
      breakStartFriday: Duration(hours: 12), breakEndFriday: Duration(hours: 14, minutes: 30));
  final mon = DateTime(2026, 11, 30);
  EmployeeCheckin tap(int h, int m) =>
      EmployeeCheckin(name: '$h$m', employee: emp.name, time: DateTime(2026, 11, 30, h, m));

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('clocked row today: net so far against expected, no shortfall yet [$b]', (tester) async {
      final row = deriveDayStatus(
        employee: emp, day: mon, now: DateTime(2026, 11, 30, 15), shift: standard,
        isHoliday: false, punches: [tap(8, 0), tap(12, 15), tap(13, 30)],
      );
      await tester.pumpWidget(app(EmployeeAttendanceCard(row: row, onTap: () {}), brightness: b));
      expect(find.text('Present'), findsOneWidget);
      expect(find.textContaining('Net 4h 15m of 10h', findRichText: true), findsOneWidget);
      expect(find.textContaining('short', findRichText: true), findsNothing);
      expect(find.text('Missing punch'), findsNothing); // odd is normal while the day runs
      expect(tester.takeException(), isNull);
    });

    testWidgets('clocked row, day over: Missing punch pill, late flag, shortfall [$b]', (tester) async {
      final row = deriveDayStatus(
        employee: emp, day: mon, now: DateTime(2026, 12, 1, 8), shift: standard,
        isHoliday: false,
        ledger: AttendanceRecord(
          name: 'A', employee: emp.name, employeeName: '', date: mon, status: 'Present',
          lateEntry: true, inTime: DateTime(2026, 11, 30, 8, 20), outTime: DateTime(2026, 11, 30, 20),
          shift: 'Standard', punchCount: 3, missingPunch: true, netHours: 3.92,
          expectedHours: 10, shortfallHours: 6.08,
        ),
      );
      await tester.pumpWidget(app(EmployeeAttendanceCard(row: row, onTap: () {}), brightness: b));
      expect(find.text('Missing punch'), findsOneWidget);
      expect(find.text('5 min late'), findsOneWidget);
      expect(find.textContaining('Net 3h 55m of 10h · short\u00A06h\u00A005m', findRichText: true), findsOneWidget);
      final (_, ink) = StatusPill.colourForStatus('Missing punch', brightness: b);
      expect(ink, b == Brightness.dark ? AppColors.yellow300 : AppColors.yellow700);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail sheet: own pattern, break and the hours panel [$b]', (tester) async {
      final row = deriveDayStatus(
        employee: emp, day: mon, now: DateTime(2026, 12, 1, 8), shift: standard,
        isHoliday: false, punches: [tap(8, 0), tap(12, 15), tap(13, 30), tap(18, 0)],
      );
      await tester.pumpWidget(app(
        // The screen's focus shift is another pattern: the sheet must use the row's own.
        EmployeeDetailSheet(row: row, day: mon, shift: shift, loadedAt: null),
        brightness: b,
      ));
      expect(find.textContaining('Standard', findRichText: true), findsWidgets);
      expect(find.textContaining('break 12:15–13:30', findRichText: true), findsOneWidget);
      expect(find.byType(ClockedHoursPanel), findsOneWidget);
      expect(find.text('8h 45m'), findsOneWidget); // net
      expect(find.text('10h'), findsOneWidget); // expected
      expect(find.text('1h 15m'), findsOneWidget); // shortfall
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a non-clocked single-shift row shows no hours line', (tester) async {
    final row = deriveDayStatus(
      employee: emp, day: day, now: DateTime(2026, 9, 9, 21), shift: shift, isHoliday: false,
      punches: [
        EmployeeCheckin(name: 'a', employee: emp.name, time: DateTime(2026, 9, 9, 8)),
        EmployeeCheckin(name: 'b', employee: emp.name, time: DateTime(2026, 9, 9, 12)),
        EmployeeCheckin(name: 'c', employee: emp.name, time: DateTime(2026, 9, 9, 13)),
      ],
    );
    await tester.pumpWidget(app(EmployeeAttendanceCard(row: row, onTap: () {})));
    expect(find.text('Present'), findsOneWidget);
    expect(find.textContaining('Net', findRichText: true), findsNothing);
  });

  // Found on a 1080 px phone: the month summary ran past the screen edge.
  testWidgets('month summary header wraps on a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const text = '13 working days · 7 present · 0 absent · 6 no check-out'
        ' · 1 missing punch · short 3h 54m';
    await tester.pumpWidget(app(const Scaffold(
      body: Padding(padding: EdgeInsets.all(12), child: AttendanceGroupHeader(text: text, wrap: true)),
    )));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.textContaining('MISSING PUNCH')).height, greaterThan(20));
  });
}
