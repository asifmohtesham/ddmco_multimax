# Attendance Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every user their own attendance for today and the month at the top of the Dashboard, and tell only System Managers that the attendance terminal may be offline.

**Architecture:** Pure logic (`buildMonthStrip`, `myAttendanceHeadline`, `unenrolledLabel`) goes in the existing `attendance_logic.dart`, with unit tests. One new controller-free widget (`MyAttendanceCard` + `MonthDotStrip`) is fed by `HomeController`, which adds one request for the viewer's own Attendance rows for the month. The existing team card, Attendance screen and month screen get small, role-aware changes.

**Tech Stack:** Flutter 3.44.4, GetX 4.7.2 (`Obx`, `Rx`), `intl` `DateFormat`, Frappe/HRMS v15 REST via the existing `AttendanceProvider`.

**Spec:** `docs/superpowers/specs/2026-09-10-attendance-visibility-design.md`

## Global Constraints

- Branch: `claude/attendance-terminal-ux-4863b9`. Run `git branch --show-current` right before every commit; stop if it differs.
- Never stage `.claude-flow/` or `.superpowers/`. Stage files by explicit path only.
- Every commit message ends with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never run `dart format`** on existing files. It rewrites whole files to a new style. Hand-format to match the surrounding code.
- Never run `flutter analyze` and `flutter test` at the same time. Run them one after the other; running them together has deadlocked this machine.
- Colours only via `AppColors` / `context.scheme` / `StatusPill.colourForStatus`, never raw Material shades (light = x700 ink, dark = x300).
- Every `Obx` builder must read at least one Rx on **every** return path. GetX 4.7.2 throws "improper use of GetX" otherwise.
- Widget tests use the Ahem font, which inflates text widths about 2×. Give every text in a `Row` `maxLines` + `TextOverflow.ellipsis`, or `Flexible`/`FittedBox`, or the tests overflow.
- Copy strings are exact. Use them verbatim:
  - `Not in yet` / `Punch before {cutoff} to be on time`
  - `No check-in recorded yet` / `Shift started {start}`
  - `In · {HH:mm}` / `On time` / `{n} min late`
  - `Holiday` / `{Weekday} · no attendance expected`
  - `{Month} · {p} present · {l} late · {a} absent` (+ ` · {v} leave` when v > 0)
  - Non-System-Manager offline (screen): `No check-ins recorded yet today` / `Statuses will appear as check-ins arrive.`
  - Non-System-Manager offline (team card): `No check-ins recorded yet` / `Statuses will appear as check-ins arrive`
  - Unenrolled banner: `1 employee isn't enrolled on the terminal` / `{n} employees aren't enrolled on the terminal`
- Test commands run from the worktree root: `flutter test <path>`, `flutter analyze`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `lib/app/modules/hr/attendance/attendance_logic.dart` | + `MonthStrip`, `buildMonthStrip`, `myAttendanceHeadline`, `unenrolledLabel` (pure) | 1 |
| `test/unit/attendance_logic_test.dart` | + unit tests for the above | 1 |
| `lib/app/modules/home/widgets/my_attendance_card.dart` (new) | `MyAttendanceCard` + `MonthDotStrip`, controller-free | 2 |
| `test/widget/my_attendance_card_test.dart` (new) | widget states × themes | 2 |
| `lib/app/modules/home/widgets/dashboard_attendance_card.dart` | remove Me line; `isSystemManager` offline copy | 3 |
| `test/widget/dashboard_attendance_card_test.dart` | update for the above | 3 |
| `lib/app/modules/home/home_controller.dart` | own month ledger, `myMonthStrip`, `isSystemManager`, `showTeamAttendance`, `hasLinkedEmployee`, `openMyMonth` | 4 |
| `lib/app/modules/home/home_screen.dart` | place `MyAttendanceCard`; gate team card | 4 |
| `lib/app/modules/hr/attendance/attendance_controller.dart` | `isSystemManager`, `untrackedCount` | 5 |
| `lib/app/modules/hr/attendance/attendance_screen.dart` | public role-aware `NoPunchesState`; unenrolled banner | 5 |
| `test/widget/attendance_widgets_test.dart` | `NoPunchesState` per role | 5 |
| `lib/app/modules/hr/attendance/month/attendance_month_controller.dart` | shift/holidays from args; self-load holidays | 6 |
| `lib/app/modules/hr/attendance/widgets/employee_detail_sheet.dart` | pass `shift` to the month screen | 6 |

---

### Task 1: Month strip + headline logic (pure)

**Files:**
- Modify: `lib/app/modules/hr/attendance/attendance_logic.dart` (add `intl` import at top; append at end of file)
- Test: `test/unit/attendance_logic_test.dart` (append groups inside `main()`)

**Interfaces:**
- Consumes: existing `deriveDayStatus`, `AttendanceStatus`, `EmployeeDayStatus`, `ShiftRules`, `TrackedEmployee`, `AttendanceRecord`, `kFrappeDate`, `kHHmm`, `dateOnly`.
- Produces:
  - `class MonthStrip { final DateTime month; final List<AttendanceStatus?> days; final int? todayIndex; final int present, late, absent, leave; String get tallyLabel; }`
  - `MonthStrip buildMonthStrip({required DateTime month, required List<AttendanceRecord> ledger, required Set<String> holidays, required EmployeeDayStatus? today, required DateTime now, required ShiftRules shift, required TrackedEmployee employee})`
  - `(String, String) myAttendanceHeadline(EmployeeDayStatus row, ShiftRules shift, DateTime now)`
  - `String unenrolledLabel(int n)`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `test/unit/attendance_logic_test.dart`, after the last existing group. The file already defines `shift` (08:00, grace 15) and `tracked` (`HR-EMP-00001`, deviceId `7`).

