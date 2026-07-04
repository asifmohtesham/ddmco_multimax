# Selectable Group Warehouse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Session Defaults Default-Warehouse picker select group warehouses (tagged "Group"); the search stock balance already sums across a group's children.

**Architecture:** Add an opt-in `includeGroups` flag to `WarehouseProvider.getWarehouses` (default false keeps every other caller leaf-only). The Session Defaults controller fetches with groups and splits names/group-set via a pure helper; `WarehousePickerSheet` tags group rows. The summing path (`aggregateByItem`) is unchanged.

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), `flutter_test`.

## Global Constraints

- Do NOT change the default behaviour of the shared `WarehouseProvider.getWarehouses()` — Stock Entry, Delivery Note, and Purchase Order rely on it being **leaf-only** (`is_group: 0`). The group inclusion is opt-in via a new default-`false` flag.
- Group warehouses are selectable alongside leaves in one searchable list; group rows carry a small trailing **"Group"** tag. Leaf rows are unchanged.
- Never hardcode surface/ink colours — the tag uses `Theme.of(context).colorScheme` (`surfaceContainerHighest` fill / `onSurfaceVariant` text), contrast-safe in both themes.
- `WarehousePickerSheet`'s new `groupNames` param defaults to `const {}` so its existing usage is unchanged.
- Summing across a group's children is already implemented (`aggregateByItem`); this plan adds NO summing code.
- No new analyzer warnings/errors in touched files.

---

### Task 1: Provider flag + controller group parsing

**Files:**
- Modify: `lib/app/data/providers/warehouse_provider.dart`
- Modify: `lib/app/modules/session_defaults/session_defaults_controller.dart`
- Test: `test/unit/session_defaults_controller_test.dart` (append)

**Interfaces:**
- Produces: `WarehouseProvider.getWarehouses({bool includeGroups = false})`; `RxSet<String> SessionDefaultsController.groupWarehouses`; `static ({List<String> names, Set<String> groups}) SessionDefaultsController.partitionWarehouses(List<dynamic> data)`.

- [ ] **Step 1: Write the failing test**

Append to `test/unit/session_defaults_controller_test.dart` inside `main()`:

```dart
  test('partitionWarehouses splits names and the group-name set', () {
    final data = <Map<String, dynamic>>[
      {'name': 'Stores A - M', 'is_group': 0},
      {'name': 'All Warehouses - M', 'is_group': 1},
      {'name': 'Finished Goods - M', 'is_group': true},
      {'name': 'Raw - M', 'is_group': '1'},
      {'name': '', 'is_group': 0},
    ];
    final r = SessionDefaultsController.partitionWarehouses(data);
    expect(r.names,
        ['Stores A - M', 'All Warehouses - M', 'Finished Goods - M', 'Raw - M']);
    expect(r.groups,
        {'All Warehouses - M', 'Finished Goods - M', 'Raw - M'});
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/session_defaults_controller_test.dart`
Expected: FAIL — `partitionWarehouses` not defined.

- [ ] **Step 3: Add the provider flag**

In `lib/app/data/providers/warehouse_provider.dart`, replace `getWarehouses`:

```dart
  Future<Response> getWarehouses({bool includeGroups = false}) async {
    return _apiProvider.getDocumentList(
      'Warehouse',
      limit: 0, // fetch all — warehouse list is small
      fields: ['name', 'warehouse_name', 'is_group', 'disabled'],
      filters: {
        if (!includeGroups) 'is_group': 0,
        'disabled': 0,
      },
      orderBy: 'name asc',
    );
  }
```

- [ ] **Step 4: Add the controller group state + helper**

In `lib/app/modules/session_defaults/session_defaults_controller.dart`:

Add the observable after `isLoadingWarehouses` (currently line 34):

```dart
  final groupWarehouses = <String>{}.obs;
```

Replace `_loadWarehouses()` (currently lines 64–79) with:

