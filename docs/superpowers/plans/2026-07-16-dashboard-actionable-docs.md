# Dashboard "Upcoming & actionable" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Broaden the dashboard's "Upcoming tasks" section into "Upcoming & actionable" — a per-DocType Draft-count strip (Purchase Order, Purchase Receipt, Stock Entry, Delivery Note) plus an open-ToDo count, above the existing ToDo task cards, with a Mine/Everyone scope toggle.

**Architecture:** New controller-free presentation widgets in `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` (enum + models + pure helpers + chip/toggle/strip widgets, following the `dashboard_todo_card.dart` convention of colocating pure helpers with the widget). `HomeController` gains scope state, cached `getDocumentCount` fetches, and chip-tap navigation. Each of the four list controllers gains a 3-line `onReady` hook (mirroring the existing `openCreate` hook) so a chip opens its list pre-filtered to Draft.

**Tech Stack:** Flutter, GetX (state + DI + routing), Dio (`ApiProvider`), Frappe/ERPNext REST (`frappe.client.get_count`), GetStorage (`StorageService`).

## Global Constraints

- **Semver:** This is a **feature** → **MINOR** bump per `docs/versioning_conventions.md` (do NOT default to PATCH). Build number `+B` always increments by 1. Release is performed by the user; the plan does not bump the version.
- **Contrast (enforced by `test/unit/theme_contrast_test.dart` + dark-mode widget tests):** theme tokens only — `context.scheme.fg`/`surface`/`subtle`/`border`/`text`/`textMuted`/`textSubtle`, and the `AppColors` ramp (x700 light / x300 dark). Never `Colors.white`/`grey.shadeX`/`black87` for surfaces or ink.
- **Async feedback (per CLAUDE.md):** the strip shows visible loading (muted placeholder pills) while counts resolve; `setActionableScope`/`fetchActionableCounts` are re-entrancy-safe and clear their busy flag in a `finally`.
- **Widgets are controller-free** — `dashboard_actionable_strip.dart` must not import `HomeController`; it is unit/widget-testable with a plain `MaterialApp(theme: ThemeData(brightness:))`.
- **Actionable = Draft only:** PO/PR/DN → `{status: 'Draft'}`, SE → `{docstatus: 0}` (SE has no `status` field). Under **Mine**, add `{owner: <email>}`. The **same** filter builder feeds both the count query and the tap-target list, so a chip's count always equals its list length.
- **Tasks chip stays personal** in both toggle states (mirrors the task cards); only the four document chips flip Mine↔Everyone.
- DRY, YAGNI, TDD, frequent commits.
- **Before each commit**, re-check `git branch --show-current` (branch can change mid-session; the user releases concurrently).

---

### Task 1: Pure helpers, enum, and chip-data model

**Files:**
- Create: `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` (helpers only in this task; widgets added in Task 2)
- Test: `test/unit/actionable_filters_test.dart`

**Interfaces:**
- Produces:
  - `enum ActionableScope { mine, everyone }`
  - `Map<String, dynamic> actionableFiltersFor(String doctype, ActionableScope scope, String? email)`
  - `String actionableCacheKey(ActionableScope scope, String? email)`
  - `String actionableScopeToString(ActionableScope scope)`
  - `ActionableScope actionableScopeFromString(String? raw)`
  - `class ActionableChipData { final String doctype; final String label; final IconData icon; final int count; final VoidCallback? onTap; bool get muted; }`
  - `class ActionableDocConfig { final String doctype; final String label; final IconData icon; final String listRoute; }`
  - `const List<ActionableDocConfig> kActionableDocConfigs`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/actionable_filters_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';