```dart
  group('buildMonthStrip', () {
    final sep = DateTime(2026, 9);
    const hol = {'2026-09-06', '2026-09-13', '2026-09-20', '2026-09-27'};
    AttendanceRecord rec(int d, String status, {bool late = false, String leave = ''}) =>
        AttendanceRecord(
          name: 'ATT-$d',
          employee: tracked.name,
          employeeName: tracked.employeeName,
          date: DateTime(2026, 9, d),
          status: status,
          lateEntry: late,
          inTime: status == 'Present'
              ? DateTime(2026, 9, d, late ? 8 : 7, late ? 30 : 55)
              : null,
          leaveType: leave,
        );
    // 1–9 Sep: 5 present, 2 late (3rd, 8th), 1 absent (5th), Sun 6th holiday.
    final ledger = [
      rec(1, 'Present'), rec(2, 'Present'), rec(3, 'Present', late: true),
      rec(4, 'Present'), rec(5, 'Absent'), rec(7, 'Present'),
      rec(8, 'Present', late: true), rec(9, 'Present'),
    ];
    MonthStrip strip({
      List<AttendanceRecord>? l,
      AttendanceStatus todaySt = AttendanceStatus.notInYet,
      DateTime? now,
      DateTime? month,
    }) =>
        buildMonthStrip(
          month: month ?? sep,
          ledger: l ?? ledger,
          holidays: hol,
          today: EmployeeDayStatus(employee: tracked, status: todaySt),
          now: now ?? DateTime(2026, 9, 10, 8, 32),
          shift: shift,
          employee: tracked,
        );

    test('September so far: 5 present, 2 late, 1 absent, Sunday holiday', () {
      final s = strip();
      expect(s.days.length, 30);
      expect(s.days[0], AttendanceStatus.present);
      expect(s.days[2], AttendanceStatus.late);
      expect(s.days[4], AttendanceStatus.absent);
      expect(s.days[5], AttendanceStatus.holiday);
      expect((s.present, s.late, s.absent, s.leave), (5, 2, 1, 0));
      expect(s.tallyLabel, 'September · 5 present · 2 late · 1 absent');
    });

    test('today pending is null with todayIndex; future days null', () {
      final s = strip();
      expect(s.todayIndex, 9);
      expect(s.days[9], isNull);
      expect(s.days[10], isNull);
      expect(s.days[12], isNull); // a future Sunday stays faint
    });

    test('today late is drawn and counted once', () {
      final s = strip(todaySt: AttendanceStatus.late);
      expect(s.days[9], AttendanceStatus.late);
      expect(s.late, 3);
    });

    test('past working day with no ledger row is unknown, not absent', () {
      final s = strip(l: [rec(1, 'Present')]);
      expect(s.days[1], isNull);
      expect(s.absent, 0);
    });

    test('On Leave counts as leave and appears in the tally', () {
      final s = strip(l: [rec(2, 'On Leave', leave: 'Casual Leave')]);
      expect(s.days[1], AttendanceStatus.onLeave);
      expect(s.leave, 1);
      expect(s.tallyLabel, 'September · 0 present · 0 late · 0 absent · 1 leave');
    });

    test('a past month has no today', () {
      final s = strip(month: DateTime(2026, 8), l: const [], now: DateTime(2026, 9, 10, 9));
      expect(s.days.length, 31);
      expect(s.todayIndex, isNull);
    });

    test('February 2027 has 28 days', () {
      final s = strip(month: DateTime(2027, 2), l: const [], now: DateTime(2027, 2, 1, 9));
      expect(s.days.length, 28);
      expect(s.todayIndex, 0);
    });
  });

  group('myAttendanceHeadline', () {
    final now = DateTime(2026, 9, 10, 8, 32); // a Thursday
    (String, String) h(AttendanceStatus s, {DateTime? inTime, Duration? lateBy}) =>
        myAttendanceHeadline(
            EmployeeDayStatus(employee: tracked, status: s, inTime: inTime, lateBy: lateBy),
            shift,
            now);

    test('before the cut-off tells them what to do', () {
      expect(h(AttendanceStatus.notInYet), ('Not in yet', 'Punch before 08:15 to be on time'));
    });
    test('after the cut-off is true whatever the cause', () {
      expect(h(AttendanceStatus.absentSoFar), ('No check-in recorded yet', 'Shift started 08:00'));
    });
    test('on time', () {
      expect(h(AttendanceStatus.present, inTime: DateTime(2026, 9, 10, 7, 58)),
          ('In · 07:58', 'On time'));
    });
    test('late', () {
      expect(
          h(AttendanceStatus.late,
              inTime: DateTime(2026, 9, 10, 8, 27), lateBy: const Duration(minutes: 12)),
          ('In · 08:27', '12 min late'));
    });
    test('holiday names the weekday', () {
      expect(h(AttendanceStatus.holiday), ('Holiday', 'Thursday · no attendance expected'));
    });
  });

  test('unenrolledLabel pluralises', () {
    expect(unenrolledLabel(1), "1 employee isn't enrolled on the terminal");
    expect(unenrolledLabel(10), "10 employees aren't enrolled on the terminal");
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/attendance_logic_test.dart`
Expected: compilation FAIL, with `buildMonthStrip`, `MonthStrip`, `myAttendanceHeadline`, `unenrolledLabel` undefined.

- [ ] **Step 3: Implement**

At the top of `lib/app/modules/hr/attendance/attendance_logic.dart`, add below the existing import:

```dart
import 'package:intl/intl.dart';
```

