# "Set a Default Warehouse" hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a tappable "Set a Default Warehouse to see stock balances" banner above Item search results when no Default Warehouse is set, opening Session Defaults.

**Architecture:** The delegate computes a single `VoidCallback? _onSetWarehouse(context)` — non-null only when `_defaultWarehouse == null && _itemReadable`. `buildResultsList` (All view) and `_ScopedResults` (Items scope) each take that callback and, for the Item group/target, insert a shared `_setWarehouseBanner` after the section header. Tapping closes search and navigates to Session Defaults.

**Tech Stack:** Flutter, GetX, `flutter_test`.

## Global Constraints

- Banner shows only when Item results are present AND `_defaultWarehouse == null` AND `_itemReadable` (encoded as a non-null `onSetWarehouse` callback; null → no banner).
- Banner is **Item-only** (guarded by `target.doctype == 'Item'` at each insertion site).
- Tapping the banner does `close(context, null)` then `Get.toNamed(AppRoutes.SESSION_DEFAULTS)`.
- Colours via `context.scheme.*` (fill `scheme.subtle`, text `scheme.text`/`scheme.textMuted`, icons `scheme.textMuted`/`scheme.textSubtle`) — no hardcoded colours.
- No change to balance fetching, `_trailingFor`, or warehouse-gating; the chevron still shows on rows while no warehouse is set.
- No new analyzer warnings/errors in touched files.

---

### Task 1: Set-warehouse hint banner

**Files:**
- Modify: `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- Test: `test/widget/global_document_search_delegate_test.dart` (banner cases)

**Interfaces:**
- Consumes: the delegate's `_defaultWarehouse`, `_itemReadable`, `_sectionHeader`, `close`; `AppRoutes.SESSION_DEFAULTS`.
- Produces: `buildResultsList(..., {..., VoidCallback? onSetWarehouse})`; `_SearchResultsList` + `_ScopedResults` gain an `onSetWarehouse` field; delegate `_onSetWarehouse(BuildContext) → VoidCallback?`; `_setWarehouseBanner(BuildContext, VoidCallback) → Widget`.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/global_document_search_delegate_test.dart` inside `main()` (the file already imports material, flutter_test, the delegate, `global_search_targets`, `global_search_item`, and has the `_target(...)` helper):

```dart
  testWidgets('Item group shows the set-warehouse banner and taps through',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    var taps = 0;
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            onSetWarehouse: () => taps++,
          ),
        ),
      ),
    ));

    expect(find.text('Set a Default Warehouse to see stock balances'),
        findsOneWidget);
    await tester.tap(find.text('Set a Default Warehouse to see stock balances'));
    expect(taps, 1);
  });

  testWidgets('no set-warehouse banner when onSetWarehouse is null',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              delegate.buildResultsList(context, groups, (t, i) {}),
        ),
      ),
    ));

    expect(find.text('Set a Default Warehouse to see stock balances'),
        findsNothing);
  });

  testWidgets('non-Item group gets no set-warehouse banner even with the callback',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Delivery Note'), items: [
        GlobalSearchItem(id: 'KA-DN-1', title: 'Acme', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            onSetWarehouse: () {},
          ),
        ),
      ),
    ));

    expect(find.text('Set a Default Warehouse to see stock balances'),
        findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: FAIL — `buildResultsList` has no `onSetWarehouse` param (compile error).

- [ ] **Step 3: Add the route import**

In `lib/app/modules/global_widgets/global_document_search_delegate.dart`, add near the other imports:

```dart
import 'package:multimax/app/data/routes/app_routes.dart';
```

- [ ] **Step 4: Add `_onSetWarehouse` + `_setWarehouseBanner` to the delegate**

Add these two methods to the `GlobalDocumentSearchDelegate` class (e.g. just after the `_itemReadable` getter):

```dart
  /// Callback for the "set a Default Warehouse" hint, or null when it should not
  /// show. Non-null only when no Default Warehouse is set and Item is readable —
  /// tapping closes search and opens Session Defaults.
  VoidCallback? _onSetWarehouse(BuildContext context) {
    if (_defaultWarehouse != null || !_itemReadable) return null;
    return () {
      close(context, null);
      Get.toNamed(AppRoutes.SESSION_DEFAULTS);
    };
  }