```dart
  Future<void> _loadWarehouses() async {
    isLoadingWarehouses.value = true;
    try {
      final res = await _warehouseProvider.getWarehouses(includeGroups: true);
      final data = res.data['data'] as List? ?? const [];
      final parsed = partitionWarehouses(data);
      warehouses.assignAll(parsed.names);
      groupWarehouses.assignAll(parsed.groups);
    } catch (_) {
      AppNotification.error('Failed to load warehouses');
    } finally {
      isLoadingWarehouses.value = false;
    }
  }

  /// Splits raw Warehouse rows into a name list (kept in received order) and the
  /// set of names that are group warehouses (`is_group` truthy: `1`, `true`, or
  /// `'1'`). Blank names are skipped. Pure — no GetX/DI, so it is unit-testable.
  static ({List<String> names, Set<String> groups}) partitionWarehouses(
    List<dynamic> data,
  ) {
    final names = <String>[];
    final groups = <String>{};
    for (final w in data) {
      final name = (w['name'] ?? '').toString();
      if (name.isEmpty) continue;
      names.add(name);
      final g = w['is_group'];
      if (g == 1 || g == true || g == '1') groups.add(name);
    }
    return (names: names, groups: groups);
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/session_defaults_controller_test.dart`
Expected: PASS (existing tests + the new `partitionWarehouses` test).

- [ ] **Step 6: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/data/providers/warehouse_provider.dart lib/app/modules/session_defaults/session_defaults_controller.dart`
Expected: No new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/app/data/providers/warehouse_provider.dart lib/app/modules/session_defaults/session_defaults_controller.dart test/unit/session_defaults_controller_test.dart
git commit -m "feat(session-defaults): include group warehouses in the default-warehouse list

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Picker "Group" tag + screen wiring

**Files:**
- Modify: `lib/app/modules/global_widgets/warehouse_picker_sheet.dart`
- Modify: `lib/app/modules/session_defaults/session_defaults_screen.dart`
- Test: `test/widget/warehouse_picker_group_tag_test.dart` (create)

**Interfaces:**
- Consumes: `SessionDefaultsController.groupWarehouses` (Task 1).
- Produces: `WarehousePickerSheet({..., Set<String> groupNames = const {}})` — rows whose name is in `groupNames` render a trailing "Group" tag.

- [ ] **Step 1: Write the failing test**

Create `test/widget/warehouse_picker_group_tag_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';