Append to the end of the file:

```dart
/// One employee's month for the Dashboard dot strip: a status (or null) per
/// calendar day plus the counts behind the tally line.
class MonthStrip {
  final DateTime month;

  /// Index 0 is the 1st. Null means nothing to draw: a future day, today
  /// while still pending, or a past working day HRMS has not processed.
  final List<AttendanceStatus?> days;

  /// Index of today within [days]; null when [month] is not the current one.
  final int? todayIndex;
  final int present, late, absent, leave;

  const MonthStrip({
    required this.month,
    required this.days,
    this.todayIndex,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.leave = 0,
  });

  /// "September · 5 present · 2 late · 1 absent" (+ " · 1 leave").
  String get tallyLabel =>
      '${DateFormat('MMMM').format(month)} · $present present · $late late · $absent absent'
      '${leave > 0 ? ' · $leave leave' : ''}';
}

/// Builds the [MonthStrip] for [month]. Past days trust [ledger] (the
/// viewer's own rows; `late_entry` → Late), holidays read Holiday, today comes
/// from [today] (Not in yet / Absent so far stay null — the day is not over),
/// future days are null. Late is counted apart from present.
MonthStrip buildMonthStrip({
  required DateTime month,
  required List<AttendanceRecord> ledger,
  required Set<String> holidays,
  required EmployeeDayStatus? today,
  required DateTime now,
  required ShiftRules shift,
  required TrackedEmployee employee,
}) {
  final first = DateTime(month.year, month.month);
  final dayCount = DateTime(month.year, month.month + 1, 0).day;
  final todayDate = dateOnly(now);
  final byDate = {for (final r in ledger) kFrappeDate.format(r.date): r};
  final days = <AttendanceStatus?>[];
  int? todayIndex;
  // Short names like AttendanceCounts.of — `late` is a Dart contextual keyword.
  var p = 0, l = 0, a = 0, v = 0;

  for (var i = 0; i < dayCount; i++) {
    final d = DateTime(first.year, first.month, i + 1);
    final key = kFrappeDate.format(d);
    AttendanceStatus? st;
    if (d == todayDate) {
      todayIndex = i;
      final t = today?.status;
      st = t == AttendanceStatus.notInYet || t == AttendanceStatus.absentSoFar ? null : t;
    } else if (d.isAfter(todayDate)) {
      st = null;
    } else if (byDate[key] != null) {
      st = deriveDayStatus(
        employee: employee,
        day: d,
        now: now,
        shift: shift,
        isHoliday: false,
        ledger: byDate[key],
      ).status;
    } else if (holidays.contains(key)) {
      st = AttendanceStatus.holiday;
    }
    switch (st) {
      case AttendanceStatus.present:
      case AttendanceStatus.halfDay:
      case AttendanceStatus.workFromHome:
        p++;
      case AttendanceStatus.late:
        l++;
      case AttendanceStatus.absent:
        a++;
      case AttendanceStatus.onLeave:
        v++;
      default:
        break;
    }
    days.add(st);
  }

  return MonthStrip(
    month: first,
    days: days,
    todayIndex: todayIndex,
    present: p,
    late: l,
    absent: a,
    leave: v,
  );
}

/// Headline + sub-line for the viewer's own "My attendance" block. Wording
/// never blames the terminal: "No check-in recorded yet" is true whether the
/// person or the device is at fault.
(String, String) myAttendanceHeadline(
        EmployeeDayStatus row, ShiftRules shift, DateTime now) =>
    switch (row.status) {
      AttendanceStatus.notInYet =>
        ('Not in yet', 'Punch before ${shift.cutoffLabel} to be on time'),
      AttendanceStatus.absentSoFar =>
        ('No check-in recorded yet', 'Shift started ${shift.startLabel}'),
      AttendanceStatus.present || AttendanceStatus.late => (
          row.inTime == null ? row.status.label : 'In · ${kHHmm.format(row.inTime!)}',
          row.lateBy != null && row.lateBy!.inMinutes > 0
              ? '${row.lateBy!.inMinutes} min late'
              : 'On time',
        ),
      AttendanceStatus.holiday =>
        ('Holiday', '${DateFormat('EEEE').format(now)} · no attendance expected'),
      AttendanceStatus.absent => ('Absent', 'No check-in recorded'),
      AttendanceStatus.untracked =>
        ('Not enrolled', "You're not enrolled on the attendance terminal"),
      _ => (row.status.label, row.ledger?.leaveType ?? ''),
    };

/// System-Manager banner copy on the Attendance screen.
String unenrolledLabel(int n) => n == 1
    ? "1 employee isn't enrolled on the terminal"
    : "$n employees aren't enrolled on the terminal";
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/attendance_logic_test.dart`
Expected: all tests PASS (existing + 13 new).

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # must print claude/attendance-terminal-ux-4863b9
git add lib/app/modules/hr/attendance/attendance_logic.dart test/unit/attendance_logic_test.dart
git commit -m "feat(attendance): month strip + own-attendance headline logic

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `MyAttendanceCard` widget (layout B)

**Files:**
- Create: `lib/app/modules/home/widgets/my_attendance_card.dart`
- Test: `test/widget/my_attendance_card_test.dart`

