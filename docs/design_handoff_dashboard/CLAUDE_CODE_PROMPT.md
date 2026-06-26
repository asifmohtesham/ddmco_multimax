# Claude Code prompt — Dashboard (HomeScreen) revamp

Copy everything in the fenced block below into Claude Code, run from the Flutter
project root (`ddmco_multimax/`). The HTML reference and full spec are alongside
this file in `design_handoff_dashboard/`.

---

```
You are working in the ddmco_multimax Flutter app (GetX + Material 3).

GOAL
Revamp the Dashboard (HomeScreen) so it is intuitive for warehouse operators and
useful for supervisors: lead with scanning and quick-create, surface a "what
needs attention now" strip, and turn the decorative KPI gauges into compact,
actionable stats. This is a PRESENTATION-ONLY change. Do NOT change networking,
HomeController data flow, or routing — every action must reuse an existing route,
handler or bottom sheet. A pixel reference is in
design_handoff_dashboard/Dashboard Revamp.html — open it (and scroll). It is
rendered in the Multimax maroon brand; in the app, source the brand from
Theme.of(context).colorScheme.primary / primaryColor and reuse the per-tile
colours already defined in _QuickActionConfig — do NOT re-theme the app.

FILES
- Edit:  lib/app/modules/home/home_screen.dart
- Read for context only (do not change behaviour):
         lib/app/modules/home/home_controller.dart
         lib/app/modules/home/widgets/performance_timeline_card.dart
         lib/app/modules/global_widgets/barcode_input_widget.dart
         lib/app/modules/global_widgets/doctype_list_header.dart
         lib/app/modules/global_widgets/app_shell_scaffold.dart

WHAT EXISTS NOW (in home_screen.dart)
- AppShellScaffold with a persistent BarcodeInputWidget in bottomNavigationBar.
- CustomScrollView: DocTypeListHeader('Dashboard') → _buildUserContextCard →
  'Quick Access' + _buildQuickAccessGrid → PerformanceTimelineCard →
  'Manufacturing Pulse' (two SpeedometerKpiCard, BomCountCard, _ResumeJobCard).
- Controller fields you may read: selectedFilterUser, userList,
  activeWorkOrdersCount, targetWorkOrders, activeJobCardsCount, targetJobCards,
  activeBomCount, activeWipJcName, activeWipJcOperation, timelineViewMode,
  timelineData, isLoadingStats, isLoadingUsers; handlers goToWorkOrder,
  goToJobCard, goToBOM, toggleTimelineView, onScan, barcodeController,
  fetchDashboardData, fetchPerformanceData; sheets _showUserSearchModal,
  _showFulfillmentSelectionSheet.

NEW SCREEN ORDER (top → bottom), inside the existing CustomScrollView/SliverList:

1. HEADER + CONTEXT CHIP (replaces _buildUserContextCard)
   Keep DocTypeListHeader('Dashboard') with its refresh action. Below it add a
   greeting Row: a brand CircleAvatar (primary bg, white initial of
   selectedFilterUser.name) + "Good morning, {firstName}" (titleLarge, w700).
   Under the greeting, a compact context CHIP (pill: surfaceVariant fill, hairline
   border, full radius): person icon + "Viewing {selectedFilterUser.name}" (name
   w600, ellipsis) + keyboard_arrow_down. onTap → the EXISTING
   _showUserSearchModal(context). Remove the old full-width context Card.

2. HERO SCAN CARD (new _ScanHeroCard, first item in the body)
   Full-width Material card, primary→primary-dark LinearGradient, radius 14,
   ~14px padding: a rounded glyph chip (white @16%) with Icons.qr_code_scanner,
   a title "Scan to start" (16, w700, white) over "Item, batch or rack — look up
   or add stock" (12, white @82%), and a trailing camera button
   (Icons.photo_camera_outlined). onTap triggers the SAME scan entry as the
   bottom BarcodeInputWidget — focus controller.barcodeController / open the
   scanner. KEEP the persistent bottom BarcodeInputWidget (Approach A); the hero
   is the discoverable entry point, the bar remains the actual input.

3. QUICK CREATE (rework _buildQuickAccessGrid / _buildQuickActionItem)
   Keep the exact items, routes, DocTypeGuard wrapping, 3-up Wrap, and the
   "Operations" / "Manufacturing" _buildSectionDivider labels. Retitle the
   section "Quick Create". Restyle each tile: add a 3px top accent bar in
   cfg.color (a thin Container or a top Border), keep the circular tinted icon
   (cfg.color @ ~12%), and add a small "+" affordance in the top-right corner
   (Icons.add, 11px, in a subtle circle) to read as "create". Min tap target
   unchanged.

4. NEEDS ATTENTION (new section)
   A _buildSectionDivider-style label "Needs attention" with a count badge, then:
   - Promote _ResumeJobCard here, restyled in the brand colour (play glyph,
     primary tint), shown only when controller.activeWipJcName.value != null
     (unchanged condition). Optional: a monospace elapsed-time tag.
   - A list of _AttentionRow(icon, color, title, subtitle, count, onTap):
       • Deliveries to pack  → reuse the delivery fulfillment flow
       • Work Orders due today → controller.goToWorkOrder
       • Purchase Receipts pending QC → its list route
     _AttentionRow = white card, radius 14, 1px border: a square tinted icon
     chip (color @13%) + title (14 w600) over subtitle (12 muted) + a pill count
     badge (color, tabular) + chevron_right. IMPORTANT: only render a row when a
     real count is available from the controller; if a source doesn't exist yet,
     omit that row (do not hard-code a number). Wire what the controller can
     already answer first.

5. TODAY'S PULSE (rework the Manufacturing Pulse block)
   Replace the two SpeedometerKpiCard with a 2-up grid of _PulseStat cards:
   header (icon + title) → "{actual}" + "/ {target} target" → a 6px rounded
   LinearProgressIndicator-style bar (filled = actual/target, in a state colour:
   <40% red, <80% amber, else green) → footer Row ("{n} due today" in the state
   colour + "{pct}%" muted). Same actual/target data and onTap (goToWorkOrder /
   goToJobCard). Keep PerformanceTimelineCard but slimmer (its Daily/Weekly
   toggle via timelineViewMode/toggleTimelineView stays). BomCountCard may stay
   as-is below, or fold in as a third stat — your call, keep it tappable.

STATE / DATA
No new networking. Reuse fetchDashboardData()/fetchPerformanceData() and the
existing RefreshIndicator. Keep the _ManufacturingPulseSkeleton loading path
(adapt it to the new stat cards). Everything theme-derived for dark mode.

WIDGET STRUCTURE
Keep new pieces as private StatelessWidgets in the same file: _ScanHeroCard,
_ContextChip (or inline), _AttentionRow, _PulseStat. You may delete
SpeedometerKpiCard if nothing else references it (grep first). Keep _ResumeJobCard
(restyled). Reuse _QuickActionConfig untouched.

CONSTRAINTS
- No fixed white/black colours where a theme token fits; brand tints via
  withValues(alpha:).
- Match the app's existing spacing and min-tap conventions.
- Run `flutter analyze` and fix all new warnings. Add/adjust a widget test under
  test/widget/ that pumps HomeScreen in both loading and loaded states without
  overflow.
- Verify against Dashboard Revamp.html: header+chip, hero scan, distinct Quick
  Create tiles, the attention strip, and compact pulse stats.

DELIVERABLE
The updated home_screen.dart compiling cleanly, the new screen order rendering as
in the reference, scanning reachable from the top, no decorative-only gauges, and
a passing widget test.
```
