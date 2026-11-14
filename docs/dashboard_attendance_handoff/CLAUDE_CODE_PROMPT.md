# Claude Code prompt — Dashboard: "Today's attendance" section

Copy the fenced block into Claude Code, run from the Flutter project root
(`ddmco_multimax/`) on a branch cut from `origin/release/play-store` at or after
`c6228378` (feat(hr): merge Attendance monitor). Backend facts come from
`docs/attendance_backend_handoff.md`; the screen it summarises is documented in
`docs/design_handoff_attendance_monitor/README.md`.

---

```
You are working in the ddmco_multimax Flutter app (GetX + Material 3).

GOAL
Add a "Today's attendance" section to the Dashboard (HomeScreen) so a manager
or HR user sees, without leaving Home, who is in, who is late and who has not
turned up today, and every employee sees their own check-in state. The section
is a glanceable summary that taps through to the existing Attendance screen
(AppRoutes.ATTENDANCE, lib/app/modules/hr/attendance/). Do NOT build a second
attendance screen and do NOT reimplement any attendance logic: everything is
derived by code that already exists and is unit-tested.

READ FIRST (do not change behaviour in these)
- docs/attendance_backend_handoff.md            # data contract, timings, gaps
- docs/design_handoff_attendance_monitor/README.md
- lib/app/modules/hr/attendance/attendance_logic.dart      # AttendanceStatus,
    EmployeeDayStatus, deriveDayStatus, compareDayStatus, AttendanceCounts,
    freshnessLabel, isStale
- lib/app/modules/hr/attendance/attendance_controller.dart # how a day loads
- lib/app/data/providers/attendance_provider.dart          # the five reads
- lib/app/data/models/attendance_models.dart               # TrackedEmployee,
    EmployeeCheckin, AttendanceRecord, ShiftRules, dateOnly, kFrappeDate
- lib/app/modules/hr/attendance/widgets/attendance_summary_strip.dart
    (AttendanceSummaryTile) and employee_attendance_card.dart
    (EmployeeAttendanceCard, AttendanceFlag)
- lib/app/modules/hr/attendance/widgets/employee_detail_sheet.dart
    (showEmployeeDetailSheet)
- lib/app/modules/home/home_screen.dart   # section order, _buildSectionHeader,
    _buildNeedsAttention (the pattern to copy), DashboardSectionOrder
- lib/app/modules/home/home_controller.dart  # fetchDashboardData,
    fetchActionableCounts (permission-gated fetch pattern), selectedFilterUser
- lib/app/modules/home/home_binding.dart
- lib/app/modules/home/widgets/dashboard_actionable_strip.dart  # style of a
    public, controller-free dashboard widget with its own widget test
- test/widget/dashboard_revamp_widgets_test.dart, test/unit/attendance_logic_test.dart

FILES
- Edit:  lib/app/modules/home/home_controller.dart
         lib/app/modules/home/home_screen.dart
         lib/app/modules/home/home_binding.dart
         lib/app/modules/hr/attendance/attendance_logic.dart  (one pure helper)
- New:   lib/app/modules/home/widgets/dashboard_attendance_card.dart
         test/widget/dashboard_attendance_card_test.dart
         (+ cases in test/unit/attendance_logic_test.dart)

WHAT EXISTS NOW
HomeScreen body order: greeting → ScanHeroCard → DashboardSectionOrder(
tasks: Upcoming & actionable, middle: Quick Create + Needs attention) →
Today's pulse. The Attendance screen already derives one EmployeeDayStatus per
active employee for a day (today from Employee Checkin punches, past days from
Attendance rows), sorts attention-first, counts with AttendanceCounts.of, and
polls every 60 s. AttendanceProvider is registered only by AttendanceBinding.

DATA RULES (from the backend handoff — design for them, do not fight them)
- Today can only be: Present, Late (first punch after shift start + grace,
  08:15 on this site), Not in yet (no punch, before the cut-off), Absent so far
  (no punch, after the cut-off), Holiday (Sunday for everyone), Not tracked
  (no attendance_device_id; never counted, never listed on the Dashboard).
- Punches arrive with up to 15 min lag. The terminal can be offline for days
  (it has been since 28 Aug 2026): zero punches for everyone after the cut-off
  is "offline", not "everyone absent".
- Most staff only check IN; out time is usually blank. Blank is normal.
- Read permission: a user with HR User / HR Manager sees everyone; an
  Employee-role user gets only their own rows from the same calls. Do not
  special-case this: whatever rows come back are what the card shows.
- Attendance is site-wide. It does NOT follow selectedFilterUser (the
  "Viewing {user}" chip). State this in a comment on the section.

CONTROLLER (home_controller.dart)
Add, next to the actionable fields:
  final AttendanceProvider _attendanceProvider = Get.find<AttendanceProvider>();
  final isLoadingAttendance = true.obs;
  final attendanceRows = <EmployeeDayStatus>[].obs;   // all, sorted
  final attendanceShift = Rx<ShiftRules>(ShiftRules.fallback);
  final attendanceHolidays = <String>{}.obs;
  final attendanceLoadedAt = Rxn<DateTime>();
  final attendanceLatestPunch = Rxn<EmployeeCheckin>();
  bool _attendanceMasterLoaded = false;
Derived getters (mirror AttendanceController, same names where they exist):
  bool get attendanceVisible =>
      Get.find<PermissionService>().hasAccess('Attendance') == true;
  bool get attendanceIsHoliday, beforeAttendanceCutoff, attendanceLooksOffline
  AttendanceCounts get attendanceCounts => AttendanceCounts.of(attendanceRows);
  EmployeeDayStatus? get myAttendance  // row whose employee.name ==
      _authController.currentUser.value?.employeeId, else null
Add Future<void> fetchTodayAttendance():
  - return immediately (isLoadingAttendance=false, rows cleared) when
    !attendanceVisible — same fail-closed gate as the drawer entry.
  - master once (_attendanceMasterLoaded): fetchActiveEmployees →
    fetchShiftRules(first non-empty default_shift, else ShiftRules.fallback.name,
    catch → fallback) → fetchHolidays(shift.holidayList, catch → empty).
    Copy this block from AttendanceController._loadMaster; do not "improve" it.
  - each call: fetchCheckins(today) and fetchAttendance(today, today) in
    Future.wait; when checkins is empty also fetchLatestCheckin (catch → null).
  - build rows exactly as AttendanceController.rows does (group punches by
    employee, ledger by employee, deriveDayStatus(now: DateTime.now()),
    sort compareDayStatus), assign, set attendanceLoadedAt.
  - catch-all: print + leave previous rows; finally isLoadingAttendance=false.
    Never let an HR 403 or a slow HR call fail fetchDashboardData: call
    fetchTodayAttendance() from fetchDashboardData's existing Future.wait
    alongside _fetchActiveWipJc / fetchUpcomingTodos / fetchActionableCounts,
    wrapped so its own try/catch swallows errors.
  - no poll on the Dashboard. Pull-to-refresh and the header refresh already
    call fetchDashboardData; that is enough. (ponytail: add a 60 s poll only if
    someone asks; the Attendance screen has one.)
  void goToAttendance() => Get.toNamed(AppRoutes.ATTENDANCE);
Register Get.lazyPut<AttendanceProvider>(() => AttendanceProvider()) in
HomeBinding next to the other providers (AttendanceBinding's lazyPut then
finds it already registered; that is fine).

PURE HELPER (attendance_logic.dart)
  /// Rows worth showing on the Dashboard: untracked never; attention first
  /// (compareDayStatus order), capped. [self] (the logged-in employee's row)
  /// is pinned first when present, even if Present.
  List<EmployeeDayStatus> dashboardAttendanceHighlights(
      Iterable<EmployeeDayStatus> rows, {String? selfEmployee, int max = 3});
Unit-test it in attendance_logic_test.dart: untracked dropped; self pinned;
cap respected; ordering Absent so far › Late › Not in yet › Present; on a
holiday returns only self (if any) — nobody needs attention on a Sunday.

WIDGET (lib/app/modules/home/widgets/dashboard_attendance_card.dart)
Public, controller-free, like DashboardActionableStrip:
  class DashboardAttendanceCard extends StatelessWidget {
    counts, isHoliday, beforeCutoff, looksOffline, latestPunch (DateTime?),
    shift (ShiftRules), highlights (List<EmployeeDayStatus>), myRow
    (EmployeeDayStatus?), loadedAt, now, isLoading, onViewAll, onRowTap(row)
  }
Anatomy, top → bottom, inside one card (surface fill, 1 px border, radius 14,
14 px padding — same shell as AttentionRow):
1. Headline row: how_to_reg_rounded icon chip (primary @12%) + one line that
   changes with state, + a muted freshness label on the right
   (freshnessLabel(loadedAt, now); orange text when isStale):
   - holiday:        "Holiday today" — subtitle "Sunday · no attendance expected"
   - beforeCutoff:   "Shift starts {shift.startLabel}" — subtitle
                     "{present+late} in so far · late after {shift.cutoffLabel}"
   - looksOffline:   "No punches yet today" — subtitle "Last punch
                     {d MMM HH:mm}" from latestPunch, or "terminal may be offline"
   - otherwise:      "{present+late} of {tracked} in" — subtitle
                     "{late} late · {absent} absent so far"
2. Summary tiles: a Row of four AttendanceSummaryTile (reused as-is):
   Present green500, Late orange500, Not in gray500, Absent red500 — with the
   same "—" semantics as AttendanceSummaryStrip (Absent is null before the
   cut-off; everything but Holiday is null on a holiday). onTap null; tiles are
   display-only here. Pass loading through.
3. "Me" line, only when myRow != null: AppAvatar initials + "You" +
   StatusPill(status: myRow.status.label, compact: true) + in time HH:mm if
   any + AttendanceFlag (e.g. "12 min late") when myRow.flag != null.
4. Highlights: up to 3 EmployeeAttendanceCard(row, onTap) reused as-is, 9 px
   apart. Skip the row that is already shown as "Me". Hide the block when
   highlights is empty.
5. Footer: TextButton "View all" right-aligned → onViewAll.
Loading: when isLoading and there is nothing yet, render the headline chip +
four AttendanceSummaryTile(loading: true) and no rows (the tile already has
its own skeleton). Never an empty grey box.
Colours: AppColors ramp only (x700 light / x300 dark for text/icons, 500 for
dots), context.scheme for surfaces; StatusPill already maps every
AttendanceStatus label. No Colors.* material shades. Both themes.

SCREEN (home_screen.dart)
- Add Widget _buildTodayAttendance(BuildContext) modelled on
  _buildNeedsAttention: an Obx that returns SizedBox.shrink() unless
  controller.attendanceVisible, then _buildSectionHeader(context,
  "Today's attendance", trailing: TextButton "Open" → controller.goToAttendance)
  + DashboardAttendanceCard(...) fed from the controller getters, with
    highlights: dashboardAttendanceHighlights(controller.attendanceRows,
        selfEmployee: currentUser.employeeId),
    onRowTap: (row) => showEmployeeDetailSheet(context, row: row,
        day: dateOnly(DateTime.now()), shift: controller.attendanceShift.value,
        loadedAt: controller.attendanceLoadedAt.value)  — that is the exact
        existing signature; pass nothing else.
  + SizedBox(height: 18).
- Place it inside DashboardSectionOrder's `middle` Column, after
  _buildNeedsAttention. It therefore follows the persona ordering that already
  exists (managers with open ToDos see tasks first, then Quick Create, Needs
  attention, Today's attendance). Do not add a new persona rule.
- The section hides entirely for users without Attendance access, so
  operators' Dashboards are unchanged.

TESTS
- test/widget/dashboard_attendance_card_test.dart: pump DashboardAttendanceCard
  in light and dark (copy the harness from dashboard_revamp_widgets_test.dart)
  for: loading; normal mid-morning (2 present, 1 late, 1 absent so far, self
  present); before cut-off (Absent tile shows "—", headline says "Shift
  starts"); holiday; offline (latestPunch shown). Assert no overflow, the
  headline text, and that onViewAll / onRowTap fire.
- test/unit/attendance_logic_test.dart: the helper cases listed above.
- Existing dashboard tests must still pass; HomeController tests that build the
  controller need AttendanceProvider in the Get graph — register a stub the way
  home_controller_actionable_test.dart stubs the other providers.

CONSTRAINTS
- No new networking beyond the five AttendanceProvider reads that already exist.
- No `dart format` on existing files (it rewrites whole files); hand-indent.
- Run `flutter analyze` and then `flutter test` — never both at once.
- Reactive controls that swap icon → spinner need their own Obx (CLAUDE.md).
- Keep the diff small: reuse AttendanceSummaryTile, EmployeeAttendanceCard,
  AttendanceFlag, StatusPill, AppAvatar, showEmployeeDetailSheet unchanged. If
  one of them genuinely cannot be reused, say why in a one-line comment rather
  than forking it.

DELIVERABLE
Dashboard shows "Today's attendance" for users with Attendance access:
headline + four count tiles + the viewer's own row + up to three attention-first
employee rows + View all → the Attendance screen; correct calm states before
08:15, on Sundays and while the terminal is offline; hidden for everyone else;
analyze clean; new widget + unit tests green; existing suite green.
```