**Interfaces:**
- Consumes: `MonthStrip`, `myAttendanceHeadline` (Task 1); `employeeImage(String?)` from `lib/app/modules/hr/attendance/widgets/employee_attendance_card.dart`; `AppAvatar`; `StatusPill.colourForStatus(String, {Brightness brightness}) → (Color bg, Color ink)`; `context.scheme` (`fg`, `border`, `subtle`, `text`, `textMuted`, `textSubtle`); `AppRadius`.
- Produces:
  - `MyAttendanceCard({Key? key, required EmployeeDayStatus? row, required ShiftRules shift, required DateTime now, MonthStrip? strip, bool isLoading = false, VoidCallback? onTap})`
  - `MonthDotStrip({Key? key, required MonthStrip strip})`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/my_attendance_card_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/my_attendance_card_test.dart`
Expected: compilation FAIL (`my_attendance_card.dart` not found).

- [ ] **Step 3: Implement**

Create `lib/app/modules/home/widgets/my_attendance_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';
import 'package:multimax/app/modules/hr/attendance/widgets/employee_attendance_card.dart';

/// "My attendance" on the Dashboard (spec §3.1, layout B): the viewer's own
/// status today, a dot per day of the month and the month tally. Public and
/// controller-free like DashboardAttendanceCard, so widget tests can pump
/// every state.
class MyAttendanceCard extends StatelessWidget {
  const MyAttendanceCard({
    super.key,
    required this.row,
    required this.shift,
    required this.now,
    this.strip,
    this.isLoading = false,
    this.onTap,
  });

  /// The viewer's own row; null while the first load is in flight.
  final EmployeeDayStatus? row;
  final ShiftRules shift;
  final DateTime now;

  /// Null when the month ledger could not be loaded: headline only.
  final MonthStrip? strip;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final r = row;
    final tappable = r != null && r.employee.isTracked;
    return Material(
      color: s.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: tappable ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: s.border),
          ),
          child: r == null ? _skeleton(s) : _content(context, r),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, EmployeeDayStatus r) {
    final s = context.scheme;
    final e = r.employee;
    final (h1, h2) = myAttendanceHeadline(r, shift, now);
    final st = strip;
    final showMonth = st != null && e.isTracked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppAvatar(initials: e.initials, image: employeeImage(e.image), size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: s.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    h2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: s.textMuted),
                  ),
                ],
              ),
            ),
            if (e.isTracked) Icon(Icons.chevron_right, size: 18, color: s.textSubtle),
          ],
        ),
        if (showMonth) ...[
          const SizedBox(height: 10),
          MonthDotStrip(strip: st),
          const SizedBox(height: 8),
          Text(
            st.tallyLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: s.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  Widget _skeleton(AppScheme s) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: s.subtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: s.subtle, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(110, 15), const SizedBox(height: 6), bar(160, 11)],
            ),
          ],
        ),
        const SizedBox(height: 10),
        bar(double.infinity, 34),
      ],
    );
  }
}

/// Two rows of up to 16 dots (1st–16th, 17th–end). Colours come from the
/// StatusPill ramp so a dot always matches its pill; unknown and future days
/// are faint; today is outlined, and hollow until it has a status.
class MonthDotStrip extends StatelessWidget {
  const MonthDotStrip({super.key, required this.strip});
  final MonthStrip strip;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final b = Theme.of(context).brightness;
    final n = strip.days.length;

    Widget dot(int i) {
      final st = strip.days[i];
      final isToday = i == strip.todayIndex;
      final fill = st == null
          ? (isToday ? Colors.transparent : s.subtle)
          : StatusPill.colourForStatus(st.label, brightness: b).$2;
      return Padding(
        padding: const EdgeInsets.all(2),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
              border: isToday ? Border.all(color: s.text, width: 1.5) : null,
            ),
          ),
        ),
      );
    }

    Widget line(int from) => Row(
          children: [
            for (var i = from; i < from + 16; i++)
              Expanded(child: i < n ? dot(i) : const SizedBox.shrink()),
          ],
        );

    return Semantics(
      label: strip.tallyLabel,
      child: ExcludeSemantics(
        child: Column(children: [line(0), line(16)]),
      ),
    );
  }
}
```

`context.scheme` is `AppScheme get scheme` on `extension AppSchemeX on BuildContext` (`lib/app/data/constants/app_theme.dart`), and `AppScheme` is exported from the already-imported `app_theme.dart`, so `_skeleton(AppScheme s)` needs no extra import.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/my_attendance_card_test.dart`
Expected: 16 tests PASS (8 states × 2 themes), no overflow exceptions.

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # must print claude/attendance-terminal-ux-4863b9
git add lib/app/modules/home/widgets/my_attendance_card.dart test/widget/my_attendance_card_test.dart
git commit -m "feat(dashboard): MyAttendanceCard with month dot strip

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Team card — drop the Me line, System-Manager-only offline copy

**Files:**
- Modify: `lib/app/modules/home/widgets/dashboard_attendance_card.dart`
- Test: `test/widget/dashboard_attendance_card_test.dart`

**Interfaces:**
- Produces: `DashboardAttendanceCard` loses the `myRow` parameter and gains `bool isSystemManager = false`. Task 4 passes `isSystemManager:` and no longer passes `myRow:`.

- [ ] **Step 1: Update the tests first**

In `test/widget/dashboard_attendance_card_test.dart`:

1. Delete the `final me = row('ME', 'Muhammad Asif', ...)` declaration (two lines).
2. Remove every `myRow: ...,` argument (in the mid-morning, before cut-off, holiday, offline and loading tests).
3. In the mid-morning test, rename it to `'mid-morning: headline, tiles, rows, taps ($mode)'` and replace `expect(find.text('You'), findsOneWidget);` with `expect(find.text('You'), findsNothing);`.
4. In the holiday test, change the comment `// tile label + Me pill` to `// tile label`.
5. Replace the whole `'offline: last punch shown, rows and Me hidden, all dashed ($mode)'` test with these two tests:

