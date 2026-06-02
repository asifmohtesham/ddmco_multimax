# Dashboard Manufacturing Pulse Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `CircularProgressIndicator` loading guard in the Manufacturing Pulse section with a shimmer skeleton that matches the real content's height, eliminating the layout shift on Dashboard load.

**Architecture:** Single-file change to `home_screen.dart`. The loading guard swaps a `SizedBox(height:150, CircularProgressIndicator)` for `_ManufacturingPulseSkeleton()`. The skeleton is a private `StatefulWidget` added at the bottom of the file, following the identical pattern used by `_ProfileSkeleton` in `user_profile_screen.dart` — `AnimationController + ColorTween (grey.100→grey.300, 900ms repeat-reverse) + _box() helper`. No new files, no new packages.

**Tech Stack:** Flutter, `AnimationController`, `ColorTween`, `SingleTickerProviderStateMixin`

---

## File Map

| File | Action |
|------|--------|
| `lib/app/modules/home/home_screen.dart` | Modify — swap loading guard + add skeleton widget |

---

### Task 1: Swap loading guard and add skeleton widget

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart`

- [ ] **Step 1: Replace the loading guard in `build()`**

In `home_screen.dart`, find the `Obx` block for Manufacturing Pulse. It currently reads:

```dart
Obx(() {
  if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
    return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
  }
```

Replace just that `if` branch with:

```dart
Obx(() {
  if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
    return const _ManufacturingPulseSkeleton();
  }
```

Everything after the `if` block (the `return Column(...)`) stays untouched.

- [ ] **Step 2: Add `_ManufacturingPulseSkeleton` at the bottom of the file**

At the very end of `home_screen.dart` — after the closing `}` of `SpeedometerKpiCard` — append:

```dart
// =============================================================================
// _ManufacturingPulseSkeleton — shimmer placeholder while stats are loading
// =============================================================================

class _ManufacturingPulseSkeleton extends StatefulWidget {
  const _ManufacturingPulseSkeleton();

  @override
  State<_ManufacturingPulseSkeleton> createState() =>
      _ManufacturingPulseSkeletonState();
}

class _ManufacturingPulseSkeletonState
    extends State<_ManufacturingPulseSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Color?> _color;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _color = ColorTween(
      begin: Colors.grey.shade100,
      end: Colors.grey.shade300,
    ).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _box({double w = double.infinity, double h = 14, double r = 8}) {
    return AnimatedBuilder(
      animation: _color,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: _color.value,
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _box(h: 200, r: 16)),
            const SizedBox(width: 16),
            Expanded(child: _box(h: 200, r: 16)),
          ],
        ),
        const SizedBox(height: 12),
        _box(h: 70, r: 16),
      ],
    );
  }
}
```

- [ ] **Step 3: Run `flutter analyze`**

```
flutter analyze lib/app/modules/home/home_screen.dart
```

Expected: `No issues found!`

If you see `The class '_ManufacturingPulseSkeleton' doesn't have a constructor named ''` — check that `const _ManufacturingPulseSkeleton()` constructor is present in the widget class.

If you see `The name 'ColorTween' isn't defined` — `ColorTween` is in `package:flutter/material.dart`, which is already imported. No additional import is needed.

- [ ] **Step 4: Verify on device**

Run the app and navigate to the Dashboard. On first load (before stats finish fetching):

- [ ] Two side-by-side grey shimmer cards visible where Work Orders / Job Cards KPI cards will appear
- [ ] One wide grey shimmer card below where the BOM count card will appear
- [ ] Shimmer pulses smoothly between light and dark grey (not a hard flash)
- [ ] When loading completes, the real KPI cards appear **without a height jump** — content below the section does not shift

Pull-to-refresh to repeat the loading sequence and confirm skeleton re-appears during the refetch.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/home/home_screen.dart
git commit -m "feat: replace Manufacturing Pulse spinner with shimmer skeleton to eliminate layout shift"
```

---

## Self-Review Notes

- **Spec coverage:** Loading gate (Task 1 Step 1) ✓, skeleton widget (Task 1 Step 2) ✓, sizing rationale (h:200 KPI, h:70 BOM, r:16) ✓, `_ResumeJobCard` intentionally omitted ✓.
- **No placeholders:** All code is complete and exact.
- **Type consistency:** `_ManufacturingPulseSkeleton` defined in Step 2, referenced in Step 1 — consistent.
- **No TDD widget test:** Same reasoning as the AppBar migration — `HomeController` has 10+ `Get.find()` dependencies; `flutter analyze` + device testing is the appropriate verification for a purely visual, zero-logic change.