```

Add the banner builder near the other private render helpers (e.g. after `_trailingFor`):

```dart
  /// Tappable hint shown above Item results when no Default Warehouse is set.
  Widget _setWarehouseBanner(BuildContext context, VoidCallback onTap) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Material(
        color: scheme.subtle,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: scheme.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Set a Default Warehouse to see stock balances',
                    style: TextStyle(fontSize: 13, color: scheme.text),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: scheme.textSubtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 5: Add `onSetWarehouse` to `buildResultsList` and insert the banner**

Replace `buildResultsList` (currently ~lines 314–345) with (adds the param + the Item-group banner):

```dart
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap, {
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading = false,
    VoidCallback? onSetWarehouse,
  }) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
      if (group.target.doctype == 'Item' && onSetWarehouse != null) {
        children.add(_setWarehouseBanner(context, onSetWarehouse));
      }
      for (final item in group.items) {
        children.add(_resultTile(
          context,
          group.target,
          item,
          onTap,
          balances: balances,
          balancesLoading: balancesLoading,
        ));
      }
    }
    return Container(
      color: scheme.bg,
      child: ListView(
        // Clear the Android gesture/nav bar so the last row isn't hidden.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: children,
      ),
    );
  }
```

- [ ] **Step 6: Thread `onSetWarehouse` through `_SearchResultsList`**

In `_SearchResultsList` (the widget), add the field + constructor param and forward it. Add to the constructor params:

```dart
    this.onSetWarehouse,
```
Add the field (near `onTap`):

```dart
  final VoidCallback? onSetWarehouse;
```
In its `build`, pass it to `buildResultsList`:

```dart
    return widget.delegate.buildResultsList(
      context,
      widget.groups,
      widget.onTap,
      balances: _balances,
      balancesLoading: _loading,
      onSetWarehouse: widget.onSetWarehouse,
    );
```

- [ ] **Step 7: Thread `onSetWarehouse` through `_ScopedResults` + render the banner**

In `_ScopedResults` (the widget), add the field + constructor param:

```dart
    this.onSetWarehouse,
```
```dart
  final VoidCallback? onSetWarehouse;
```
In `_ScopedResultsState.build`, replace the `if (i == 0) { return widget.delegate._sectionHeader(context, widget.target); }` branch of the `itemBuilder` with:

```dart
          if (i == 0) {
            final header = widget.delegate._sectionHeader(context, widget.target);
            if (widget.target.doctype == 'Item' &&
                widget.onSetWarehouse != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  widget.delegate
                      ._setWarehouseBanner(context, widget.onSetWarehouse!),
                ],
              );
            }
            return header;
          }
```

- [ ] **Step 8: Wire `_onSetWarehouse` in `_buildResultsArea`**

In `_buildResultsArea`, pass the callback to both branches.

Scoped branch — add to the `_ScopedResults(...)` call:

```dart
        onSetWarehouse: _onSetWarehouse(context),
```

"All" branch — add to the `_SearchResultsList(...)` call:

```dart
          onSetWarehouse: _onSetWarehouse(context),
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: PASS — the 3 new banner cases plus all pre-existing delegate tests (which call `buildResultsList` without `onSetWarehouse` → no banner).

- [ ] **Step 10: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/modules/global_widgets/global_document_search_delegate.dart`
Expected: No issues found (the `app_routes.dart` import is used by `_onSetWarehouse`).

- [ ] **Step 11: Commit**

```bash
git add lib/app/modules/global_widgets/global_document_search_delegate.dart test/widget/global_document_search_delegate_test.dart
git commit -m "feat(search): prompt to set a Default Warehouse when Item balances are hidden

Shows a tappable 'Set a Default Warehouse to see stock balances' banner above
Item results when none is set (→ Session Defaults), so the warehouse-gated
inline balance isn't silently invisible.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count ≤ the 386 baseline; no new issues in `global_document_search_delegate.dart`. Grep aid: `flutter analyze 2>&1 | grep -Ei "global_document_search|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass (existing + the 3 new banner cases). If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual)**

- With **no** Default Warehouse set: search an item term → under ITEMS (both "All" and the "Items" scope) a "Set a Default Warehouse to see stock balances" banner shows above the rows; tapping it opens Session Defaults.
- Set a Default Warehouse → re-search → the banner is gone and Item rows show balances.
- Non-Item results (e.g. Delivery Notes scope) never show the banner.

---

## Notes / deviations from the spec

- `_SearchResultsList`/`_ScopedResults` merely hold and forward `onSetWarehouse`; the delegate computes it once per build via `_onSetWarehouse(context)`.
- The banner text/gate logic is covered through `buildResultsList` (the `@visibleForTesting` seam); the scoped insertion and the live `_defaultWarehouse`/`_itemReadable` gate are verified on-device.

## Versioning

Small search UX addition → **PATCH** at release time, bundled with the pending search Part 1 + Part 2 commits.