```dart
    testWidgets('offline, System Manager: terminal diagnosis, all dashed ($mode)',
        (tester) async {
      await pump(
        tester,
        DashboardAttendanceCard(
          counts: const AttendanceCounts(absent: 16, tracked: 16),
          shift: shift,
          now: now,
          loadedAt: loadedAt,
          looksOffline: true,
          isSystemManager: true,
          latestPunch: DateTime(2026, 8, 28, 19, 52),
          highlights: highlights,
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text('No punches yet today'), findsOneWidget);
      expect(find.text('Last punch 28 Aug 19:52 · terminal may be offline'), findsOneWidget);
      expect(find.byType(EmployeeAttendanceCard), findsNothing);
      expect(find.text('—'), findsNWidgets(4));
    });

    testWidgets('offline, everyone else: no terminal mention ($mode)', (tester) async {
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
          onViewAll: () {},
          onRowTap: (_) {},
        ),
        brightness,
      );
      expect(find.text('No check-ins recorded yet'), findsOneWidget);
      expect(find.text('Statuses will appear as check-ins arrive'), findsOneWidget);
      expect(find.textContaining('terminal'), findsNothing);
      expect(find.textContaining('Last punch'), findsNothing);
    });
```

6. Delete the whole `'one-row Employee viewer speaks to them directly ($mode)'` test. That viewer no longer sees the team card; "My attendance" replaces it.
7. Update the file's header comment: replace `(mid-morning, before cut-off, holiday, offline, loading, one-row Employee viewer)` with `(mid-morning, before cut-off, holiday, offline per role, loading)`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/dashboard_attendance_card_test.dart`
Expected: compilation FAIL (`isSystemManager` is not a parameter).

- [ ] **Step 3: Implement**

In `lib/app/modules/home/widgets/dashboard_attendance_card.dart`:

1. Replace the class doc comment's last two lines:

```dart
/// Everything inside is reused from the Attendance screen; the only decision
/// made here is which headline / tile / row set fits the day:
/// holiday › beforeCutoff › looksOffline › counts. The viewer's own status
/// lives in MyAttendanceCard, and only a System Manager is told the terminal
/// may be offline.
```

(Also change the first doc line `"Today's attendance" summary on the Dashboard — headline, four count` / `tiles, the viewer's own row, up to three attention-first employee rows and` to `tiles, up to three attention-first employee rows and`.)

2. In the constructor, replace `this.myRow,` with `this.isSystemManager = false,`.
3. Replace the field `final EmployeeDayStatus? myRow;` with:

```dart
  /// Only a System Manager sees the terminal diagnosis (spec §3.3).
  final bool isSystemManager;
```

4. Delete the `_selfOnly` getter and its doc comment (the 3 lines starting `/// An Employee-role viewer gets only their own row back`).
5. In `build`, delete `final me = _showRows ? myRow : null;` and the block:

```dart
            if (me != null) ...[
              const SizedBox(height: 12),
              _MeLine(row: me),
            ],
```

6. In `_copy()`, replace the `if (looksOffline) { ... }` block with:

```dart
    if (looksOffline) {
      if (!isSystemManager) {
        return ('No check-ins recorded yet', 'Statuses will appear as check-ins arrive');
      }
      final last = latestPunch == null
          ? 'terminal may be offline'
          : 'Last punch ${DateFormat('d MMM HH:mm').format(latestPunch!)} · terminal may be offline';
      return ('No punches yet today', last);
    }
```

and delete the whole `if (_selfOnly) { ... }` block that follows it.

