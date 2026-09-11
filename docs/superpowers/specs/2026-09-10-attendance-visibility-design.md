# Attendance visibility — design (sub-project #1)

Date: 2026-09-10 · Branch: `claude/attendance-terminal-ux-4863b9` (based on `c35bd6a5`,
the Dashboard "Today's attendance" card) · Release: one MINOR, `--no-ff` into `release/play-store`.

## 1. Why

Three asks from the user, after seeing the Attendance screen's offline state on a phone:

1. Only `System Manager` users should be told "the attendance terminal may be offline".
2. Employees who fail to punch should be reminded and see that they are late / absent.
3. Each user's attendance for the day **and the month** should be on the Dashboard the
   moment the app opens.

This spec covers asks 1 and 3 plus the System-Manager unenrolled-staff nudge. Ask 2 and
the other follow-ups are separate sub-projects (§9).

## 2. Facts this design rests on (verified 2026-09-10)

- HRMS v15 permissions: the `Employee` role can **read** Attendance and Shift Type, but only
  their **own** Employee Checkin / Attendance rows (user permissions). `HR User`+ read all.
- Therefore an Employee-role client cannot tell "I did not punch" from "the terminal did
  not upload". Only a viewer who sees every punch (HR User+/System Manager) can infer an
  outage from "zero punches site-wide past the cut-off".
- The uncommitted-until-now Dashboard card computed `attendanceLooksOffline` as "every row
  I can see has no punches" — for a self-only viewer that is just their own missed punch,
  so it would have told employees the terminal is offline. This spec fixes that.
- HRMS writes a day's Attendance row only after the shift's check-out window closes
  (22:00); a `Present` row with `late_entry = 1` is a late day. Nobody is Absent before the
  day closes.
- `AttendanceMonthController` only picks up holidays and shift rules when
  `AttendanceController` happens to be registered; opened from the Dashboard it would lose
  Sunday labels and use the fallback shift.

## 3. What each person sees

### 3.1 "My attendance" block (Dashboard, between greeting and Scan hero) — layout B

Headline + sub-line, then a whole-month dot strip, then a tally line. Whole block taps to
the viewer's month calendar.

| State | Headline | Sub-line |
|---|---|---|
| Before cut-off, no punch | Not in yet | Punch before {cutoff} to be on time |
| After cut-off, no punch | No check-in recorded yet | Shift started {start} |
| Punched, on time | In · {HH:mm} | On time |
| Punched, late | In · {HH:mm} | {n} min late |
| Holiday | Holiday | {Weekday} · no attendance expected |
| Ledger status for today (On Leave / Half Day / WFH) | {status label} | leave type, if any |

- Dot strip: one dot per day of the current month. Each dot uses
  `StatusPill.colourForStatus(status.label)` ink, so it always matches the pill — green
  Present, orange Late, red Absent, blue Holiday **and** On Leave, yellow Half Day, purple
  WFH. Future days faint; today outlined while it has no status, filled once it does.
- Tally line: `{Month} · {p} present · {l} late · {a} absent` (+ ` · {v} leave` when > 0).
  Late days are **not** counted in present.
- Hidden when the user has no linked Employee (`currentUser.employeeId` empty) or the
  employee is not in the loaded rows.
- Linked but not enrolled on the terminal (`!isTracked`): one line "You're not enrolled on
  the attendance terminal" — no strip, no tally.
- Loading (first load): skeleton headline + grey strip. Month-ledger fetch failure:
  headline only — no strip, no tally, since an empty ledger would draw a wrong month
  (fail soft, no snackbar — dashboard convention).

### 3.2 "Today's attendance" team card (Dashboard, middle block)

- Shown only when the viewer sees more than their own row: `attendanceCounts.tracked > 1`.
  Employee-role viewers no longer get a duplicate of "My attendance".
- The card's "You" line (`_MeLine`) and the `_selfOnly` headline branch are removed — "My
  attendance" owns the viewer's own status.

### 3.3 Terminal-offline wording (Attendance screen + team card)

- **System Manager** (`currentUser.hasRole('System Manager')`): unchanged — "No punches
  since {d MMM}" / "The attendance terminal may be offline…", plus the last-punch line.
- **Everyone else**: title "No check-ins recorded yet today", message "Statuses will appear
  as check-ins arrive." Same icon and Reload action, **no** last-punch line, no mention of
  the terminal. Team-card headline becomes "No check-ins recorded yet", sub-line "Statuses
  will appear as check-ins arrive".

### 3.4 Unenrolled-staff nudge (Attendance screen, System Manager only)

A one-line banner, reusing the screen's existing info-banner widget:
"{n} employee(s) aren't enrolled on the terminal". Tap = set the status filter to
`Not tracked`. Hidden when n = 0, and also hidden while any search or filter is active
(tapping the banner itself sets the `Not tracked` filter, which then hides it).

## 4. Data flow

`HomeController.fetchTodayAttendance` (already called from `fetchDashboardData`, so
pull-to-refresh covers it) keeps its current loads — employees, today's punches, today's
ledger, shift, holidays — and adds **one** request when the viewer has an Employee id:

```
fetchAttendance(firstOfMonth, yesterday, employee: myId)   // own rows only
```

