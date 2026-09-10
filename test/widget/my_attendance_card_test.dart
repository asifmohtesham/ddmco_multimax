import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/home/widgets/my_attendance_card.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/main.dart' show buildAppTheme;

// MyAttendanceCard on a 360 px phone in both themes: every headline state of
// spec §3.1, the month strip + tally, fail-soft (no strip), not enrolled,
// skeleton, and the tap.
void main() {
  const shift = ShiftRules(
    name: 'General',
    start: Duration(hours: 8),
    end: Duration(hours: 20),
    graceMinutes: 15,
  );
  const me = TrackedEmployee(name: 'ME', employeeName: 'Muhammad Asif', deviceId: '1');
  final now = DateTime(2026, 9, 10, 8, 32);
  final strip = MonthStrip(
    month: DateTime(2026, 9),
    days: [
      AttendanceStatus.present, AttendanceStatus.present, AttendanceStatus.late,
      AttendanceStatus.present, AttendanceStatus.absent, AttendanceStatus.holiday,
      AttendanceStatus.present, AttendanceStatus.late, AttendanceStatus.present,
      ...List<AttendanceStatus?>.filled(21, null),
    ],
    todayIndex: 9,
    present: 5,
    late: 2,
    absent: 1,
  );

  EmployeeDayStatus row(AttendanceStatus st,
          {DateTime? inTime, Duration? lateBy, TrackedEmployee e = me}) =>
      EmployeeDayStatus(employee: e, status: st, inTime: inTime, lateBy: lateBy);

  Future<void> pump(WidgetTester tester, Widget child, Brightness brightness) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(AppScheme.of(brightness), brightness),
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    testWidgets('not in yet: instruction, strip, tally, tap ($mode)', (tester) async {
      var taps = 0;
      await pump(
        tester,
        MyAttendanceCard(
            row: row(AttendanceStatus.notInYet),
            shift: shift,
            now: now,
            strip: strip,
            onTap: () => taps++),
        brightness,
      );
      expect(find.text('Not in yet'), findsOneWidget);
      expect(find.text('Punch before 08:15 to be on time'), findsOneWidget);
      expect(find.byType(MonthDotStrip), findsOneWidget);
      expect(find.text('September · 5 present · 2 late · 1 absent'), findsOneWidget);
      await tester.tap(find.text('Not in yet'));
      expect(taps, 1);
    });

    testWidgets('after cut-off: neutral wording, no terminal ($mode)', (tester) async {
      await pump(
        tester,
        MyAttendanceCard(
            row: row(AttendanceStatus.absentSoFar), shift: shift, now: now, strip: strip),
        brightness,
      );
      expect(find.text('No check-in recorded yet'), findsOneWidget);
      expect(find.text('Shift started 08:00'), findsOneWidget);
      expect(find.textContaining('terminal'), findsNothing);
    });

    testWidgets('late punch ($mode)', (tester) async {
      await pump(
        tester,
        MyAttendanceCard(
          row: row(AttendanceStatus.late,
              inTime: DateTime(2026, 9, 10, 8, 27), lateBy: const Duration(minutes: 12)),
          shift: shift,
          now: now,
          strip: strip,
        ),
        brightness,
      );
      expect(find.text('In · 08:27'), findsOneWidget);
      expect(find.text('12 min late'), findsOneWidget);
    });

    testWidgets('on time ($mode)', (tester) async {
      await pump(
        tester,
        MyAttendanceCard(
          row: row(AttendanceStatus.present, inTime: DateTime(2026, 9, 10, 7, 58)),
          shift: shift,
          now: now,
          strip: strip,
        ),
        brightness,
      );
      expect(find.text('In · 07:58'), findsOneWidget);
      expect(find.text('On time'), findsOneWidget);
    });

    testWidgets('holiday ($mode)', (tester) async {
      await pump(
        tester,
        MyAttendanceCard(
          row: row(AttendanceStatus.holiday),
          shift: shift,
          now: DateTime(2026, 9, 13, 10), // a Sunday
          strip: strip,
        ),
        brightness,
      );
      expect(find.text('Holiday'), findsOneWidget);
      expect(find.text('Sunday · no attendance expected'), findsOneWidget);
    });

    testWidgets('month ledger failed: headline only ($mode)', (tester) async {
      await pump(
        tester,
        MyAttendanceCard(row: row(AttendanceStatus.notInYet), shift: shift, now: now),
        brightness,
      );
      expect(find.text('Not in yet'), findsOneWidget);
      expect(find.byType(MonthDotStrip), findsNothing);
      expect(find.textContaining('present'), findsNothing);
    });

    testWidgets('not enrolled: no strip, not tappable ($mode)', (tester) async {
      var taps = 0;
      await pump(
        tester,
        MyAttendanceCard(
          row: row(AttendanceStatus.untracked,
              e: const TrackedEmployee(name: 'ME', employeeName: 'Muhammad Asif')),
          shift: shift,
          now: now,
          strip: strip,
          onTap: () => taps++,
        ),
        brightness,
      );
      expect(find.text("You're not enrolled on the attendance terminal"), findsOneWidget);
      expect(find.byType(MonthDotStrip), findsNothing);
      await tester.tap(find.text('Not enrolled'));
      expect(taps, 0);
    });

    testWidgets('loading: skeleton, no text ($mode)', (tester) async {
      await pump(
        tester,
        MyAttendanceCard(row: null, shift: shift, now: now, isLoading: true),
        brightness,
      );
      expect(find.byType(MonthDotStrip), findsNothing);
      expect(find.byType(Text), findsNothing);
    });
  }
}