7. Delete the whole `_MeLine` class (from `/// The viewer's own row — the only tinted block` through its closing `}`).
8. Remove the now-unused imports `package:multimax/app/modules/global_widgets/app_avatar.dart` and `package:multimax/app/modules/global_widgets/status_pill.dart`. Keep `employee_attendance_card.dart`, which `EmployeeAttendanceCard` still uses.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widget/dashboard_attendance_card_test.dart`
Expected: all PASS (7 tests × 2 themes = 14: mid-morning, before cut-off, holiday, offline System Manager, offline everyone else, loading, stale).

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # must print claude/attendance-terminal-ux-4863b9
git add lib/app/modules/home/widgets/dashboard_attendance_card.dart test/widget/dashboard_attendance_card_test.dart
git commit -m "feat(dashboard): team card offline copy for System Managers only, drop Me line

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Dashboard wiring (controller + screen)

**Files:**
- Modify: `lib/app/modules/home/home_controller.dart` (attendance block, around lines 150–256)
- Modify: `lib/app/modules/home/home_screen.dart` (imports; greeting block around line 76; `_buildTodayAttendance` around lines 309–360)

**Interfaces:**
- Consumes: `buildMonthStrip`, `MonthStrip` (Task 1); `MyAttendanceCard` (Task 2); `DashboardAttendanceCard(isSystemManager:)` (Task 3); `AppRoutes.ATTENDANCE_MONTH` month-screen arguments `{employee, month, today, shift, holidays}` (Task 6 reads `shift` / `holidays`; before Task 6 lands they are ignored, which is harmless).
- Produces on `HomeController`: `Rxn<List<AttendanceRecord>> myMonthLedger`, `bool get hasLinkedEmployee`, `bool get isSystemManager`, `bool get showTeamAttendance`, `MonthStrip? get myMonthStrip`, `void openMyMonth()`.

There's no unit test for this task. `HomeController` needs the full GetX harness (see `test/unit/home_controller_actionable_test.dart`), and the new members are one-line getters over logic already tested in Task 1. Verification is `flutter analyze` plus the Task 7 on-device smoke test.

- [ ] **Step 1: Controller — new members**

In `home_controller.dart`, directly after the `myAttendance` getter (ends `return attendanceRows.firstWhereOrNull((r) => r.employee.name == id);` / `}`), insert:

```dart

  /// The viewer's own Attendance rows from the 1st to yesterday. Today stays
  /// punch-derived until HRMS writes its row after 22:00, so one source per
  /// day. Null = not loaded or the request failed → headline only.
  final myMonthLedger = Rxn<List<AttendanceRecord>>();

  bool get hasLinkedEmployee =>
      (_authController.currentUser.value?.employeeId ?? '').isNotEmpty;

  /// Only a System Manager is told the terminal may be offline.
  bool get isSystemManager =>
      _authController.currentUser.value?.hasRole('System Manager') ?? false;

  /// The team card only helps viewers who can see more than their own row;
  /// for an Employee-role viewer it would duplicate "My attendance".
  bool get showTeamAttendance => attendanceCounts.tracked > 1;

  MonthStrip? get myMonthStrip {
    final me = myAttendance;
    final ledger = myMonthLedger.value;
    if (me == null || ledger == null || !me.employee.isTracked) return null;
    final now = DateTime.now();
    return buildMonthStrip(
      month: DateTime(now.year, now.month),
      ledger: ledger,
      holidays: attendanceHolidays,
      today: me,
      now: now,
      shift: attendanceShift.value,
      employee: me.employee,
    );
  }

  /// Opens the viewer's own month calendar with the dashboard's shift and
  /// holidays, so Sundays and late minutes match (no dependency on the
  /// Attendance list screen being underneath).
  void openMyMonth() {
    final me = myAttendance;
    if (me == null || !me.employee.isTracked) return;
    final now = DateTime.now();
    Get.toNamed(AppRoutes.ATTENDANCE_MONTH, arguments: {
      'employee': me.employee,
      'month': DateTime(now.year, now.month),
      'today': me,
      'shift': attendanceShift.value,
      'holidays': attendanceHolidays.toSet(),
    });
  }

  /// Own rows 1st → yesterday; `[]` on the 1st, null when not linked or failed.
  Future<List<AttendanceRecord>?> _fetchMyMonth(DateTime today) async {
    final id = _authController.currentUser.value?.employeeId;
    if (id == null || id.isEmpty) return null;
    if (today.day == 1) return const [];
    try {
      return await _attendanceProvider.fetchAttendance(
        DateTime(today.year, today.month),
        today.subtract(const Duration(days: 1)),
        employee: id,
      );
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 2: Controller — fetch the month with today's data**

In `fetchTodayAttendance`, replace:

```dart
      final results = await Future.wait([
        _attendanceProvider.fetchCheckins(today),
        _attendanceProvider.fetchAttendance(today, today),
      ]);
      final checkins = results[0] as List<EmployeeCheckin>;
      final ledger = results[1] as List<AttendanceRecord>;
```

with:

```dart
      final results = await Future.wait<Object?>([
        _attendanceProvider.fetchCheckins(today),
        _attendanceProvider.fetchAttendance(today, today),
        _fetchMyMonth(today),
      ]);
      final checkins = results[0] as List<EmployeeCheckin>;
      final ledger = results[1] as List<AttendanceRecord>;
      myMonthLedger.value = results[2] as List<AttendanceRecord>?;
```

- [ ] **Step 3: Screen — place "My attendance" under the greeting**

In `home_screen.dart`, add the import next to the other home widget imports:

```dart
import 'package:multimax/app/modules/home/widgets/my_attendance_card.dart';
```

Replace:

```dart
                  // 1 ── Greeting + context chip ──────────────────────────────
                  _buildGreeting(context),
                  const SizedBox(height: 18),
```

with:

```dart
                  // 1 ── Greeting + context chip ──────────────────────────────
                  _buildGreeting(context),
                  const SizedBox(height: 18),

                  // 1b ── My attendance: own day + month, above the fold ──────
                  _buildMyAttendance(),
```

Add this method directly above the `// Today's attendance — site-wide summary` comment block:

```dart
  // ---------------------------------------------------------------------------
  // My attendance — the viewer's own status today + the month dot strip.
  // Hidden without a linked Employee or Attendance access (the Employee role
  // has read on Attendance, so ordinary staff see their own).
  // ---------------------------------------------------------------------------
  Widget _buildMyAttendance() {
    return Obx(() {
      // hasLinkedEmployee reads currentUser (an Rx) on every path — keep it first.
      if (!controller.hasLinkedEmployee || !controller.attendanceVisible) {
        return const SizedBox.shrink();
      }
      final me = controller.myAttendance;
      final loading = controller.isLoadingAttendance.value &&
          controller.attendanceLoadedAt.value == null;
      if (me == null && !loading) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: MyAttendanceCard(
          row: me,
          shift: controller.attendanceShift.value,
          now: DateTime.now(),
          strip: controller.myMonthStrip,
          isLoading: loading,
          onTap: controller.openMyMonth,
        ),
      );
    });
  }

```

- [ ] **Step 4: Screen — gate the team card, pass the role**

In `_buildTodayAttendance`:

1. Replace the method's header comment lines `// terminal is one site, and the "Me" line is always the logged-in employee.` with `// terminal is one site. Hidden for self-only viewers (MyAttendanceCard covers them).`
2. After `if (!loading && rows.isEmpty) return const SizedBox.shrink();` add:

```dart
      if (!loading && !controller.showTeamAttendance) return const SizedBox.shrink();
```

3. In the `DashboardAttendanceCard(` arguments, replace `myRow: controller.myAttendance,` with `isSystemManager: controller.isSystemManager,`.

- [ ] **Step 5: Analyze the touched files**

Run: `flutter analyze lib/app/modules/home`
Expected: `No issues found!` No import becomes unused: `home_screen.dart` still uses `EmployeeDayStatus` (in `onRowTap`) and `dashboardAttendanceHighlights`, and `home_controller.dart` already imports `attendance_logic.dart` and `AppRoutes`.

- [ ] **Step 6: Run the dashboard tests**

Run: `flutter test test/widget/dashboard_attendance_card_test.dart test/widget/my_attendance_card_test.dart test/unit/home_controller_actionable_test.dart`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git branch --show-current   # must print claude/attendance-terminal-ux-4863b9
git add lib/app/modules/home/home_controller.dart lib/app/modules/home/home_screen.dart
git commit -m "feat(dashboard): My attendance above the fold; team card for multi-row viewers

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Attendance screen — role-aware no-punches state + unenrolled banner

**Files:**
- Modify: `lib/app/modules/hr/attendance/attendance_controller.dart`
- Modify: `lib/app/modules/hr/attendance/attendance_screen.dart` (`_TerminalOffline` class around lines 320–357; its use around line 168; `_buildList` children around line 208)
- Test: `test/widget/attendance_widgets_test.dart`

**Interfaces:**
- Consumes: `unenrolledLabel` (Task 1).
- Produces: `NoPunchesState({Key? key, required EmployeeCheckin? latest, required bool isSystemManager, required VoidCallback onReload})` (public, in `attendance_screen.dart`); `AttendanceController.isSystemManager`, `AttendanceController.untrackedCount`.

- [ ] **Step 1: Write the failing widget tests**

In `test/widget/attendance_widgets_test.dart`, add the import:

```dart
import 'package:multimax/app/modules/hr/attendance/attendance_screen.dart';
```

and append inside `main()` (after the last test):

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/attendance_widgets_test.dart`
Expected: compilation FAIL (`NoPunchesState` undefined).

- [ ] **Step 3: Controller getters**

In `attendance_controller.dart`, add the import:

```dart
import 'package:multimax/app/modules/auth/authentication_controller.dart';
```

and, after the `looksOffline` getter, add:

```dart

  /// Only a System Manager is told the terminal may be offline; everyone else
  /// can't tell a dead terminal from nobody punching (spec §2).
  bool get isSystemManager =>
      Get.isRegistered<AuthenticationController>() &&
      (Get.find<AuthenticationController>().currentUser.value?.hasRole('System Manager') ??
          false);

  /// Active employees with no terminal ID — HRMS marks them Absent every day.
  int get untrackedCount => employees.where((e) => !e.isTracked).length;
```

- [ ] **Step 4: Screen — replace `_TerminalOffline` with public `NoPunchesState`**

Replace the whole `_TerminalOffline` class (from `class _TerminalOffline extends StatelessWidget {` through the closing `}` after its `_mon` helper) with:

```dart
/// Today, past the cut-off, with no punches for anyone. Only a System Manager
/// sees the terminal diagnosis and the last punch; everyone else gets wording
/// that is true whatever the cause (spec §3.3). Controller-free for tests.
class NoPunchesState extends StatelessWidget {
  const NoPunchesState({
    super.key,
    required this.latest,
    required this.isSystemManager,
    required this.onReload,
  });

  final EmployeeCheckin? latest;
  final bool isSystemManager;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final since = latest == null ? '' : ' since ${latest!.time.day} ${_mon(latest!.time.month)}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ListEmptyState(
          hasActiveFilters: false,
          emptyIcon: Icons.cloud_off_outlined,
          emptyTitle: isSystemManager ? 'No punches$since' : 'No check-ins recorded yet today',
          emptyMessage: isSystemManager
              ? "The attendance terminal may be offline. Employee statuses can't be worked out until it reconnects."
              : 'Statuses will appear as check-ins arrive.',
          filteredTitle: '',
          filteredMessage: '',
          onClearFilters: () {},
          onReload: onReload,
        ),
        if (isSystemManager && latest != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Text(
              'Last punch · ${latest!.time.day} ${_mon(latest!.time.month)}, ${kHHmm.format(latest!.time)}',
              style: TextStyle(fontSize: 12, color: s.textSubtle),
            ),
          ),
      ],
    );
  }

  static String _mon(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}
