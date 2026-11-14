# Handoff: Dashboard revamp — scan-first, task-aware home

## Overview
Redesign of the **Dashboard** (`HomeScreen`) in the ddmco_multimax Flutter app.
The current screen is a flat stack — user-context card, an undifferentiated
Quick Access grid, a performance chart, and decorative half-arc KPI gauges, with
the barcode scanner pinned to the very bottom. The revamp re-ranks the screen by
operational value so both operators and supervisors know **what to do right now**:

1. **Scan elevated to a hero action** at the top of the scroll (no longer the
   easiest-to-miss control on the screen).
2. **Quick Create first** — same tiles, but each is visually distinct (coloured
   icon chip + matching top accent bar + a "+" create cue) and split into clear
   Operations / Manufacturing groups so they stop reading as identical pills.
3. **New "Needs attention" strip** — actionable rows that tell the operator what
   to do now: Resume Job Card (live WIP), Deliveries to pack, Work Orders due,
   Purchase Receipts pending QC. Each is a tap-through with a count.
4. **KPIs made actionable, not decorative** — the two half-arc speedometers
   become compact progress stats (actual / target, % bar, a "due today" line),
   and the timeline shrinks to a weekly read.
5. **Context switcher folded into the header** — the bulky "Showing data for…"
   card becomes a compact chip under the greeting, keeping the manager's
   switch-user power without eating the top of the screen.

## About the design files
The files in this bundle are **design references created in HTML** — a prototype
showing the intended look and behaviour, **not** production code to copy. The
task is to **recreate this layout in the existing Flutter codebase** using its
established patterns (GetX `HomeController`, Material 3 `Theme.colorScheme`, the
app's existing widgets, routes and formatting helpers). Do not port HTML/CSS; do
not re-theme the app.

- `Dashboard Revamp.html` — the visual reference (open in a browser; scroll).
- `ds.css` — the Multimax design-system tokens the reference was styled with
  (for intent only; in-app, map to `Theme.colorScheme`).
- `TASK.md` — the To-Do ticket.
- `CLAUDE_CODE_PROMPT.md` — a ready-to-paste implementation prompt.

## Fidelity
**High-fidelity on layout & hierarchy.** The section order, grouping, tile
treatment, and the new "Needs attention" pattern are settled. Colours in the
reference use the maroon brand over the DS language — in-app, source the brand
from `Theme.primaryColor` / `colorScheme.primary` and the per-tile accents from
the existing `_QuickActionConfig.color` values already in the file. The "Needs
attention" data sources are noted as **suggested** — wire the rows that the
controller can already answer first; gate the rest behind real data.

## Screens / sections (top → bottom)

### 1. Header — greeting + context chip (replaces `_buildUserContextCard`)
- `DocTypeListHeader(title: 'Dashboard')` stays (with the existing refresh action).
- Below it, a greeting row: brand avatar (user initial) + "Good morning, {first
  name}" (titleLarge, w700). No time-of-day logic required if you prefer a static
  "Welcome back".
- Under the greeting, a **compact context chip** (pill, subtle fill + hairline
  border): person glyph + "Viewing **{selectedFilterUser.name}**" + a chevron.
  Tapping it opens the **existing** `_showUserSearchModal` unchanged. This
  replaces the full-width context Card.

### 2. Hero scan (new, top of scroll body)
- A full-width maroon gradient card: barcode glyph chip + "Scan to start" /
  "Item, batch or rack — look up or add stock" + a trailing camera button.
- Tapping it triggers the **same** scan entry point as the existing
  `BarcodeInputWidget` (focus the barcode field / open the scanner via
  `controller.onScan` plumbing). See "Scanner" below for the two options.

### 3. Quick Create (reworked `_buildQuickAccessGrid`)
- Keep the exact same items, routes, `DocTypeGuard` wrapping and 3-up `Wrap`.
- Restyle each tile (`_buildQuickActionItem`): add a **3px top accent bar** in
  `cfg.color`, keep the circular tinted icon, add a small "+" affordance top-
  right to signal "create". Section dividers ("Operations" / "Manufacturing")
  stay.

