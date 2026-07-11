# Dashboard Persona-Aware Section Ordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Managers with open ToDos see "Upcoming tasks" directly after the Scan hero; everyone else keeps today's Quick-Create-first layout — with the verdict persisted per user so the dashboard never reflows while the async ToDo fetch is in flight.

**Architecture:** A pure static predicate on `HomeController` (`tasksFirst = any role containing "manager" AND upcomingTodos non-empty`), an `RxBool tasksFirst` seeded from a per-user GetStorage key and recomputed after each ToDo fetch, and a new public controller-free `DashboardSectionOrder` widget in `home_screen.dart` that places the tasks section above or below the Quick Create + Needs attention block.

**Tech Stack:** Flutter, GetX (`.obs` / `Obx`), GetStorage via the existing `StorageService`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-11-dashboard-persona-section-order-design.md`

## Global Constraints

- Combine rule is **AND**, never OR: `tasksFirst = isManagerish && hasOpenTodos`.
- `isManagerish` = any login role whose name contains `manager`, **case-insensitive**. ("Management" does not contain "manager" — no trailing 'r' — so trainee/management-adjacent roles correctly do not count.)
- Storage default is `false` (operator layout) — a missing/foreign key must never produce tasks-first.
- Storage key is per user: `'dashboard_tasks_first::<email>'`.
- The ONLY layout change is the Upcoming-tasks section moving; Quick Create → Needs attention keep their relative order in both modes. Operator mode must render exactly today's order.
- No new API calls, no new settings UI.
- Follow repo conventions: new dashboard widgets are public (testable without the HomeController DI graph); observables use `.obs`; comments state constraints, not narration.
- Windows PowerShell environment — use `flutter test <path>` (forward slashes work).
- This branch has pre-existing test failures unrelated to this work — Task 0 records the baseline; the final gate is "no NEW failures".

---

### Task 0: Record the test baseline

**Files:** none (measurement only)

**Interfaces:**
- Consumes: nothing
- Produces: the list of pre-existing failing test files, saved to the scratchpad for Task 4's comparison

- [ ] **Step 1: Run the full suite and save the summary**

Run:
```powershell
flutter test 2>&1 | Select-String -Pattern 'Some tests failed|All tests passed|^\d+:.*\[E\]|(?i)failed' | Out-File -Encoding utf8 "$env:LOCALAPPDATA\Temp\claude-test-baseline.txt"; Get-Content "$env:LOCALAPPDATA\Temp\claude-test-baseline.txt" | Select-Object -Last 30
```

Expected: either "All tests passed!" or a set of failing tests. Record which test FILES fail — memory notes ~24 pre-existing failures have been seen on this branch. Do not fix them; they are the baseline.

---

### Task 1: Pure predicate `HomeController.showTasksFirst`

**Files:**
- Modify: `lib/app/modules/home/home_controller.dart` (add static method after `setDashboardColumns`, currently ending at line 142)
- Test: `test/unit/dashboard_tasks_first_test.dart` (create)

**Interfaces:**
- Consumes: nothing (pure static function)
- Produces: `static bool HomeController.showTasksFirst({required List<String> roles, required bool hasOpenTodos})` — Task 3 calls this from `_recomputeTasksFirst()`; Task 1's tests call it directly.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/dashboard_tasks_first_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/home_controller.dart';

void main() {
  group('HomeController.showTasksFirst', () {
    test('manager with open todos leads with tasks', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Stock User', 'Stock Manager'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
    });

    test('manager with no open todos keeps operator layout', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Stock Manager'],
          hasOpenTodos: false,
        ),
        isFalse,
      );
    });

    test('operator keeps operator layout even with open todos', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Stock User', 'Sales User'],
          hasOpenTodos: true,
        ),
        isFalse,
      );
    });

    test('no roles at all is operator layout', () {
      expect(
        HomeController.showTasksFirst(roles: [], hasOpenTodos: true),
        isFalse,
      );
    });

    test('role match is case-insensitive', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['manufacturing manager'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
      expect(
        HomeController.showTasksFirst(
          roles: ['SYSTEM MANAGER'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
    });

    test('custom "* Manager" roles match with no maintained list', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Delivery Manager'],
          hasOpenTodos: true,
        ),
        isTrue,
      );
    });

    // "management" does not contain the substring "manager" (no trailing
    // 'r') — so trainee/management-adjacent roles correctly do NOT count.
    test('"Management Trainee" is NOT managerish', () {
      expect(
        HomeController.showTasksFirst(
          roles: ['Management Trainee'],
          hasOpenTodos: true,
        ),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/dashboard_tasks_first_test.dart`
Expected: FAIL to compile — `The method 'showTasksFirst' isn't defined for the type 'HomeController'`.

- [ ] **Step 3: Implement the predicate**