```

and replace its use in `build`:

```dart
                        child: _TerminalOffline(latest: controller.latestPunch.value),
```

with:

```dart
                        child: NoPunchesState(
                          latest: controller.latestPunch.value,
                          isSystemManager: controller.isSystemManager,
                          onReload: controller.loadDay,
                        ),
```

- [ ] **Step 5: Screen — unenrolled banner (System Manager only)**

In `_buildList`, in the `children` list, directly after the `ResultCountPill` `Padding(...)` entry and before `if (controller.isHoliday)`, insert:

```dart
      if (controller.isSystemManager && controller.untrackedCount > 0 && !controller.hasFilters)
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => controller.toggleStatusFilter('Not tracked'),
          child: _Banner(
            icon: Icons.person_off_outlined,
            calm: true,
            child: Text(unenrolledLabel(controller.untrackedCount)),
          ),
        ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/widget/attendance_widgets_test.dart`
Expected: all PASS (existing 5 + 2 new).

- [ ] **Step 7: Commit**

```bash
git branch --show-current   # must print claude/attendance-terminal-ux-4863b9
git add lib/app/modules/hr/attendance/attendance_controller.dart lib/app/modules/hr/attendance/attendance_screen.dart test/widget/attendance_widgets_test.dart
git commit -m "feat(attendance): terminal-offline copy for System Managers only; unenrolled nudge

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Month screen gets its own shift + holidays