### 4. Needs attention (new strip)
- A labelled section with a count badge, containing:
  - **Resume Job Card** — promote the existing `_ResumeJobCard` here, restyled in
    the brand colour with a play glyph (and optionally an elapsed-time tag). Only
    shown when `controller.activeWipJcName.value != null` (unchanged condition).
  - **Action rows** — `_AttentionRow(icon, color, title, subtitle, count, onTap)`:
    Deliveries to pack, Work Orders due today, Purchase Receipts pending QC. Each
    routes to the relevant list (reuse `controller.goToWorkOrder`, the delivery
    fulfillment sheet, etc.). Counts come from the controller where available.

### 5. Today's pulse (reworked Manufacturing Pulse)
- Replace the two `SpeedometerKpiCard` gauges with compact `_PulseStat` cards:
  title + icon, "{actual} / {target} target", a thin progress bar in the state
  colour, and a footer line ("{n} due today" + "{pct}%"). Same `actual`/`target`
  data, same `onTap` (`goToWorkOrder` / `goToJobCard`).
- Keep `PerformanceTimelineCard` but as a slimmer weekly read (the reference
  shows a 7-bar mini chart with a Daily/Weekly segmented toggle —
  `controller.timelineViewMode` / `toggleTimelineView` already exist).
- `BomCountCard` can stay as-is or fold into the pulse grid as a third stat.

## Interactions & behavior
- **No new networking or controller data flow.** Every tap reuses an existing
  route / handler / bottom sheet.
- The user context modal (`_showUserSearchModal`) and the fulfillment selection
  sheet (`_showFulfillmentSelectionSheet`) are unchanged.
- Light/dark: every colour theme-derived; brand tints use `withValues(alpha:)`.

## Scanner — where the input lives
The scanner is currently a persistent `BarcodeInputWidget` in
`AppShellScaffold.bottomNavigationBar`. Two acceptable approaches:
- **A (recommended, lowest risk):** keep the persistent bottom input AND add the
  hero card at the top whose tap focuses/opens it (`controller.barcodeController`
  + scanner). The hero is the discoverable entry; the bar is the actual field.
- **B:** move scanning fully into the hero card (open the camera scanner sheet on
  tap) and drop the bottom bar. Only do this if product confirms the persistent
  bar isn't relied on elsewhere.
Default to **A** unless told otherwise.

## State management
None new. All data already arrives via `HomeController.fetchDashboardData()` /
`fetchPerformanceData()`. The only additions are presentational widgets and,
optionally, surfacing already-known counts (work orders due, deliveries pending)
in the attention rows — guard each row behind a real source and hide it when the
count is unknown rather than showing a placeholder.

## Design tokens (reference values from `ds.css`)
- **Brand (maroon):** primary `#8c1c2b`, dark `#5f0f1a`; tints at 6–13% over
  surface. In-app: `colorScheme.primary` + `withValues(alpha:)`.
- **Tile accents:** reuse the existing per-item colours (orange, blue, green,
  purple, deepPurple / teal, indigo, deepOrange). Icon chip = colour @10–14%,
  3px top bar = colour @90%.
- **State colours (pulse / attention):** healthy green `#38a160`, watch/at-risk
  orange `#f0851b`, info blue. Map to Material shades as the rest of the app does.
- **Radius:** cards 14–16, icon chip full, pills/bars full.
- **Type:** Inter; mono = Roboto Mono for codes/timers. Greeting 19/700, section
  label 13/700, tile label 12/600, stat number 27/800 tabular, captions 11–12.
- **Spacing:** 4px grid; ~18px between major sections, 9–12px within a group.

## Assets
Icons only — Material symbols already in the app (qr_code_scanner,
photo_camera_outlined, compare_arrows, local_shipping, receipt_long,
assignment_return, shopping_bag, account_tree, precision_manufacturing,
assignment_ind, play_circle, schedule, chevron_right, person,
keyboard_arrow_down). No images.

## Files in this project
- `Dashboard Revamp.html` (root + this folder) — the design.
- Implementation target: `lib/app/modules/home/home_screen.dart`
  (`_buildUserContextCard` → header+chip, `_buildQuickAccessGrid` /
  `_buildQuickActionItem`, the Manufacturing Pulse block, `_ResumeJobCard`,
  `SpeedometerKpiCard` → `_PulseStat`), plus a new hero scan widget and a
  `_AttentionRow` helper. Controller: `home_controller.dart` (read-only for the
  field names).