void main() {
  group('actionableFiltersFor', () {
    test('PO/PR/DN filter on status Draft', () {
      for (final dt in const ['Purchase Order', 'Purchase Receipt', 'Delivery Note']) {
        expect(actionableFiltersFor(dt, ActionableScope.everyone, 'x@y.com'),
            {'status': 'Draft'});
      }
    });

    test('Stock Entry filters on docstatus 0 (no status field)', () {
      expect(actionableFiltersFor('Stock Entry', ActionableScope.everyone, 'x@y.com'),
          {'docstatus': 0});
    });

    test('mine scope adds owner', () {
      expect(actionableFiltersFor('Delivery Note', ActionableScope.mine, 'a@b.com'),
          {'status': 'Draft', 'owner': 'a@b.com'});
      expect(actionableFiltersFor('Stock Entry', ActionableScope.mine, 'a@b.com'),
          {'docstatus': 0, 'owner': 'a@b.com'});
    });

    test('mine scope with null/empty email omits owner', () {
      expect(actionableFiltersFor('Delivery Note', ActionableScope.mine, null),
          {'status': 'Draft'});
      expect(actionableFiltersFor('Delivery Note', ActionableScope.mine, ''),
          {'status': 'Draft'});
    });
  });

  group('actionableCacheKey', () {
    test('mine keys by email; everyone is user-independent', () {
      expect(actionableCacheKey(ActionableScope.mine, 'a@b.com'), 'mine::a@b.com');
      expect(actionableCacheKey(ActionableScope.everyone, 'a@b.com'), 'all');
      expect(actionableCacheKey(ActionableScope.everyone, null), 'all');
    });
  });

  group('scope <-> string', () {
    test('round trips and defaults to mine', () {
      expect(actionableScopeToString(ActionableScope.mine), 'mine');
      expect(actionableScopeToString(ActionableScope.everyone), 'everyone');
      expect(actionableScopeFromString('everyone'), ActionableScope.everyone);
      expect(actionableScopeFromString('mine'), ActionableScope.mine);
      expect(actionableScopeFromString('garbage'), ActionableScope.mine);
      expect(actionableScopeFromString(null), ActionableScope.mine);
    });
  });

  group('kActionableDocConfigs', () {
    test('covers the four transactional DocTypes in strip order', () {
      expect(kActionableDocConfigs.map((c) => c.doctype).toList(),
          ['Purchase Order', 'Purchase Receipt', 'Stock Entry', 'Delivery Note']);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/actionable_filters_test.dart`
Expected: FAIL — `Error: Not found: ...dashboard_actionable_strip.dart` / undefined names.

- [ ] **Step 3: Create the file with helpers, enum, model, config**

```dart
// lib/app/modules/home/widgets/dashboard_actionable_strip.dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Which population the actionable count strip reflects. [mine] scopes the
/// four document chips to the selected dashboard user (owner); [everyone] is
/// company-wide. The Tasks chip stays personal regardless.
enum ActionableScope { mine, everyone }

String actionableScopeToString(ActionableScope scope) =>
    scope == ActionableScope.everyone ? 'everyone' : 'mine';

ActionableScope actionableScopeFromString(String? raw) =>
    raw == 'everyone' ? ActionableScope.everyone : ActionableScope.mine;

/// Frappe filter map for the "still a Draft" documents of [doctype]. Used for
/// BOTH the `get_count` query and the tap-target list, so a chip's count and
/// its opened list always agree.
///
/// PO/PR/DN filter on `status == 'Draft'` (equivalent to docstatus 0 for these
/// submittables, and it renders a removable "Status: Draft" chip on the list).
/// Stock Entry has no `status` field — its status is derived from docstatus —
/// so it filters on `docstatus == 0`. Under [ActionableScope.mine] a non-empty
/// [email] adds an `owner` equality.
Map<String, dynamic> actionableFiltersFor(
    String doctype, ActionableScope scope, String? email) {
  final filters = <String, dynamic>{};
  if (doctype == 'Stock Entry') {
    filters['docstatus'] = 0;
  } else {
    filters['status'] = 'Draft';
  }
  if (scope == ActionableScope.mine && email != null && email.isNotEmpty) {
    filters['owner'] = email;
  }
  return filters;
}

/// Cache key for a scope's counts. `mine` depends on the viewed user; `everyone`
/// is user-independent so it collapses to a single `'all'` bucket.
String actionableCacheKey(ActionableScope scope, String? email) =>
    scope == ActionableScope.mine ? 'mine::${email ?? ''}' : 'all';

/// Static identity of one document chip — label/icon/route are presentation
/// constants; the live count is supplied separately via [ActionableChipData].
class ActionableDocConfig {
  final String doctype;
  final String label;
  final IconData icon;
  final String listRoute;
  const ActionableDocConfig(this.doctype, this.label, this.icon, this.listRoute);
}

const List<ActionableDocConfig> kActionableDocConfigs = [
  ActionableDocConfig('Purchase Order', 'PO', Icons.shopping_cart_outlined, AppRoutes.PURCHASE_ORDER),
  ActionableDocConfig('Purchase Receipt', 'PR', Icons.receipt_long_outlined, AppRoutes.PURCHASE_RECEIPT),
  ActionableDocConfig('Stock Entry', 'SE', Icons.swap_horiz, AppRoutes.STOCK_ENTRY),
  ActionableDocConfig('Delivery Note', 'DN', Icons.local_shipping_outlined, AppRoutes.DELIVERY_NOTE),
];

/// One rendered chip's data. [muted] (a zero count) renders dim and passes a
/// null [onTap] so the chip is non-interactive.
class ActionableChipData {
  final String doctype;
  final String label;
  final IconData icon;
  final int count;
  final VoidCallback? onTap;
  const ActionableChipData({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  bool get muted => count == 0;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/actionable_filters_test.dart`
Expected: PASS (all groups green).

- [ ] **Step 5: Commit**

```bash
git branch --show-current   # confirm the feature branch
git add lib/app/modules/home/widgets/dashboard_actionable_strip.dart test/unit/actionable_filters_test.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): actionable-count filter helpers + chip model

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Presentational widgets (chip, toggle, strip)

**Files:**
- Modify: `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` (append widgets)
- Test: `test/unit/dashboard_actionable_strip_test.dart`

**Interfaces:**
- Consumes (Task 1): `ActionableChipData`, `ActionableScope`.
- Produces:
  - `class ActionableCountChip extends StatelessWidget { final ActionableChipData data; }`
  - `class ActionableScopeToggle extends StatelessWidget { final ActionableScope scope; final ValueChanged<ActionableScope> onChanged; }`
  - `class DashboardActionableStrip extends StatelessWidget { final List<ActionableChipData> chips; final bool isLoading; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/dashboard_actionable_strip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';

Future<void> _pump(WidgetTester t, Widget child,
        {Brightness b = Brightness.light}) =>
    t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: child),
    ));

ActionableChipData _chip(String label, int count, VoidCallback? onTap) =>
    ActionableChipData(
        doctype: label, label: label, icon: Icons.circle, count: count, onTap: onTap);

void main() {
  group('ActionableCountChip', () {
    testWidgets('renders label and count', (t) async {
      await _pump(t, ActionableCountChip(data: _chip('PO', 3, () {})));
      expect(find.text('PO'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('fires onTap when not muted', (t) async {
      var tapped = false;
      await _pump(t, ActionableCountChip(data: _chip('SE', 2, () => tapped = true)));
      await t.tap(find.byType(ActionableCountChip));
      expect(tapped, isTrue);
    });

    testWidgets('muted chip (count 0) has no ink well', (t) async {
      await _pump(t, ActionableCountChip(data: _chip('DN', 0, null)));
      expect(find.text('DN'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('renders in dark mode', (t) async {
      await _pump(t, ActionableCountChip(data: _chip('PR', 5, () {})),
          b: Brightness.dark);
      expect(find.text('PR'), findsOneWidget);
    });
  });

  group('ActionableScopeToggle', () {
    testWidgets('tapping Everyone reports the everyone scope', (t) async {
      ActionableScope? got;
      await _pump(t, ActionableScopeToggle(
          scope: ActionableScope.mine, onChanged: (s) => got = s));
      await t.tap(find.text('Everyone'));
      expect(got, ActionableScope.everyone);
    });

    testWidgets('tapping Mine reports the mine scope', (t) async {
      ActionableScope? got;
      await _pump(t, ActionableScopeToggle(
          scope: ActionableScope.everyone, onChanged: (s) => got = s));
      await t.tap(find.text('Mine'));
      expect(got, ActionableScope.mine);
    });
  });

  group('DashboardActionableStrip', () {
    testWidgets('renders one chip per data entry', (t) async {
      await _pump(t, DashboardActionableStrip(isLoading: false, chips: [
        _chip('PO', 1, () {}),
        _chip('DN', 0, null),
      ]));
      expect(find.byType(ActionableCountChip), findsNWidgets(2));
    });

    testWidgets('isLoading shows placeholders, not chips', (t) async {
      await _pump(t, const DashboardActionableStrip(isLoading: true, chips: []));
      expect(find.byType(ActionableCountChip), findsNothing);
      expect(find.byKey(const ValueKey('actionable-strip-loading')), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/dashboard_actionable_strip_test.dart`
Expected: FAIL — undefined `ActionableCountChip` / `ActionableScopeToggle` / `DashboardActionableStrip`.

- [ ] **Step 3: Append the widgets**

Add `import 'package:multimax/app/data/constants/app_theme.dart';` to the top of `dashboard_actionable_strip.dart` (for `context.scheme`, `AppColors`, `AppRadius`), then append:

```dart
/// A compact pill: icon + short label + count. A [ActionableChipData.muted]
/// (zero) chip renders dim and is not wrapped in an InkWell (non-interactive);
/// otherwise the whole pill is tappable.
class ActionableCountChip extends StatelessWidget {
  final ActionableChipData data;
  const ActionableCountChip({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;
    final muted = data.muted;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon,
              size: 16, color: muted ? scheme.textSubtle : cs.primary),
          const SizedBox(width: 6),
          Text(
            data.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: muted ? scheme.textMuted : scheme.text,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${data.count}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: muted ? scheme.textSubtle : cs.primary,
            ),
          ),
        ],
      ),
    );

    if (muted || data.onTap == null) {
      return Opacity(opacity: 0.55, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: content,
      ),
    );
  }
}

/// Two-segment "Mine | Everyone" control, styled after DashboardColumnsToggle.
class ActionableScopeToggle extends StatelessWidget {
  final ActionableScope scope;
  final ValueChanged<ActionableScope> onChanged;
  const ActionableScopeToggle({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scheme = context.scheme;

    Widget seg(ActionableScope value, String label) {
      final selected = scope == value;
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? cs.primary : scheme.textSubtle,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ActionableScope.mine, 'Mine'),
          const SizedBox(width: 2),
          seg(ActionableScope.everyone, 'Everyone'),
        ],
      ),
    );
  }
}

/// The wrap of actionable-count chips. Shows muted placeholder pills while
/// [isLoading]; otherwise a [Wrap] of [ActionableCountChip]s (one per [chips]).
class DashboardActionableStrip extends StatelessWidget {
  final List<ActionableChipData> chips;
  final bool isLoading;
  const DashboardActionableStrip({
    super.key,
    required this.chips,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    if (isLoading) {
      return Wrap(
        key: const ValueKey('actionable-strip-loading'),
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          5,
          (_) => Container(
            width: 64,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.subtle,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: scheme.border),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final c in chips) ActionableCountChip(data: c)],
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/dashboard_actionable_strip_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/widgets/dashboard_actionable_strip.dart test/unit/dashboard_actionable_strip_test.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): actionable count chip, scope toggle, strip widgets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: HomeController wiring + scope persistence

**Files:**
- Modify: `lib/app/modules/home/home_controller.dart`
- Modify: `lib/app/data/services/storage_service.dart`

**Interfaces:**
- Consumes (Task 1): `ActionableScope`, `actionableFiltersFor`, `actionableCacheKey`, `actionableScopeToString`, `actionableScopeFromString`, `kActionableDocConfigs`.
- Produces (used by Task 5 screen):
  - `Rx<ActionableScope> actionableScope`
  - `RxBool isLoadingActionable`
  - `RxMap<String, int> actionableCounts`
  - `RxInt openTodoCount`
  - `void setActionableScope(ActionableScope scope)`
  - `void openActionableList(String doctype)`
  - `Future<void> fetchActionableCounts({bool force})`

> **Note:** This task's deliverable is verified by `flutter analyze` + `flutter test` (existing suite stays green) and on-device in Task 5. The GetStorage getters mirror the existing (untested) `getDashboardColumns`/`saveDashboardColumns` pair, so they carry no separate unit test; the pure `actionableScopeFromString`/`ToString` mapping they rely on is already covered by Task 1.

- [ ] **Step 1: Add the StorageService persistence methods**

In `lib/app/data/services/storage_service.dart`, alongside `getDashboardColumns`/`saveDashboardColumns` (~line 141), add a key constant next to the other dashboard keys and these two methods:

```dart
  // (add near _dashboardColumnsKey / _dashboardTasksFirstKey)
  static const _dashboardActionableScopeKey = 'dashboard_actionable_scope';

  // Persisted Mine/Everyone choice for the "Upcoming & actionable" strip.
  // Stored as 'mine' | 'everyone'; any other value reads back as 'mine'.
  Future<void> saveDashboardActionableScope(String value) async =>
      _box.write(_dashboardActionableScopeKey, value);

  String getDashboardActionableScope() =>
      _box.read<String>(_dashboardActionableScopeKey) == 'everyone'
          ? 'everyone'
          : 'mine';
```

> Match the exact declaration style used by the surrounding keys/methods (confirm the private-key constants block; `_box` is the shared `GetStorage`).

- [ ] **Step 2: Add imports + state to HomeController**

At the top of `lib/app/modules/home/home_controller.dart` add:

```dart
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
```

Inside `HomeController`, near `upcomingTodos` (line 86), add:

```dart
  /// Draft counts for the four transactional DocTypes, keyed by doctype, for
  /// the currently displayed [actionableScope]. Only DocTypes the user can
  /// read appear as keys.
  final actionableCounts = <String, int>{}.obs;

  /// Number of open ToDos for the selected user (personal in both scopes) —
  /// drives the Tasks chip. Derived from the [fetchUpcomingTodos] fetch.
  final openTodoCount = 0.obs;

  /// Mine/Everyone scope for the four document chips. Seeded from storage in
  /// [onInit]; the Tasks chip is unaffected by it.
  final actionableScope = ActionableScope.mine.obs;

  /// True until the first count fetch for the current scope resolves (drives
  /// the strip's loading placeholders). Starts true so the first build shows
  /// placeholders rather than an empty strip.
  final isLoadingActionable = true.obs;

  /// Counts cache keyed by [actionableCacheKey] — `mine::<email>` / `all`.
  final Map<String, Map<String, int>> _actionableCountCache = {};
```

- [ ] **Step 3: Seed scope in onInit**

In `onInit` (after the `tasksFirst.value = ...` seed, ~line 119), add:

```dart
    actionableScope.value =
        actionableScopeFromString(_storageService.getDashboardActionableScope());
```

- [ ] **Step 4: Add the fetch, toggle, and navigator methods**

Add these methods to `HomeController` (e.g. just after `fetchUpcomingTodos`):

```dart
  /// Fetches Draft counts for accessible document DocTypes in the current
  /// [actionableScope]. Serves a cached result when present unless [force].
  /// `mine` counts key by the viewed user's email; `everyone` counts are
  /// user-independent. Only DocTypes the user can read are queried (no 403s).
  Future<void> fetchActionableCounts({bool force = false}) async {
    final scope = actionableScope.value;
    final email = selectedFilterUser.value?.email ??
        _authController.currentUser.value?.email;
    final key = actionableCacheKey(scope, email);

    if (force) _actionableCountCache.clear();

    final cached = _actionableCountCache[key];
    if (cached != null) {
      actionableCounts.assignAll(cached);
      isLoadingActionable.value = false;
      return;
    }

    isLoadingActionable.value = true;
    try {
      final perm = Get.find<PermissionService>();
      final doctypes = <String>[];
      final requests = <Future<Response>>[];
      for (final cfg in kActionableDocConfigs) {
        if (perm.hasAccess(cfg.doctype) != true) continue;
        doctypes.add(cfg.doctype);
        requests.add(_apiProvider.getDocumentCount(
          cfg.doctype,
          filters: actionableFiltersFor(cfg.doctype, scope, email),
        ));
      }
      final responses = await Future.wait(requests);
      final counts = <String, int>{};
      for (var i = 0; i < doctypes.length; i++) {
        counts[doctypes[i]] = _extractCount(responses[i]);
      }
      _actionableCountCache[key] = counts;
      // Guard against a scope flip landing before this fetch returns.
      if (scope == actionableScope.value) actionableCounts.assignAll(counts);
    } catch (e) {
      print('Error fetching actionable counts: $e');
    } finally {
      if (scope == actionableScope.value) isLoadingActionable.value = false;
    }
  }

  /// Flips the strip scope, persists it, and loads the new scope's counts
  /// (served from cache when available, so a second flip is instant).
  void setActionableScope(ActionableScope scope) {
    if (actionableScope.value == scope) return;
    actionableScope.value = scope;
    _storageService.saveDashboardActionableScope(actionableScopeToString(scope));
    fetchActionableCounts();
  }

  /// Opens [doctype]'s list pre-filtered to Draft (+ owner under Mine), via the
  /// list controller's onReady `filters` hook (Task 4).
  void openActionableList(String doctype) {
    final cfg =
        kActionableDocConfigs.firstWhereOrNull((c) => c.doctype == doctype);
    if (cfg == null) return;
    final email = selectedFilterUser.value?.email ??
        _authController.currentUser.value?.email;
    Get.toNamed(cfg.listRoute, arguments: {
      'filters': actionableFiltersFor(doctype, actionableScope.value, email),
    });
  }
```

- [ ] **Step 5: Derive the ToDo count and widen the fetch**

In `fetchUpcomingTodos`, change `limit: 20` to `limit: 50`, and set `openTodoCount` from the fetched (pre-cap) list. Replace the success block:

```dart
      if (res.statusCode == 200 && res.data['data'] != null) {
        final list = (res.data['data'] as List)
            .map((e) => ToDo.fromJson(e))
            .toList();
        openTodoCount.value = list.length;
        upcomingTodos.assignAll(selectUpcomingTodos(list));
        _recomputeTasksFirst();
      }
```

Also set `openTodoCount.value = 0;` in the early-return branch where `email` is null/empty (next to `upcomingTodos.clear();`).

- [ ] **Step 6: Trigger count fetch on load / refresh**

In `fetchDashboardData`, change the final `await Future.wait([...])` (line ~250) to also fetch actionable counts (force, since this method is the load + refresh entry point):

```dart
      await Future.wait([
        _fetchActiveWipJc(),
        fetchUpcomingTodos(),
        fetchActionableCounts(force: true),
      ]);
```

- [ ] **Step 7: Verify analyzer + full suite**

Run: `flutter analyze`
Expected: no new errors/warnings for the edited files.

Run: `flutter test`
Expected: existing suite still green (baseline: ~952 pass / ~24 pre-existing fails per project memory — no NEW failures).

- [ ] **Step 8: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/home_controller.dart lib/app/data/services/storage_service.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): actionable-count state, cached fetch, scope toggle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: List-controller `onReady` filter hook (PO/PR/SE/DN)

**Files:**
- Modify: `lib/app/modules/purchase_order/purchase_order_controller.dart` (`onReady`)
- Modify: `lib/app/modules/purchase_receipt/purchase_receipt_controller.dart` (`onReady`)
- Modify: `lib/app/modules/stock_entry/stock_entry_controller.dart` (`onReady`)
- Modify: `lib/app/modules/delivery_note/delivery_note_controller.dart` (`onReady`)

**Interfaces:**
- Consumes: the existing `applyFilters(Map<String, dynamic>)` on each controller (confirmed present: PO:121, PR:62, SE:86, DN:83) and the `{'filters': ...}` route argument produced by `HomeController.openActionableList` (Task 3).
- Produces: nothing new — behavioural change only.

> **Verification:** GetX `onReady`/route-argument behaviour is not unit-tested in this repo; this task is verified by `flutter analyze` and the on-device drive in Task 5. Each edit is the identical 3-line addition, reviewed together.

- [ ] **Step 1: Add the hook to each controller's `onReady`**

In each of the four controllers, extend `onReady` so it reads a `filters` argument in addition to the existing `openCreate`. For **Delivery Note** (its `onReady` currently only handles `openCreate`, lines 72-76):

```dart
  @override
  void onReady() {
    super.onReady();
    final args = Get.arguments;
    if (args is Map && args['openCreate'] == true) {
      openCreateDialog();
    }
    if (args is Map && args['filters'] is Map) {
      applyFilters(Map<String, dynamic>.from(args['filters'] as Map));
    }
  }
```

Apply the **same** two-branch shape to `purchase_order_controller.dart` (onReady ~63), `purchase_receipt_controller.dart` (onReady ~47), and `stock_entry_controller.dart` (onReady ~79). Keep each file's existing `openCreate` branch intact — only add the `filters` branch (and hoist `Get.arguments` into a local `args` as shown, so it is read once).

- [ ] **Step 2: Verify analyzer**

Run: `flutter analyze`
Expected: no new errors/warnings in the four controllers.

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add lib/app/modules/purchase_order/purchase_order_controller.dart lib/app/modules/purchase_receipt/purchase_receipt_controller.dart lib/app/modules/stock_entry/stock_entry_controller.dart lib/app/modules/delivery_note/delivery_note_controller.dart
git commit -m "$(cat <<'EOF'
feat(lists): honor a `filters` route arg to open a pre-filtered list

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Dashboard screen integration + end-to-end verification

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart` (replace `_buildUpcomingTasks`; add `_actionableChips`; add import)

**Interfaces:**
- Consumes: `DashboardActionableStrip`, `ActionableScopeToggle`, `ActionableChipData`, `kActionableDocConfigs` (Task 2/1); `controller.actionableCounts`, `openTodoCount`, `actionableScope`, `isLoadingActionable`, `setActionableScope`, `openActionableList`, `upcomingTodos`, `goToToDo` (Task 3).

- [ ] **Step 1: Add imports**

At the top of `home_screen.dart` add (if not already imported):

```dart
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/data/services/permission_service.dart';
```

- [ ] **Step 2: Replace the section builder**

Replace the entire `_buildUpcomingTasks` method (lines 301-335) with the following. Note the outer `DocTypeGuard(doctype: 'ToDo', ...)` is **removed** — the section is no longer ToDo-gated (a user with only PO access should still see the strip); the Tasks chip and cards are gated on ToDo access individually.

```dart
  // ---------------------------------------------------------------------------
  // Upcoming & actionable — Draft counts across PO/PR/SE/DN + open ToDos,
  // with a Mine/Everyone scope toggle, above the open-ToDo task cards.
  // ---------------------------------------------------------------------------
  Widget _buildUpcomingActionable(BuildContext context) {
    return Obx(() {
      final chips = _actionableChips(context);
      final todos = controller.upcomingTodos;
      final loading = controller.isLoadingActionable.value;

      // Nothing to show and nothing loading → collapse entirely.
      if (chips.isEmpty && todos.isEmpty && !loading) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Upcoming & actionable',
            trailing: ActionableScopeToggle(
              scope: controller.actionableScope.value,
              onChanged: controller.setActionableScope,
            ),
          ),
          const SizedBox(height: 11),
          DashboardActionableStrip(chips: chips, isLoading: loading),
          if (todos.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var i = 0; i < todos.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              DashboardTodoCard(
                todo: todos[i],
                onTap: () => Get.toNamed(
                  AppRoutes.TODO_FORM,
                  arguments: {'name': todos[i].name, 'mode': 'view'},
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.goToToDo,
                child: const Text('View all tasks'),
              ),
            ),
          ],
          const SizedBox(height: 6),
        ],
      );
    });
  }

  /// Builds the chip data: one per accessible document DocType (present in
  /// [actionableCounts]) in [kActionableDocConfigs] order, then a personal
  /// Tasks chip when the user can read ToDos. A zero count → non-tappable.
  List<ActionableChipData> _actionableChips(BuildContext context) {
    final chips = <ActionableChipData>[];
    for (final cfg in kActionableDocConfigs) {
      if (!controller.actionableCounts.containsKey(cfg.doctype)) continue;
      final count = controller.actionableCounts[cfg.doctype] ?? 0;
      chips.add(ActionableChipData(
        doctype: cfg.doctype,
        label: cfg.label,
        icon: cfg.icon,
        count: count,
        onTap: count == 0 ? null : () => controller.openActionableList(cfg.doctype),
      ));
    }
    if (Get.find<PermissionService>().hasAccess('ToDo') == true) {
      final count = controller.openTodoCount.value;
      chips.add(ActionableChipData(
        doctype: 'ToDo',
        label: 'Tasks',
        icon: Icons.check_circle_outline,
        count: count,
        onTap: count == 0 ? null : controller.goToToDo,
      ));
    }
    return chips;
  }
```

- [ ] **Step 3: Point the section-order wiring at the new builder**

In the dashboard `build` (line ~83), update the `tasks:` argument:

```dart
                  Obx(() => DashboardSectionOrder(
                        tasksFirst: controller.tasksFirst.value,
                        tasks: _buildUpcomingActionable(context),
                        middle: Column(
```

- [ ] **Step 4: Verify analyzer + full suite**

Run: `flutter analyze`
Expected: no new errors/warnings. (Confirm the old `_buildUpcomingTasks` name is fully gone — no dangling references.)

Run: `flutter test`
Expected: existing suite green; new unit/widget tests from Tasks 1-2 green.

- [ ] **Step 5: Verify on-device (use the `verify` / `run` skill)**

Drive the running app and confirm:
1. Dashboard loads → the strip shows five chips (PO/PR/SE/DN/Tasks) with counts; zero counts render dim and non-tappable.
2. Tapping a non-zero **PO/PR/DN** chip opens that list showing only Drafts (a "Status: Draft" filter chip is visible); tapping **SE** opens Drafts (docstatus 0). Under **Mine**, results are limited to the selected user's documents.
3. The **Mine ⇄ Everyone** toggle flips the four document chips' counts (Everyone ≥ Mine); the **Tasks** chip is unchanged by the toggle. Toggling back is instant (cached). The choice survives an app restart.
4. Switching the "Viewing …" user updates the **Mine** counts; **Everyone** stays constant.
5. Task cards still render below the strip and deep-link to the ToDo form; "View all tasks" opens the ToDo list.
6. Dark mode: chips, toggle, and placeholders are legible (theme tokens only).

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/home_screen.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): render Upcoming & actionable strip above task cards

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- §1 broadened section + rename → Task 5 (`_buildUpcomingActionable`, "Upcoming & actionable").
- §2 Draft-only definitions (SE docstatus vs PO/PR/DN status) → Task 1 `actionableFiltersFor` + tests.
- §3 Mine/Everyone toggle, Tasks-personal, per-session persistence → Task 2 toggle, Task 3 `setActionableScope`/storage, Task 1 scope↔string.
- §4 light-on-load fetch, lazy + cached per (scope,email), access-gated, ToDo count via existing fetch → Task 3 `fetchActionableCounts` + `openTodoCount`.
- §5 chip tap → pre-filtered list via `onReady` hook → Task 4 (+ Task 3 `openActionableList`).
- §6 always-show muted zero chips; section visibility; persona rule unchanged → Task 2 muted chip, Task 5 visibility (`DashboardSectionOrder`/`showTasksFirst` untouched).
- §7 controller-free components → Tasks 1-2 (widget file imports no controller).
- §8 async feedback → Task 2 loading placeholders + Task 3 `isLoadingActionable` in `finally`.
- §9 testing → Tasks 1-2 unit/widget tests; Task 3/5 suite + on-device.

**Refinement vs spec (noted):** the spec listed the count filter as `docstatus:0` and the tap filter as `status:'Draft'` separately; the plan uses **one** builder (`status:'Draft'` for PO/PR/DN, `docstatus:0` for SE) for both, guaranteeing a chip's count equals its opened list. Consequently PO/PR/DN lists show a visible "Draft" chip; SE still shows none (the accepted minor cosmetic gap from spec §5).

**Placeholder scan:** no TBD/TODO/"handle edge cases"; every code step shows complete code.

**Type consistency:** `actionableFiltersFor`, `actionableCacheKey`, `actionableScope`, `actionableCounts`, `openTodoCount`, `isLoadingActionable`, `setActionableScope`, `openActionableList`, `ActionableChipData`, `ActionableScopeToggle`, `DashboardActionableStrip`, `kActionableDocConfigs` are used identically across Tasks 1→5.

## Out of Scope
- Submitted/pending states (PO To Receive, PR To Bill), the `showTasksFirst` persona rule, company-wide ToDo counting, and any list-screen change beyond the `onReady` hook (and the accepted SE "Draft"-chip cosmetic gap).
- The version bump + release (user-driven; this is a **MINOR** feature per Global Constraints).