**Files:**
- Modify: `lib/app/modules/hr/attendance/month/attendance_month_controller.dart` (`onInit` lines 26–39, `load` lines 58–67, the `shift` doc comment lines 22–24)
- Modify: `lib/app/modules/hr/attendance/widgets/employee_detail_sheet.dart` (arguments map, around line 132)

**Interfaces:**
- Consumes: route arguments `{'employee': TrackedEmployee, 'month': DateTime?, 'today': EmployeeDayStatus?, 'shift': ShiftRules?, 'holidays': Set<String>?}` (Task 4 sends all five; the detail sheet sends `shift` after this task).

There's no automated test here, because the controller reads `Get.arguments` and would need a routing harness for a three-step fallback. It's covered by Task 7's smoke steps 3 and 4.

- [ ] **Step 1: Controller — resolve shift/holidays from args first**

Replace the `shift` field's doc comment:

```dart
  /// Real shift rules from the list screen when it is underneath us; the
  /// fallback only matters for "minutes late" on ledger rows.
  ShiftRules shift = ShiftRules.fallback;
```

with:

```dart
  /// Shift rules and holidays come from the route arguments (Dashboard,
  /// detail sheet), else the list screen if it is underneath us; [load]
  /// fetches holidays itself if still unknown, so every entry path shows
  /// Sundays and real late minutes.
  ShiftRules shift = ShiftRules.fallback;
```

In `onInit`, replace:

```dart
    today = args['today'] as EmployeeDayStatus?;
    if (Get.isRegistered<AttendanceController>()) {
      final list = Get.find<AttendanceController>();
      holidays.assignAll(list.holidays);
      shift = list.shift.value;
    }
```

with:

```dart
    today = args['today'] as EmployeeDayStatus?;
    final list = Get.isRegistered<AttendanceController>()
        ? Get.find<AttendanceController>()
        : null;
    shift = args['shift'] as ShiftRules? ?? list?.shift.value ?? ShiftRules.fallback;
    holidays.assignAll(args['holidays'] as Set<String>? ?? list?.holidays ?? const <String>{});
```

- [ ] **Step 2: Controller — self-load holidays**

In `load()`, replace:

```dart
    try {
      records.assignAll(await _provider.fetchAttendance(first, last, employee: employee.name));
```

with:

```dart
    try {
      if (holidays.isEmpty && shift.holidayList.isNotEmpty) {
        try {
          holidays.assignAll(await _provider.fetchHolidays(shift.holidayList));
        } catch (_) {} // a month without holiday labels beats no month
      }
      records.assignAll(await _provider.fetchAttendance(first, last, employee: employee.name));
```

- [ ] **Step 3: Detail sheet passes the shift**

In `employee_detail_sheet.dart`, replace:

```dart
                  Get.toNamed(AppRoutes.ATTENDANCE_MONTH, arguments: {
                    'employee': e,
                    'month': DateTime(day.year, day.month),
                    'today': row,
                  });
```

with:

```dart
                  Get.toNamed(AppRoutes.ATTENDANCE_MONTH, arguments: {
                    'employee': e,
                    'month': DateTime(day.year, day.month),
                    'today': row,
                    'shift': shift,
                  });
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/app/modules/hr`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # must print claude/attendance-terminal-ux-4863b9
git add lib/app/modules/hr/attendance/month/attendance_month_controller.dart lib/app/modules/hr/attendance/widgets/employee_detail_sheet.dart
git commit -m "fix(attendance): month screen resolves shift + holidays on every entry path

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Full verification + on-device smoke

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: `No issues found!` Wait for it to finish before Step 2.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all pass. The baseline on `c35bd6a5` was 1244 passing, 0 failing; expect about 1244 − 2 (one-row viewer test × 2 themes removed) + 2 (offline split adds one per theme) + 13 (unit) + 16 (MyAttendanceCard) + 2 (NoPunchesState) ≈ **1275**. If the count is different, explain why before moving on; don't just accept it.

If you see "Failed to load" errors for a package, the pub cache is corrupt: run `dart pub cache repair`, then re-run.

- [ ] **Step 3: On-device smoke (Pixel 7, debug build). Record results per step.**

1. **System Manager session** (e.g. `asif@multimax.cloud`): Dashboard shows "My attendance" under the greeting with the dot strip and the month tally. The team card is still below Quick Create / Needs attention. With the terminal quiet, the team card and the Attendance screen say "terminal may be offline" with the last punch. The Attendance screen shows the "{n} employees aren't enrolled on the terminal" banner, and tapping it filters to Not tracked.
2. **Employee-role session** (e.g. Jawwad): "My attendance" shows. **No** team card. The Attendance screen, when there are no punches, says "No check-ins recorded yet today" with no terminal mention, no last-punch line and no unenrolled banner.
3. From "My attendance", tap → the month screen opens for yourself. Sundays are labelled Holiday, and late days show real minutes late.
4. Dashboard → team-card row → detail sheet → "View month" → Sundays are still labelled Holiday. This is the self-loaded-holidays path.
5. Pull-to-refresh on the Dashboard updates "My attendance" (the freshness label on the team card changes too).
6. Light and dark mode: dots are readable, and today is outlined.
7. **No-Attendance-access session** (e.g. a warehouse operator): Dashboard renders with no attendance cards and no red error widget or "improper use of GetX" log.

- [ ] **Step 4: Report**

Report the analyze result, the pass/fail counts and the smoke results to the user. Don't merge or bump the version. The user decides release timing after the smoke test (it ships as one MINOR together with the `c35bd6a5` card, merged `--no-ff` into `release/play-store`).
