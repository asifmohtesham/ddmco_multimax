# Claude Design prompt — Attendance monitor (mockups)

Paste the fenced block into Claude Design. Backend facts come from
`docs/attendance_backend_handoff.md`; component names come from
`docs/doctype_list_view_conventions.md` and `docs/app_bar_conventions.md`.

---

```
Design the mobile UI for a new "Attendance" screen in Multimax, an existing
warehouse ERP app (Flutter, Material 3, Android-first, phone 390x844). Produce
mockups only; no code. Match the existing app, do not restyle it.

BRAND / TOKENS (existing, reuse exactly)
- Primary maroon #870E18 (app bar, FAB, avatars, active chips). On-primary white.
- Grey ramp: 50 #F9FAFA, 100 #F4F5F6, 200 #EBEEF0, 300 #D8DEE3, 400 #BCC4CB,
  500 #98A1A9, 600 #74808B, 700 #525C66, 800 #323A45, 900 #1F272E.
- Status colours, as TEXT/ICON only: light mode uses the 700 shade, dark mode
  the 300 shade. green 700 #1F5E34 / 300 #8FD3A8; red 700 #9A2222 / 300
  #F09494; orange 700 #9E5409 / 300 #F7B67A; blue 700 #18599A / 300 #7CC0F7;
  yellow 500 #E0A93A / 300 #F3D08C. Pills: tinted fill (colour at ~12%) +
  700/300 text. Never material default shades. Every text/background pair
  must pass 4.5:1.
- Corners 12-14px on cards, full radius on pills/chips. 14px card padding.
- Both light and dark themes are required.

WHO USES IT
A warehouse manager or HR user checking, several times a day, who is on site,
who came late, and who has not turned up. Secondary use: looking back at a
past day or the month. Glanceable first, detailed on tap.

DATA (real constraints, design for them)
- One shift "General" 08:00-20:00, late after 08:15, Sundays off.
- Today's state comes from raw punches and can only be one of:
  Present (first punch <= 08:15), Late (first punch > 08:15), Not in yet
  (no punch, time < 08:15), Absent so far (no punch, time >= 08:15),
  Holiday (Sunday, everyone), Not tracked (employee has no terminal ID;
  show greyed and grouped at the bottom, never counted).
- Past days come from an Attendance ledger with status Present / Absent /
  On Leave / Half Day / Work From Home, in time, out time, working hours,
  late-entry and early-exit flags.
- Staff mostly only check IN, so out time and working hours are often blank
  or 0. Design blanks as a normal state, not an error.
- Data is at most 15 minutes stale; show "Updated 5 min ago" style freshness.
- 16 tracked employees, 10 untracked. Lists are short; no pagination needed.
- Departments exist and are a filter. Employee photos may be missing; fall
  back to an initial on a maroon circle.

SCREEN ANATOMY (must follow the app's list-screen convention)
1. Large collapsing app bar titled "Attendance" (singular), hamburger on the
   left, filter + search + refresh icons on the right.
2. Date context row: a chip showing the selected day ("Today, Tue 9 Sep") with
   prev/next day arrows; tapping opens a date picker.
3. Summary strip: compact count tiles Present / Late / Not in / Holiday-or-
   Absent, each tile filterable on tap (acts as a status filter chip).
4. Result count pill ("16 employees") and any active filter chips
   (department, status) as removable chips in one row.
5. Employee rows, one card per person: avatar, name, department, status
   pill on the right, in time and out time underneath (out time may be
   blank), a small late/early flag when applicable. Rows are sorted by
   status severity (Absent/Late first) then name.
6. End-of-list footer with a one-line summary of counts (present / late /
   not in). Never a sum of hours.
7. Pull-to-refresh.

ALSO DESIGN
- Employee detail bottom sheet (tap a row): name, department, today's status,
  a vertical timeline of every punch with time and device, shift window shown
  as context, and a "View month" action.
- Month view for one employee or everyone: a calendar grid with a status dot
  per day, plus a list below it using the ledger statuses.
- Filter bottom sheet: date range, department, status; primary "Apply" and
  text "Clear".
- States: loading; empty because the terminal is offline ("No punches since
  28 Aug, terminal may be offline"); no permission (user lacks HR role);
  Sunday/holiday view.

ARTBOARDS TO PRODUCE (one each, phone frame)
1. Today list, light, mid-morning: mix of Present, Late, Absent so far,
   Not tracked group at the bottom.
2. Same screen, dark theme.
3. Today list before 08:15: everyone "Not in yet", calm tone, no alarm colours.
4. Holiday (Sunday) view.
5. Employee detail bottom sheet over the list.
6. Month view.
7. Filter sheet.
8. Terminal-offline empty state, and no-permission state (two frames).
9. Component sheet: every status pill in light and dark with hex values,
   summary tile, employee row anatomy with spacing, freshness label.

CONSTRAINTS
- Reuse these existing app components conceptually, and name them in the
  notes so the developer maps them: DocTypeListHeader (app bar),
  ResultCountPill, FilterChipWidget, GenericDocumentCard (row), ListEndFooter,
  ListEmptyState, ReportFilterSheet. Call out anything genuinely new (status
  pill, summary tile, punch timeline, calendar grid).
- No red for "Not in yet" before 08:15; red only for Absent/Absent so far.
- Numbers right-aligned in tabular figures; times as HH:mm, 24h.
- Touch targets >= 48px. Text >= 12px.

DELIVERABLE
Artboards plus a short notes page: colour mapping per status for both
themes, list of new vs reused components, and any assumptions you made.
```
