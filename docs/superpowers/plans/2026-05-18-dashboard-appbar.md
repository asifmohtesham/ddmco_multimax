# Dashboard AppBar Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `HomeScreen` from `MainAppBar` + `Scaffold` to `DocTypeListHeader` + `AppShellScaffold` + `CustomScrollView`, making the Dashboard visually and structurally consistent with every other list screen.

**Architecture:** Single-file change — `home_screen.dart`. The `MainAppBar` (fixed, dark red) is replaced by `DocTypeListHeader` (expanding, white surface). The `Scaffold` body `Column` becomes a `CustomScrollView` with slivers. The `BarcodeInputWidget` moves from a fixed bottom slot in the `Column` to `AppShellScaffold.bottomNavigationBar`. No logic changes — controllers, routes, and bindings are untouched.

**Tech Stack:** Flutter, GetX, `DocTypeListHeader` (SliverPersistentHeader), `AppShellScaffold` (Scaffold wrapper), `CustomScrollView`

---

## File Map

| File | Action |
|------|--------|
| `lib/app/modules/home/home_screen.dart` | Modify — replace AppBar/Scaffold, convert body to slivers |

---

### Task 1: Update imports

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart:1-13`

> `MainAppBar` and `AppNavDrawer` are no longer used directly — `AppShellScaffold` provides the drawer internally. `DocTypeListHeader` and `AppShellScaffold` are added.

- [ ] **Step 1: Replace the two removed imports and add the two new ones**

Open `lib/app/modules/home/home_screen.dart`. Find these two lines:

```dart
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
```

Replace them with:

```dart
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
```

- [ ] **Step 2: Verify no other reference to `MainAppBar` or `AppNavDrawer` remains in this file**

Run:
```
grep -n "MainAppBar\|AppNavDrawer" lib/app/modules/home/home_screen.dart
```
Expected: no output (zero matches).

---

### Task 2: Replace the `build()` method

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart` — the `build()` method of `HomeScreen`

> This is the core structural swap. The entire `build()` method is replaced. All helper methods (`_buildQuickAccessGrid`, `_buildUserContextCard`, etc.) are untouched.

- [ ] **Step 1: Replace the `build()` method**

Find the existing `build()` method (lines 19–159 approximately). Replace it entirely with:

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);

  return AppShellScaffold(
    bottomNavigationBar: Container(
      decoration: const BoxDecoration(
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
    body: RefreshIndicator(
      onRefresh: () async {
        await controller.fetchDashboardData();
        await controller.fetchPerformanceData();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          DocTypeListHeader(
            title: 'Dashboard',
            automaticallyImplyLeading: false,
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildUserContextCard(context),
                const SizedBox(height: 24),
                Text(
                  'Quick Access',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildQuickAccessGrid(context),
                const SizedBox(height: 24),
                Obx(() => PerformanceTimelineCard(
                  viewMode: controller.timelineViewMode.value,
                  onToggleView: controller.toggleTimelineView,
                  data: controller.timelineData,
                  isLoading: controller.isLoadingTimeline.value,
                  selectedDate: controller.timelineViewMode.value != 'Weekly'
                      ? controller.selectedDailyDate.value
                      : null,
                  selectedRange: controller.timelineViewMode.value == 'Weekly'
                      ? controller.selectedWeeklyRange.value
                      : null,
                  onDateChanged: controller.onDailyDateChanged,
                  onRangeChanged: controller.onWeeklyRangeChanged,
                )),
                const SizedBox(height: 24),
                Text(
                  'Manufacturing Pulse',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Obx(() {
                  if (controller.isLoadingStats.value || controller.isLoadingUsers.value) {
                    return const SizedBox(
                      height: 150,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SpeedometerKpiCard(
                              title: 'Work Orders',
                              actual: controller.activeWorkOrdersCount.value,
                              target: controller.targetWorkOrders,
                              icon: Icons.precision_manufacturing_outlined,
                              onTap: controller.goToWorkOrder,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SpeedometerKpiCard(
                              title: 'Job Cards',
                              actual: controller.activeJobCardsCount.value,
                              target: controller.targetJobCards,
                              icon: Icons.assignment_ind_outlined,
                              onTap: controller.goToJobCard,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      BomCountCard(
                        count: controller.activeBomCount.value,
                        onTap: controller.goToBOM,
                      ),
                      Obx(() {
                        final jcName = controller.activeWipJcName.value;
                        final op = controller.activeWipJcOperation.value;
                        if (jcName == null) return const SizedBox.shrink();
                        return _ResumeJobCard(jcName: jcName, operation: op);
                      }),
                    ],
                  );
                }),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 2: Run `flutter analyze`**

```
flutter analyze lib/app/modules/home/home_screen.dart
```

Expected: `No issues found!`

If you see `Undefined name 'MainAppBar'` or `Undefined name 'AppNavDrawer'` — Task 1 was not saved correctly. Recheck the imports.

If you see `The getter 'barcodeController' isn't defined` — check `HomeController` for the exact field name and update the call.

- [ ] **Step 3: Hot-reload on device and verify**

Run the app (`flutter run -d <device_id>`). Navigate to the Dashboard (home screen).

Verify:
- [ ] Header background is **white** (not dark red)
- [ ] "Dashboard" large title appears below the toolbar when at the top of the scroll
- [ ] Scrolling down **collapses** the large title into the toolbar
- [ ] Hamburger (☰) icon is in the top-left — tapping it opens the nav drawer
- [ ] Refresh icon (↺) is in the top-right toolbar
- [ ] Notifications icon is **gone**
- [ ] Barcode input is pinned at the bottom — position unchanged
- [ ] Pull-to-refresh still triggers `fetchDashboardData` + `fetchPerformanceData`
- [ ] All Quick Access tiles, timeline, and KPI cards still render and are tappable

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/home/home_screen.dart
git commit -m "feat: migrate Dashboard to DocTypeListHeader + AppShellScaffold for AppBar consistency"
```

---

## Self-Review Notes

- **Spec coverage:** All three spec sections covered — Scaffold (Task 1–2 step 1), AppBar (Task 2 step 1 `DocTypeListHeader` block), Body slivers (Task 2 step 1 `CustomScrollView` block). Files changed table matches.
- **No TDD widget test:** `HomeController` has 10+ `Get.find()` field initializers; writing a mock harness would require stubbing every global service. Since this is a purely structural/visual change with zero logic delta, `flutter analyze` + device verification is the appropriate verification strategy here.
- **`backgroundColor`:** `AppShellScaffold` defaults to `colorScheme.surfaceContainerLow` (~`#F7F2FA` on Material 3 light). The old value was `Colors.grey[50]` (`#FAFAFA`). Both are near-white; the difference is imperceptible. No override needed.
- **`resizeToAvoidBottomInset`:** Omitted — `AppShellScaffold` defaults to `true`, same as `Scaffold`. No change in behaviour.
