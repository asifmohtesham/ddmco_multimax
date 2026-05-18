# Dashboard AppBar Consistency — Design Spec

**Date:** 2026-05-18  
**Status:** Approved  

---

## Problem

The Dashboard (`HomeScreen`) uses `MainAppBar` — a fixed `PreferredSizeWidget` with a dark red background and a two-row layout (title row + actions row below). Every other top-level list screen uses `DocTypeListHeader` — a `SliverPersistentHeader` with a white/surface background and an expanding large title. The inconsistency is visually jarring when navigating between the Dashboard and any DocType list screen.

---

## Goal

Make the Dashboard AppBar visually and structurally consistent with DocType List View screens by migrating to the same `DocTypeListHeader` + `AppShellScaffold` + `CustomScrollView` pattern already used by every other list screen.

---

## Approach: Direct migration (Approach A)

No new abstractions. Every pattern used is already established in the codebase.

---

## Design

### 1. Scaffold

Replace the plain `Scaffold` + `MainAppBar` with `AppShellScaffold`. `AppShellScaffold` supplies the `AppNavDrawer` automatically, so the explicit `drawer:` is removed.

The `BarcodeInputWidget` moves from the `Column`'s fixed-bottom slot to `AppShellScaffold.bottomNavigationBar`. The decoration (white background + top shadow) is preserved.

```dart
AppShellScaffold(
  bottomNavigationBar: Container(
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
    ),
    child: Obx(() => BarcodeInputWidget(
      onScan: controller.onScan,
      controller: controller.barcodeController,
      isLoading: controller.isScanning.value,
      hintText: 'Scan Item / Batch / Rack',
      activeRoute: AppRoutes.HOME,
    )),
  ),
  body: CustomScrollView(...),
)
```

### 2. AppBar

Replace `MainAppBar(title: "Dashboard", actions: [...])` with `DocTypeListHeader`:

```dart
DocTypeListHeader(
  title: 'Dashboard',
  automaticallyImplyLeading: false,   // shows hamburger, not back arrow
  extraActions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Refresh Data',
      onPressed: () {
        controller.fetchDashboardData();
        controller.fetchPerformanceData();
      },
    ),
  ],
),
```

- `automaticallyImplyLeading: false` → hamburger menu icon (same as all list screens)
- Only the Refresh action is kept; the Notifications icon is removed
- The large title "Dashboard" expands/collapses on scroll, matching the DocType List View behaviour

### 3. Body — sliver structure

The `SingleChildScrollView` + `Column` body is replaced by a `CustomScrollView` whose children mirror the original layout 1-to-1:

```
CustomScrollView
  ├── DocTypeListHeader
  ├── SliverPadding (horizontal 16, top 16)  ← replaces fromLTRB padding
  │     └── SliverList / SliverToBoxAdapters:
  │           ├── _buildUserContextCard(context)
  │           ├── SizedBox(height: 24)
  │           ├── "Quick Access" heading + _buildQuickAccessGrid()
  │           ├── SizedBox(height: 24)
  │           ├── PerformanceTimelineCard  (Obx-wrapped)
  │           ├── SizedBox(height: 24)
  │           ├── "Manufacturing Pulse" heading + KPI cards  (Obx-wrapped)
  │           └── SizedBox(height: 80)  ← bottom clearance above BarcodeInputWidget
```

The `RefreshIndicator` wraps the `CustomScrollView` (same as `ItemScreen`). `AlwaysScrollableScrollPhysics` is retained so pull-to-refresh always fires even when content is short.

---

## Files changed

| File | Change |
|------|--------|
| `lib/app/modules/home/home_screen.dart` | Replace `Scaffold`+`MainAppBar` with `AppShellScaffold`+`DocTypeListHeader`; convert body to `CustomScrollView` with slivers; move `BarcodeInputWidget` to `bottomNavigationBar` |

No new files. No changes to controllers, routes, bindings, or other screens.

---

## What is NOT in scope

- Personalised greeting in the large title (Approach C) — deferred
- User context card in the header bottom slot (Approach B) — deferred
- Any changes to the Dashboard content (KPI cards, timeline, quick-access grid)
