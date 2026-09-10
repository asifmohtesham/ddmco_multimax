import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_attendance_card.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

// DashboardAttendanceCard across both themes on a phone-width viewport: every
// headline state from the Claude Design frames (mid-morning, before cut-off,
// holiday, offline, loading, one-row Employee viewer), no overflow, and the
// two callbacks.
void main() {
  const shift = ShiftRules(
    name: 'General',
    start: Duration(hours: 8),
    end: Duration(hours: 20),
    graceMinutes: 15,
  );
  final now = DateTime(2026, 9, 9, 10, 42);
  final loadedAt = DateTime(2026, 9, 9, 10, 37);

  TrackedEmployee emp(String id, String name, [String dept = 'Warehouse']) =>
      TrackedEmployee(name: id, employeeName: name, department: dept, deviceId: '1');

  EmployeeDayStatus row(String id, String name, AttendanceStatus st,
          {DateTime? inTime, Duration? lateBy}) =>
      EmployeeDayStatus(
          employee: emp(id, name), status: st, inTime: inTime, lateBy: lateBy);

  final me = row('ME', 'Muhammad Asif', AttendanceStatus.present,
      inTime: DateTime(2026, 9, 9, 7, 48));
  final highlights = [
    row('E1', 'Rashid Al Mansoori', AttendanceStatus.absentSoFar),
    row('E2', 'Priya Nair', AttendanceStatus.absentSoFar),
    row('E3', 'Ayesha Mohammed', AttendanceStatus.late,
        inTime: DateTime(2026, 9, 9, 8, 31), lateBy: const Duration(minutes: 16)),
  ];
  const counts = AttendanceCounts(present: 11, late: 3, notIn: 0, absent: 2, tracked: 16);

  Future<void> pump(WidgetTester tester, Widget child, Brightness brightness) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
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

    testWidgets('mid-morning: headline, tiles, Me line, rows, taps ($mode)',
        (tester) async {
      EmployeeDayStatus? tapped;
      var viewAll = 0;
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: counts,
          shift: shift,
          now: now,
          loadedAt: loadedAt,
          highlights: highlights,
          myRow: me,
          onViewAll: () => viewAll++,
          onRowTap: (r) => tapped = r,
        ),
        brightness,
      );
      expect(find.text('14 of 16 in'), findsOneWidget);
      expect(find.text('3 late · 2 absent so far'), findsOneWidget);
      expect(find.text('Updated 5 min ago'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.byType(EmployeeAttendanceCard), findsNWidgets(3));
      expect(find.text('16 min late'), findsOneWidget);

      await tester.tap(find.text('View all'));
      expect(viewAll, 1);
      await tester.tap(find.text('Priya Nair'));
      expect(tapped?.employee.name, 'E2');
    });

    testWidgets('before cut-off: calm headline, Absent tile dashed ($mode)',
        (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: const AttendanceCounts(present: 6, notIn: 10, tracked: 16),
          shift: shift,
          now: DateTime(2026, 9, 9, 7, 52),
          loadedAt: DateTime(2026, 9, 9, 7, 50),
          beforeCutoff: true,
          highlights: [row('E4', 'Bilal Hussain', AttendanceStatus.notInYet)],
          myRow: me,
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text('Shift starts 08:00'), findsOneWidget);
      expect(find.text('6 in so far · late after 08:15'), findsOneWidget);
      expect(find.text('—'), findsWidgets); // Absent tile (plus blank Out times)
      expect(find.text('Not in yet'), findsOneWidget);
    });

    testWidgets('holiday: Holiday tile, no rows ($mode)', (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: const AttendanceCounts(holiday: 16, tracked: 16),
          shift: shift,
          now: DateTime(2026, 9, 13, 10, 42), // a Sunday
          loadedAt: DateTime(2026, 9, 13, 10, 40),
          isHoliday: true,
          myRow: row('ME', 'Muhammad Asif', AttendanceStatus.holiday),
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text('Holiday today'), findsOneWidget);
      expect(find.text('Sunday · no attendance expected'), findsOneWidget);
      expect(find.text('Holiday'), findsWidgets); // tile label + Me pill
      expect(find.text('16'), findsOneWidget);
      expect(find.byType(EmployeeAttendanceCard), findsNothing);
    });

    testWidgets('offline: last punch shown, rows and Me hidden, all dashed ($mode)',
        (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: const AttendanceCounts(absent: 16, tracked: 16),
          shift: shift,
          now: now,
          loadedAt: loadedAt,
          looksOffline: true,
          latestPunch: DateTime(2026, 8, 28, 19, 52),
          highlights: highlights,
          myRow: row('ME', 'Muhammad Asif', AttendanceStatus.absentSoFar),
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text('No punches yet today'), findsOneWidget);
      expect(find.text('Last punch 28 Aug 19:52 · terminal may be offline'), findsOneWidget);
      expect(find.byType(EmployeeAttendanceCard), findsNothing);
      expect(find.text('You'), findsNothing);
      expect(find.text('—'), findsNWidgets(4));
    });

    testWidgets('loading: skeleton, no rows, no footer ($mode)', (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: const AttendanceCounts(),
          shift: shift,
          now: now,
          isLoading: true,
          highlights: highlights,
          myRow: me,
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text('Updating…'), findsOneWidget);
      expect(find.text('View all'), findsNothing);
      expect(find.byType(EmployeeAttendanceCard), findsNothing);
      expect(find.text('Present'), findsOneWidget); // tile labels stay
    });

    testWidgets('stale data turns the freshness label orange ($mode)', (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: counts,
          shift: shift,
          now: now,
          loadedAt: now.subtract(const Duration(minutes: 42)),
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      final label = tester.widget<Text>(find.text('Updated 42 min ago'));
      expect(label.style?.color,
          brightness == Brightness.dark ? AppColors.orange300 : AppColors.orange700);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('one-row Employee viewer speaks to them directly ($mode)',
        (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: const AttendanceCounts(late: 1, tracked: 1),
          shift: shift,
          now: DateTime(2026, 9, 9, 8, 34),
          loadedAt: DateTime(2026, 9, 9, 8, 34),
          myRow: row('ME', 'Ayesha Mohammed', AttendanceStatus.late,
              inTime: DateTime(2026, 9, 9, 8, 31), lateBy: const Duration(minutes: 16)),
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text("You're in · 08:31"), findsOneWidget);
      expect(find.text('16 min after the 08:15 cut-off'), findsOneWidget);
      expect(find.text('16 min late'), findsOneWidget);
    });
  }
}