In `lib/app/modules/home/home_controller.dart`, directly after the `setDashboardColumns` method (after its closing `}` around line 142), add:

```dart
  /// Pure persona rule for dashboard section ordering: "Upcoming tasks"
  /// leads only when the user holds a manager-ish role AND there are open
  /// ToDos to show. AND, not OR — a manager with an empty list gains
  /// nothing from leading with an empty section, and an operator's layout
  /// must not flip whenever a task lands.
  ///
  /// Manager-ish = any role whose name contains "manager" (case-insensitive)
  /// — covers Stock/Purchase/Manufacturing/System Manager and custom
  /// "* Manager" roles with no maintained list.
  static bool showTasksFirst({
    required List<String> roles,
    required bool hasOpenTodos,
  }) {
    if (!hasOpenTodos) return false;
    return roles.any((r) => r.toLowerCase().contains('manager'));
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/dashboard_tasks_first_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```powershell
git add lib/app/modules/home/home_controller.dart test/unit/dashboard_tasks_first_test.dart && git commit -m @'
feat(dashboard): pure persona predicate for tasks-first section order

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 2: Per-user verdict persistence in `StorageService`

**Files:**
- Modify: `lib/app/data/services/storage_service.dart` (append to the "Dashboard view preferences" block, currently lines 137-144)
- Test: `test/unit/dashboard_tasks_first_test.dart` (extend — file created in Task 1)

