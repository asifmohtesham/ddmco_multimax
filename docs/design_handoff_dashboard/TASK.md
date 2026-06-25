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

- [ ] A **hero "Scan to start" card** sits at the top of the scroll body and
      triggers the existing scan entry point; the scanner is no longer the
      hardest control to find (keep the persistent input — Approach A in README).
- [ ] **Quick Create comes first** and each tile is visually distinct: coloured
      icon chip + a 3px top accent bar in the tile colour + a small "+" create
      cue. Same items, routes and `DocTypeGuard` wrapping as today.
- [ ] A **"Needs attention"** section shows actionable rows with counts:
      Resume Job Card (existing WIP condition), Deliveries to pack, Work Orders
      due today, Purchase Receipts pending QC — each tapping through to the
      relevant list. Rows with no real data source are hidden, not faked.
- [ ] The two `SpeedometerKpiCard` gauges become compact **progress stats**
      (actual / target, % bar in the state colour, a "due today" footer). Same
      data and `onTap`.
- [ ] The full-width user-context Card becomes a **compact context chip** under a
      greeting; tapping it opens the existing `_showUserSearchModal` unchanged.
- [ ] `PerformanceTimelineCard` stays as a slimmer weekly read; the
      Daily/Weekly toggle keeps working (`timelineViewMode` / `toggleTimelineView`).
- [ ] Light + dark themes both pass; all colours come from `Theme.colorScheme`
      plus the existing per-tile `cfg.color` accents (no hard-coded surfaces).
- [ ] `flutter analyze` clean; a widget test renders the screen (loading + loaded
      states) without overflow.

## Design reference

`Dashboard Revamp.html` in this bundle (open in a browser, scroll). See
`README.md` for the full spec and `CLAUDE_CODE_PROMPT.md` for an implementation
prompt.
