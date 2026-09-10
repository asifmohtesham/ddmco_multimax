# Dashboard · Today's attendance — design handoff

Mockups live in Claude Design:
<https://claude.ai/design/p/9746931c-4bcc-40e2-aa3e-53323678cd6f?file=Dashboard+-+Today%27s+Attendance.html>
(`Dashboard - Today's Attendance.html` + `dashboard-attendance.css`, on top of `attendance.css`
and `multimax-ds/ds.css`). The prompt that produced the build brief is `CLAUDE_CODE_PROMPT.md`;
the backend contract is `../attendance_backend_handoff.md`.

Built 2026-09-09 as a new section of `HomeScreen` (`lib/app/modules/home/`), placed in the
persona-ordered middle block right after Needs attention. Hidden unless
`PermissionService.hasAccess('Attendance') == true` (same gate as the drawer entry), so operator
Dashboards are unchanged. Site-wide: it does not follow the "Viewing {user}" chip.

## Pieces

| Piece | Where | Status |
|---|---|---|
| `DashboardAttendanceCard` | `home/widgets/dashboard_attendance_card.dart` | new, controller-free |
| `dashboardAttendanceHighlights` | `hr/attendance/attendance_logic.dart` | new pure helper |
| `HomeController.fetchTodayAttendance` + `attendance*` getters | `home/home_controller.dart` | new, runs inside `fetchDashboardData` |
| `AttendanceSummaryTile`, `EmployeeAttendanceCard`, `InOutStat`, `AttendanceFlag`, `StatusPill`, `AppAvatar`, `showEmployeeDetailSheet` | attendance module / global widgets | reused unchanged |

## Where the build follows the mockup's open points (⚑)

- **Offline** (zero punches for anyone after the cut-off): highlights and the Me line are hidden,
  all four tiles show "—", the subtitle carries the last punch on the site.
- **One-row viewer** (Employee role): headline speaks to them ("You're in · 08:31",
  "16 min after the 08:15 cut-off") instead of "1 of 1 in".
- **Before the cut-off**: highlights are the first three "Not in yet" rows (grey, calm). Not
  suppressed; flip `max` in the helper call if it reads as noise.
- **Self on the Me line only**: the helper excludes the viewer's own row from highlights rather
  than pinning it; the mockup shows both and the notes say skip.

## Deviations

| Mockup | Built | Why |
|---|---|---|
| Highlight rows at 10/12 padding, no shadow | `EmployeeAttendanceCard` at its default 14/12 | Reused as-is per the notes ("ship it at its default"). |
| Freshness ticks | Freshness is computed at build; no clock | The Dashboard does not poll. Pull-to-refresh / header refresh rebuild it. |
| Employee photo | `AppAvatar` initials (image when `Employee.image` is set) | Same as the Attendance screen. |

Tests: `test/widget/dashboard_attendance_card_test.dart` (every frame state, both themes, taps)
and the `dashboardAttendanceHighlights` group in `test/unit/attendance_logic_test.dart`.
