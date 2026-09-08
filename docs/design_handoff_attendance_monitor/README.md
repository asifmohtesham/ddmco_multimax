# Attendance monitor — design handoff

Mockups live in Claude Design:
<https://claude.ai/design/p/9746931c-4bcc-40e2-aa3e-53323678cd6f?file=Attendance.html>
(`Attendance.html` + `attendance.css`, tokens in `multimax-ds/ds.css`). The prompt that
produced them is in `CLAUDE_DESIGN_PROMPT.md`; the backend contract is
`../attendance_backend_handoff.md`.

Built 2026-09-09 as `lib/app/modules/hr/attendance/` (list screen, employee detail sheet,
per-employee month view). Route `/hr/attendance`, drawer group **HR**, gated by
`DocTypeGuard('Attendance')`.

## Where the build deviates from the mockups

| Mockup | Built | Why |
|---|---|---|
| Employee row on `GenericDocumentCard` | Dedicated `EmployeeAttendanceCard` | `GenericDocumentCard` only takes a status *string* and adds a chevron row; the pill + flag trailing column and the In/Out line did not fit its API. Same visual spec (40px avatar, 12px gap, radius 12, pill top-aligned, flag 7px below). |
| Filter sheet with date range + multi-select chips + "Apply" | `ReportFilterSheet` with single-select Department and Status chip groups; button reads "Run Report" | Reuses the shared sheet unchanged. The date is already the date row's job. Add multi-select when someone asks for it. |
| Month view "Everyone" switcher | Per-employee only | "Everyone for a day" is the list screen with that date selected. |
| Filter chips in the count row | Chips render in the `DocTypeListHeader` chip row | App-wide list convention wins over the mockup. |
| Freshness = last terminal upload | Freshness = last app fetch; the offline empty state shows the last punch on the site | The app cannot see the agent; last fetch is what it knows. Stale (>15 min) still turns orange. |
| Solid-maroon avatar | `AppAvatar` (16% primary tint, primary initials) | Shared component; keeps avatars consistent with the rest of the app. |

## Pieces reused as-is

`DocTypeListHeader` (inline search on Employee, filter badge, refresh `AsyncIconButton`),
`ResultCountPill`, `FilterChipWidget`, `ListEmptyState`, `DocCardSkeletonList`,
`ReportFilterSheet`, `StatusPill` (ramp extended with the attendance statuses),
`ListEndFooter` (gained an optional `label`), `AppAvatar`, `AppShellScaffold`.

## Behaviour notes

- Today is derived from Employee Checkin punches; any other day uses submitted Attendance
  rows and falls back to punches when the scheduler has not produced a row yet.
- `now` is injected into `deriveDayStatus` so the 08:15 rule is unit-tested
  (`test/unit/attendance_logic_test.dart`). Shift start / grace / holiday list are read
  from `Shift Type` + `Holiday List`; a hardcoded 08:00/08:15 fallback exists only for
  when the Shift Type is unreadable.
- 60-second poll while today is selected; pull-to-refresh and the header icon reload on demand.
- Terminal-offline state: today, past the cut-off, zero punches for anyone.
- Not tracked (no `attendance_device_id`) rows are dimmed, grouped last, never counted.
