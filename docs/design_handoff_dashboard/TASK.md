# To-Do — Revamp the Dashboard (HomeScreen)

**DocType:** ToDo
**Priority:** Medium
**Reference Type:** Page
**Reference Name:** Dashboard
**Assigned module:** `lib/app/modules/home/`

---

## Description

Make the Dashboard more intuitive and friendly for operations. Today the screen
gives equal weight to everything — a big user-context card, an
undifferentiated Quick Access grid, a performance chart and two decorative
half-arc KPI gauges — while the barcode scanner sits at the very bottom. Re-rank
the screen so both an operator and a supervisor immediately see **what to do
now**.

This is a **presentation-only** change to `HomeScreen` and its private widgets in
`home_screen.dart`. No API, controller data-flow or routing changes are required;
every action reuses an existing route, handler or bottom sheet.

## Why

- Quick Access tiles all look identical, so the most-used create actions are hard
  to scan.
- The half-arc speedometers look like dials but aren't actionable — they don't
  say what's overdue.
- The barcode scanner — the single most-used floor action — is the least
  prominent control, pinned to the bottom.
- The screen has no "what needs my attention" surface; hierarchy is flat.

## Acceptance criteria

- [x] A **hero "Scan to start" card** sits at the top of the scroll body and
      triggers the existing scan entry point; the scanner is no longer the
      hardest control to find (keep the persistent input — Approach A in README).
- [x] **Quick Create comes first** and each tile is visually distinct: coloured
      icon chip + a 3px top accent bar in the tile colour + a small "+" create
      cue. Same items, routes and `DocTypeGuard` wrapping as today.
- [x] A **"Needs attention"** section shows actionable rows with counts:
      Resume Job Card (existing WIP condition), Deliveries to pack, Work Orders
      due today, Purchase Receipts pending QC — each tapping through to the
      relevant list. Rows with no real data source are hidden, not faked.
      *(See deviation 1 — only Resume Job Card / Work Orders / Job Cards wired;
      Deliveries-to-pack and PR-pending-QC omitted, no controller source yet.)*
- [x] The two `SpeedometerKpiCard` gauges become compact **progress stats**
      (actual / target, % bar in the state colour, a "due today" footer). Same
      data and `onTap`. *(See deviation 2 — footer shows distance-to-target.)*
- [x] The full-width user-context Card becomes a **compact context chip** under a
      greeting; tapping it opens the existing `_showUserSearchModal` unchanged.
- [x] `PerformanceTimelineCard` stays as a slimmer weekly read; the
      Daily/Weekly toggle keeps working (`timelineViewMode` / `toggleTimelineView`).
- [x] Light + dark themes both pass; all colours come from `Theme.colorScheme`
      plus the existing per-tile `cfg.color` accents (no hard-coded surfaces).
- [x] `flutter analyze` clean; a widget test renders the screen (loading + loaded
      states) without overflow.

## Implementation status (2026-06-21)

Done on branch `feature/design-system-family-a`. Edited
`lib/app/modules/home/home_screen.dart` only (presentation-only — no controller,
networking or routing changes). Test:
`test/widget/dashboard_revamp_widgets_test.dart` (6 cases: loaded + loading +
zero-target, light & dark, 360 px — all pass). `flutter analyze` clean on the
file. Smoke test on device still pending.

**Deviations from the spec (intentional):**

1. **Needs-attention rows** — wired only the rows the controller can already
   answer: Resume Job Card (`activeWipJcName`), Work Orders in process
   (`activeWorkOrdersCount` → `goToWorkOrder`), Open Job Cards
   (`activeJobCardsCount` → `goToJobCard`). **Deliveries to pack** and **Purchase
   Receipts pending QC** are omitted — there is no controller count for them and
   the spec says rows without a real source are hidden, not faked. Wire them when
   the counts exist. (Work Orders/Job Cards also appear in Today's pulse — same as
   the HTML mockup; worklist vs. progress-vs-target framings.)
2. **Pulse footer** — the design's "{n} due today" has no data source, so the
   footer shows the honest, derivable `"{remaining} to target"` (or `"Target met"`
   once actual ≥ target) in the state colour, with `"{pct}%"` muted on the right.
3. **Widget visibility** — `ScanHeroCard`, `PulseStat`, `AttentionRow`,
   `ResumeJobCard` and `PulseSkeleton` are **public** (not private as the prompt
   suggested) so they are unit-testable — matching the file's existing public
   `BomCountCard`. `SpeedometerKpiCard` was deleted (no other references);
   the `percent_indicator` import was dropped from this file.
4. **Layout fix** — the two-up pulse row is wrapped in `IntrinsicHeight` so its
   `CrossAxisAlignment.stretch` has a bounded cross-axis; a bare stretched Row in
   the sliver throws "RenderBox was not laid out". Caught by the widget test.

## Design reference

`Dashboard Revamp.html` in this bundle (open in a browser, scroll). See
`README.md` for the full spec and `CLAUDE_CODE_PROMPT.md` for an implementation
prompt.