The range ends **yesterday** so a late-evening ledger row for today is never counted next
to the punch-derived today (one source per day: ledger for past days, punches for today).
On the 1st of the month the call is skipped (empty range).

Today's dot/headline come from the existing `myAttendance` getter (the viewer's
`EmployeeDayStatus`), which works for both self-only and site-wide viewers.

## 5. Components

### New

- `attendance_logic.dart` → pure
  `MonthStrip buildMonthStrip({required DateTime month, required List<AttendanceRecord> ledger, required Set<String> holidays, required EmployeeDayStatus? today, required DateTime now, required ShiftRules shift, required TrackedEmployee employee})`
  returning `MonthStrip { List<AttendanceStatus?> days; int present, late, absent, leave; }`.
  Past days use `deriveDayStatus(ledger: row)` (so `late_entry` → Late); a past non-holiday
  day with no ledger row is `null` (unknown, drawn faint — HRMS may not have processed it);
  holidays → Holiday; today → `today?.status`; future → `null`.
- `lib/app/modules/home/widgets/my_attendance_card.dart` → `MyAttendanceCard`, public and
  controller-free (plain values + callbacks), like `DashboardAttendanceCard`.

### Changed

| File | Change |
|---|---|
| `home_controller.dart` | `myMonthLedger` Rx list + fetch in `fetchTodayAttendance`; `myMonthStrip` getter; `showTeamAttendance` (`attendanceCounts.tracked > 1`); `isSystemManager`; `attendanceLooksOffline` unchanged but only read by the team card, which is hidden for self-only viewers — so it can no longer misfire for them |
| `home_screen.dart` | `MyAttendanceCard` after the greeting; team card wrapped in `showTeamAttendance`; tap → month route with `{employee, today, holidays, shift}` |
| `dashboard_attendance_card.dart` | `isSystemManager` flag selects offline copy; remove `_MeLine`, `myRow`, `_selfOnly` |
| `attendance_screen.dart` | `_TerminalOffline` role-aware copy; unenrolled banner for System Managers |
| `attendance_controller.dart` | `untrackedCount` getter |
| `attendance_month_controller.dart` | accept `holidays` (Set<String>) and `shift` (ShiftRules) arguments; fall back to the registered list controller, then to `ShiftRules.fallback`; when holidays are still empty, `load()` fetches them from `shift.holidayList` — fixes every entry path, including Dashboard → detail sheet → View month |
| `employee_detail_sheet.dart` | "View month" also passes `'shift': shift` |

## 6. Error handling

- All dashboard attendance loads keep "swallow and render what we have"; no snackbars on
  the Dashboard.
- Role checks read the cached `currentUser`; no extra request.
- `myId` present but employee missing from rows (e.g. Employee list denied) → block hidden,
  not an error.

## 7. Testing

TDD, pure logic first.

- Unit (`test/unit/attendance_logic_test.dart`): `buildMonthStrip` — Sunday holiday, late
  ledger row counted as late not present, On Leave, unknown past day, today outlined vs
  filled, future null, 1st-of-month, 28/30/31-day months; tally counts.
- Unit: `myAttendanceHeadline`, `unenrolledLabel`. (`showTeamAttendance` is a one-line
  getter — no test; offline copy by role is covered by the widget tests.)
- Widget (`test/widget/my_attendance_card_test.dart`): the six states of §3.1 + not-enrolled
  + skeleton, × light/dark, at 360 px. Use `Wrap` / `Flexible` + `FittedBox` — the Ahem test
  font inflates widths.
- Widget: update `dashboard_attendance_card_test.dart` (System Manager vs not; no Me line);
  Attendance screen offline copy per role.
- `flutter analyze`, then the full suite — sequentially, never concurrently.
- On-device smoke: a System Manager session, an Employee-role session (e.g. Jawwad), and a
  session for a user WITHOUT Attendance read access (e.g. a warehouse operator) — the
  Dashboard should render cleanly with no "My attendance" or "Today's attendance" card and
  no error widget.

## 8. Out of scope here

Reminders, sync heartbeat, Attendance Request, manager team view (§9). No changes to the
Attendance list's derivation rules or to the month screen's layout.

## 9. Follow-up sub-projects

| # | Sub-project | Notes |
|---|---|---|
| 0 | Sync heartbeat (handoff doc for the BioTime agent repo — not on this machine) | User keeps HRMS "Automatically update Last Sync of Checkin" **ticked** for now, so `last_sync_of_checkin` is not a trustworthy heartbeat; #0 must use a separate agent-written signal readable by the Employee role. Known risk accepted by the user: while the terminal is offline, HRMS marks Absent and late-uploaded punches do not correct it. |
| 2 | Attendance notifications | 08:15 "no check-in seen yet", next-morning recap, 20:00 punch-out; System-Manager terminal-quiet alert (> 2 h on a working day). WorkManager + local notifications like the digest; iOS fixed-text only. Blocked on #0. |
| 3 | Fix a missed punch | HRMS Attendance Request form, launched from a reminder or "My attendance". |
| 4 | Manager team view | Direct reports via `reports_to` (`UserProvider.getDirectReports`). |