void main() {
  final theme = buildAppTheme(AppScheme.light, Brightness.light);
  Widget app(Widget child) =>
      GetMaterialApp(theme: theme, home: Scaffold(body: child));

  testWidgets('tags group warehouses; leaves have no tag', (tester) async {
    await tester.pumpWidget(app(WarehousePickerSheet(
      warehouses: const ['Stores A - M', 'All Warehouses - M'],
      isLoading: false,
      onSelected: (_) {},
      groupNames: const {'All Warehouses - M'},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Stores A - M'), findsOneWidget);
    expect(find.text('All Warehouses - M'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget); // only the group row
  });

  testWidgets('no tags when groupNames is empty (default)', (tester) async {
    await tester.pumpWidget(app(WarehousePickerSheet(
      warehouses: const ['Stores A - M', 'Stores B - M'],
      isLoading: false,
      onSelected: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Group'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/warehouse_picker_group_tag_test.dart`
Expected: FAIL — `groupNames` is not a parameter of `WarehousePickerSheet`.

- [ ] **Step 3: Add `groupNames` + the tag to the picker**

In `lib/app/modules/global_widgets/warehouse_picker_sheet.dart`:

Add the field + constructor param. Change the constructor and fields block to:

```dart
  const WarehousePickerSheet({
    super.key,
    required this.warehouses,
    required this.isLoading,
    required this.onSelected,
    this.title = 'Select Warehouse',
    this.groupNames = const {},
  });

  final List<String> warehouses;
  final bool isLoading;
  final ValueChanged<String> onSelected;
  final String title;
  final Set<String> groupNames;
```

Replace the `itemBuilder`'s `ListTile` (the `return ListTile(...)` in the `ListView.separated`) with:

```dart
                        itemBuilder: (ctx, i) {
                          final wh = _filtered[i];
                          final isGroup = widget.groupNames.contains(wh);
                          return ListTile(
                            title: Text(wh),
                            trailing: isGroup ? _groupTag(ctx) : null,
                            onTap: () {
                              // Use Navigator.of(ctx).pop() instead of Get.back().
                              // Get.back() unconditionally calls
                              // Get.closeCurrentSnackbar() before popping; when a
                              // SnackbarController is queued but not yet attached to
                              // the Overlay, its late AnimationController throws
                              // LateInitializationError.
                              Navigator.of(ctx).pop();
                              widget.onSelected(wh);
                            },
                          );
                        },
```

Add the `_groupTag` helper inside `_WarehousePickerSheetState` (e.g. above `build`):

```dart
  Widget _groupTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Group',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
```

- [ ] **Step 4: Wire the screen to pass group names**

In `lib/app/modules/session_defaults/session_defaults_screen.dart`, update `_pickWarehouse` (currently lines 236–245) so the sheet receives the group set:

```dart
  void _pickWarehouse(BuildContext context) {
    Get.bottomSheet(
      Obx(() => WarehousePickerSheet(
            warehouses: controller.warehouses.toList(),
            isLoading: controller.isLoadingWarehouses.value,
            groupNames: controller.groupWarehouses.toSet(),
            onSelected: (wh) => controller.selectedWarehouse.value = wh,
          )),
      isScrollControlled: true,
    );
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/widget/warehouse_picker_group_tag_test.dart`
Expected: PASS (both cases).

- [ ] **Step 6: Confirm the existing dark-mode sheet test still passes**

`test/widget/dark_mode_sheet_surfaces_test.dart` builds `WarehousePickerSheet` without `groupNames` — verify the default keeps it green.

Run: `flutter test test/widget/dark_mode_sheet_surfaces_test.dart`
Expected: PASS.

- [ ] **Step 7: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/modules/global_widgets/warehouse_picker_sheet.dart lib/app/modules/session_defaults/session_defaults_screen.dart`
Expected: No issues found.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/global_widgets/warehouse_picker_sheet.dart lib/app/modules/session_defaults/session_defaults_screen.dart test/widget/warehouse_picker_group_tag_test.dart
git commit -m "feat(session-defaults): tag group warehouses in the picker

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count ≤ the 387 baseline and no new issues referencing `warehouse_provider.dart`, `session_defaults_controller.dart`, `warehouse_picker_sheet.dart`, or `session_defaults_screen.dart`. Grep aid: `flutter analyze 2>&1 | grep -Ei "warehouse_provider|session_defaults|warehouse_picker|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass. If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout before treating it as a regression (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual)**

Verify on device:
- Session Defaults → Default Warehouse picker now lists group warehouses too, each with a "Group" tag; leaf warehouses have no tag; search filters both.
- Select a **group** warehouse, save → Dashboard search, type ≥3 chars matching items → each Item row shows the **summed** balance across the group's child warehouses.
- Select a **leaf** warehouse → shows that single warehouse's balance (unchanged from 2.3.0).

---

## Notes / deviations from the spec

- No provider unit test — `WarehouseProvider` wraps a live Dio call with no existing test seam; the one-line filter flag is covered by the on-device smoke and by `partitionWarehouses` (which consumes the shape it returns).
- `_groupTag` uses `colorScheme.surfaceContainerHighest` / `onSurfaceVariant` (Material 3, available on this Flutter version — the codebase already uses the newer `withValues` colour API).

## Versioning

New user-facing capability (group warehouse selectable) → **MINOR** at release time per `docs/versioning_conventions.md`. Not part of this plan.
