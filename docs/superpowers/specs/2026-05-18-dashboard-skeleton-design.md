# Dashboard Manufacturing Pulse Skeleton — Design Spec

**Date:** 2026-05-18  
**Status:** Approved  

---

## Problem

When the Dashboard loads, the Manufacturing Pulse section shows a `CircularProgressIndicator` inside a fixed `SizedBox(height: 150)`. When `isLoadingStats` and `isLoadingUsers` flip to false, the section replaces the 150dp spinner with the full KPI card column (~480dp). This height jump causes a jarring layout shift that scrolls the content below it out of position.

---

## Goal

Replace the `CircularProgressIndicator` in the Manufacturing Pulse section with a shimmer skeleton that matches the approximate height and shape of the real content, eliminating the layout shift on initial load.

---

## Approach: Inline skeleton in `home_screen.dart`

No new files. No new packages. Follows the exact pattern already established by `_ProfileSkeleton` in `user_profile_screen.dart` and `_SkeletonDrawerItem` in `app_nav_drawer.dart`.

---

## Design

### 1. Loading gate (home_screen.dart — build method)

The loading guard in the Manufacturing Pulse `Obx` block changes from a spinner to the skeleton:

```dart
// Before
if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
  return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
}

// After
if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
  return const _ManufacturingPulseSkeleton();
}
```

### 2. `_ManufacturingPulseSkeleton` widget

A private `StatefulWidget` added at the bottom of `home_screen.dart`, after the existing `_ResumeJobCard`, `BomCountCard`, and `SpeedometerKpiCard` classes.

**Animation setup** — identical to `_ProfileSkeleton`:
- `AnimationController(vsync: this, duration: Duration(milliseconds: 900))..repeat(reverse: true)`
- `ColorTween(begin: Colors.grey.shade100, end: Colors.grey.shade300).animate(_anim)`
- Disposed in `dispose()`

**`_box()` helper** — identical to `_ProfileSkeleton`:
```dart
Widget _box({double w = double.infinity, double h = 14, double r = 8}) {
  return AnimatedBuilder(
    animation: _color,
    builder: (_, __) => Container(
      width: w, height: h,
      decoration: BoxDecoration(color: _color.value, borderRadius: BorderRadius.circular(r)),
    ),
  );
}
```

**Skeleton layout** — mirrors the real Manufacturing Pulse content:

```
Column
  ├── Row
  │     ├── Expanded(_box(h: 200, r: 16))   ← SpeedometerKpiCard (Work Orders)
  │     ├── SizedBox(width: 16)
  │     └── Expanded(_box(h: 200, r: 16))   ← SpeedometerKpiCard (Job Cards)
  ├── SizedBox(height: 12)
  └── _box(h: 70, r: 16)                    ← BomCountCard
```

**Sizing rationale:**
- `h: 200` for the two KPI cards — `SpeedometerKpiCard` has `padding: fromLTRB(16, 20, 16, 12)` + `CircularPercentIndicator(radius: 60)` (diameter 120dp) + title row + target badge ≈ 200dp
- `h: 70` for the BOM card — `BomCountCard` has `padding: symmetric(vertical: 16)` + single icon/text row ≈ 70dp
- `r: 16` — matches `borderRadius: BorderRadius.circular(16)` on both real cards
- `_ResumeJobCard` is omitted — it is conditional even in the real state (only shown when a WIP job card exists), so reserving space for it would cause its own shift

---

## Files changed

| File | Change |
|------|--------|
| `lib/app/modules/home/home_screen.dart` | Replace spinner with `_ManufacturingPulseSkeleton()` in loading guard; add `_ManufacturingPulseSkeleton` + `_ManufacturingPulseSkeletonState` classes |

No new files. No new dependencies.

---

## What is NOT in scope

- Skeleton for the User Context Card or Quick Access grid (no layout shift there)
- Skeleton for the Performance Timeline Card (already handled internally by `PerformanceTimelineCard`)
- Full-page skeleton on initial load