**Interfaces:**
- Consumes: nothing new (uses the existing `_box` GetStorage wrapper and the `StorageService.withStorage` test constructor)
- Produces: `Future<void> saveDashboardTasksFirst(String user, bool value)` and `bool getDashboardTasksFirst(String user)` (default `false`) — Task 3 calls both from `HomeController`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/dashboard_tasks_first_test.dart`. First add these imports at the top of the file:

```dart
import 'package:multimax/app/data/services/storage_service.dart';
```

Then add this fake box class after the imports (same shape as `test/unit/dashboard_columns_test.dart` uses):

```dart
/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}
```

And this group inside `main()`:

```dart
  group('StorageService dashboard tasks-first verdict', () {
    test('defaults to false (operator layout) when never stored', () {
      final s = StorageService.withStorage(_FakeBox());
      expect(s.getDashboardTasksFirst('manager@multimax.cloud'), isFalse);
    });

    test('round-trips true and false', () async {
      final s = StorageService.withStorage(_FakeBox());
      await s.saveDashboardTasksFirst('manager@multimax.cloud', true);
      expect(s.getDashboardTasksFirst('manager@multimax.cloud'), isTrue);
      await s.saveDashboardTasksFirst('manager@multimax.cloud', false);
      expect(s.getDashboardTasksFirst('manager@multimax.cloud'), isFalse);
    });

    test('verdicts are per user — one user never leaks to another', () async {
      final s = StorageService.withStorage(_FakeBox());
      await s.saveDashboardTasksFirst('manager@multimax.cloud', true);
      expect(s.getDashboardTasksFirst('operator@multimax.cloud'), isFalse);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/dashboard_tasks_first_test.dart`
Expected: FAIL to compile — `The method 'getDashboardTasksFirst' isn't defined`.

- [ ] **Step 3: Implement the storage methods**

In `lib/app/data/services/storage_service.dart`:

Add the key constant next to `_dashboardColumnsKey` (line 36):

```dart
  static const String _dashboardTasksFirstKey = 'dashboard_tasks_first';
```

Append to the end of the "Dashboard view preferences" section (after `getDashboardColumns`, line 144):

```dart
  // Last computed "Upcoming tasks lead" verdict, PER USER, so the initial
  // dashboard build matches the previous session instead of reflowing when
  // the async ToDo fetch lands. Missing key = false (operator layout).
  Future<void> saveDashboardTasksFirst(String user, bool value) async =>
      _box.write('$_dashboardTasksFirstKey::$user', value);

  bool getDashboardTasksFirst(String user) =>
      _box.read<bool>('$_dashboardTasksFirstKey::$user') ?? false;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/dashboard_tasks_first_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```powershell
git add lib/app/data/services/storage_service.dart test/unit/dashboard_tasks_first_test.dart && git commit -m @'
feat(storage): persist per-user dashboard tasks-first verdict

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 3: `DashboardSectionOrder` widget

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart` (add public widget at the bottom of the file, after the `DashboardColumnsToggle` block that starts around line 955)
- Test: `test/unit/dashboard_tasks_first_test.dart` (extend)

**Interfaces:**
- Consumes: nothing (pure `StatelessWidget`, no controller)
- Produces: `DashboardSectionOrder({required bool tasksFirst, required Widget tasks, required Widget middle})` — Task 4 mounts it inside `HomeScreen.build`.

- [ ] **Step 1: Write the failing widget tests**

Add to `test/unit/dashboard_tasks_first_test.dart`. Add imports:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/home/home_screen.dart';
```

Add this group inside `main()`:

```dart
  group('DashboardSectionOrder', () {
    Future<void> pump(WidgetTester tester, {required bool tasksFirst}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardSectionOrder(
              tasksFirst: tasksFirst,
              tasks: const SizedBox(key: Key('tasks'), height: 40),
              middle: const SizedBox(key: Key('middle'), height: 40),
            ),
          ),
        ),
      ));
    }

    testWidgets('operator mode renders tasks BELOW the middle block',
        (tester) async {
      await pump(tester, tasksFirst: false);
      final tasksY = tester.getTopLeft(find.byKey(const Key('tasks'))).dy;
      final middleY = tester.getTopLeft(find.byKey(const Key('middle'))).dy;
      expect(middleY, lessThan(tasksY));
    });

    testWidgets('manager mode renders tasks ABOVE the middle block',
        (tester) async {
      await pump(tester, tasksFirst: true);
      final tasksY = tester.getTopLeft(find.byKey(const Key('tasks'))).dy;
      final middleY = tester.getTopLeft(find.byKey(const Key('middle'))).dy;
      expect(tasksY, lessThan(middleY));
    });

    testWidgets('both children are always in the tree', (tester) async {
      await pump(tester, tasksFirst: true);
      expect(find.byKey(const Key('tasks')), findsOneWidget);
      expect(find.byKey(const Key('middle')), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/dashboard_tasks_first_test.dart`
Expected: FAIL to compile — `The name 'DashboardSectionOrder' isn't a class`.

- [ ] **Step 3: Implement the widget**

At the very end of `lib/app/modules/home/home_screen.dart` (after the `DashboardColumnsToggle` widget's closing brace), add:

```dart
// =============================================================================
// DashboardSectionOrder — persona-aware Tasks ↔ Quick-Create ordering
// =============================================================================

/// Places [tasks] above [middle] (manager persona: manager role + open
/// ToDos) or below it (everyone else — exactly today's layout). Public and
/// controller-free (like the other dashboard widgets) so widget tests can
/// assert the flip without the full HomeController DI graph.
class DashboardSectionOrder extends StatelessWidget {
  const DashboardSectionOrder({
    super.key,
    required this.tasksFirst,
    required this.tasks,
    required this.middle,
  });

  /// True when Upcoming tasks lead.
  final bool tasksFirst;

  /// The Upcoming-tasks section (hides itself when there are no ToDos).
  final Widget tasks;

  /// The Quick Create + Needs attention block, kept in its existing
  /// internal order in both modes.
  final Widget middle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tasksFirst ? [tasks, middle] : [middle, tasks],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/dashboard_tasks_first_test.dart`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```powershell
git add lib/app/modules/home/home_screen.dart test/unit/dashboard_tasks_first_test.dart && git commit -m @'
feat(dashboard): DashboardSectionOrder widget for persona-aware layout

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 4: Wire controller + mount in HomeScreen

**Files:**
- Modify: `lib/app/modules/home/home_controller.dart` (observable + seed + recompute)
- Modify: `lib/app/modules/home/home_screen.dart:76-93` (replace fixed slots 3–5 with `DashboardSectionOrder`)

**Interfaces:**
- Consumes: `HomeController.showTasksFirst` (Task 1), `StorageService.saveDashboardTasksFirst` / `getDashboardTasksFirst` (Task 2), `DashboardSectionOrder` (Task 3).
- Produces: `RxBool HomeController.tasksFirst` read by `HomeScreen` inside an `Obx`.

> Line numbers below are from the file BEFORE Task 1's insertion — anything past ~line 142 in `home_controller.dart` will have shifted by ~15 lines. Match on the quoted code, not the number.

- [ ] **Step 1: Add the observable to `HomeController`**

In `lib/app/modules/home/home_controller.dart`, directly after the `dashboardColumns` declaration (line 89), add:

```dart
  /// Whether "Upcoming tasks" leads the dashboard (manager persona with
  /// open ToDos). Seeded from the persisted per-user verdict so the initial
  /// build doesn't reflow when the async ToDo fetch lands; recomputed by
  /// [_recomputeTasksFirst] after each fetch.
  var tasksFirst = false.obs;
```

- [ ] **Step 2: Seed it in `onInit`**

In `onInit()`, directly after `dashboardColumns.value = _storageService.getDashboardColumns();` (line 112), add:

```dart
    tasksFirst.value = _storageService.getDashboardTasksFirst(
        _authController.currentUser.value?.email ?? '');
```

- [ ] **Step 3: Recompute after every ToDo fetch**

Add this private method directly after `fetchUpcomingTodos()` (after its closing `}`, around line 263):

```dart
  /// Recomputes the section-order verdict from the logged-in user's roles
  /// and the just-fetched ToDo list, then persists it per user so the NEXT
  /// session's initial build starts from this verdict. On a failed fetch
  /// the previous verdict is deliberately kept (no recompute call).
  void _recomputeTasksFirst() {
    final user = _authController.currentUser.value;
    final v = showTasksFirst(
      roles: user?.roles ?? const [],
      hasOpenTodos: upcomingTodos.isNotEmpty,
    );
    tasksFirst.value = v;
    final email = user?.email;
    if (email != null && email.isNotEmpty) {
      _storageService.saveDashboardTasksFirst(email, v);
    }
  }
```

Then wire it into `fetchUpcomingTodos()` at BOTH exit points:

In the empty-email early return (lines 241-244), add the call before `return;`:

```dart
      if (email == null || email.isEmpty) {
        upcomingTodos.clear();
        _recomputeTasksFirst();
        return;
      }
```

And after the successful `assignAll` (line 258):

```dart
        upcomingTodos.assignAll(selectUpcomingTodos(list));
        _recomputeTasksFirst();
```

- [ ] **Step 4: Mount `DashboardSectionOrder` in `HomeScreen`**

In `lib/app/modules/home/home_screen.dart`, replace the fixed slots 3–5 (lines 76-93, from the `// 3 ── Quick Create` comment through the `_buildUpcomingTasks(context),` line inclusive) with:

```dart
                  // 3-5 ── Quick Create / Needs attention / Upcoming tasks ────
                  // Manager persona (manager role + open ToDos) leads with
                  // Upcoming tasks; everyone else keeps Quick Create first.
                  // Only the tasks section moves — the middle block keeps
                  // today's internal order in both modes.
                  Obx(() => DashboardSectionOrder(
                        tasksFirst: controller.tasksFirst.value,
                        tasks: _buildUpcomingTasks(context),
                        middle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              context,
                              'Quick Create',
                              trailing: Obx(() => DashboardColumnsToggle(
                                    columns: controller.dashboardColumns.value,
                                    onChanged: controller.setDashboardColumns,
                                  )),
                            ),
                            const SizedBox(height: 12),
                            _buildQuickAccessGrid(context),
                            const SizedBox(height: 18),
                            _buildNeedsAttention(context),
                          ],
                        ),
                      )),
```

Note: the inner `Obx` around `DashboardColumnsToggle` stays — it keeps a column-toggle tap from rebuilding the whole section block. The comment markers `// 4` and `// 5` disappear with this block; the following section keeps its `// 6 ── Today's pulse` comment unchanged.

- [ ] **Step 5: Analyze and run the focused tests**

Run: `flutter analyze`
Expected: 0 errors (warnings/infos only if pre-existing).

Run: `flutter test test/unit/dashboard_tasks_first_test.dart test/unit/dashboard_columns_test.dart test/unit/dashboard_todo_card_test.dart test/widget/dashboard_revamp_widgets_test.dart`
Expected: PASS — all four files green (unless one of them was already failing in the Task 0 baseline; only NEW failures block).

- [ ] **Step 6: Commit**

```powershell
git add lib/app/modules/home/home_controller.dart lib/app/modules/home/home_screen.dart && git commit -m @'
feat(dashboard): managers with open ToDos see Upcoming tasks first

tasksFirst = manager-ish role AND open ToDos, seeded from a per-user
persisted verdict so the layout never reflows while the ToDo fetch is
in flight. Operator layout is unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 5: Full-suite regression gate

**Files:** none (verification only)

**Interfaces:**
- Consumes: Task 0's baseline file
- Produces: green light for release/smoke

- [ ] **Step 1: Run the full suite**

Run: `flutter test`
Expected: the ONLY failing test files (if any) are the ones already failing in the Task 0 baseline (`$env:LOCALAPPDATA\Temp\claude-test-baseline.txt`). Any newly failing file is a regression from this work — fix it before proceeding.

- [ ] **Step 2: Run the analyzer one last time**

Run: `flutter analyze`
Expected: 0 errors.

- [ ] **Step 3: Report status**

On-device smoke checklist for the user (manual, not automated):
1. Log in as a manager-role user with open ToDos → Upcoming tasks renders between the Scan hero and Quick Create; no reflow after the dashboard settles.
2. Same user, complete/close all ToDos, refresh → layout returns to Quick-Create-first.
3. Log in as an operator (e.g. jawwad@multimax.cloud, standard roles) with an assigned ToDo → Quick Create stays first, tasks show below Needs attention.
4. Kill and relaunch the app as the manager → tasks-first appears on FIRST paint (persisted verdict), no jump when the fetch lands.

No version bump in this plan — bump via `dart run tool/bump_version.dart` per `docs/versioning_conventions.md` only when the user asks to release (this is a `feat:` → MINOR when it ships).
