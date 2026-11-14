# Inline Warehouse Balance on Item Search Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each matched Item's Default-Warehouse balance inline (bold trailing qty) on the Dashboard global-search Item rows — summed across children for a group warehouse — replacing the separate footer section.

**Architecture:** The service aggregates Stock Balance rows per item (summing across warehouses, so a group warehouse totals its children). A stateful `_SearchResultsList` renders the groups immediately, then fetches balances for the Item group's known codes and rebuilds so each Item row's trailing slot swaps loader→qty. The old footer-section widgets are removed.

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), `flutter_test`.

## Global Constraints

- Never hardcode surface/ink colours — use `context.scheme.*`; the loader must be visible on `scheme.bg`.
- Async work gives immediate, painted, visible loading feedback (per-row loader here).
- Balance is shown on **Item** rows only (`target.doctype == 'Item'`); other doctypes keep the chevron.
- Feature is OFF (Item rows keep the chevron) when there is no Default Warehouse, the user lacks Item read access, or the fetch errors — document search must never break.
- Group warehouse total = sum of `bal_qty` across all returned rows per item (ERPNext expands a group-warehouse filter to descendant leaf rows). Assumption to confirm on-device.
- `getStockBalanceReport` handles the single-vs-multi item-code filter across ERPNext versions; the caller narrows returned rows to the requested codes client-side.
- No new analyzer warnings/errors in touched files.
- `buildResultsList` must keep working for callers that pass only its 3 positional args (existing tests) — new params are optional with defaults that reproduce today's behaviour (chevron).

---

### Task 1: Service — `warehouseBalances` + `aggregateByItem` (replace the query/map/codes helpers)

**Files:**
- Modify: `lib/app/data/services/global_search_service.dart` (replace `stockBalanceForQuery`, `itemCodesFrom`, `mapStockLines` — lines 144–194 — with the two methods below; keep `_num`/`_today`)
- Test: `test/unit/global_search_stock_balance_test.dart` (replace contents)

**Interfaces:**
- Consumes: `ApiProvider.getStockBalanceReport({required String fromDate, required String toDate, List<String>? itemCodes, String? warehouse})` → `({List<Map<String,dynamic>> columns, List<Map<String,dynamic>> rows})`; existing `_num`/`_today` statics; `WarehouseStockLine(itemCode, itemName, balanceQty, uom)`.
- Produces: `Future<Map<String, WarehouseStockLine>> warehouseBalances(List<String> itemCodes, String warehouse)`; `static Map<String, WarehouseStockLine> aggregateByItem(List<Map<String,dynamic>> rows)`.

- [ ] **Step 1: Replace the unit test**

Overwrite `test/unit/global_search_stock_balance_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('aggregateByItem', () {
    test('sums bal_qty across warehouses per item (group warehouse case)', () {
      final rows = <Map<String, dynamic>>[
        {'item_code': 'FG-1', 'item_name': 'Blue Strap', 'bal_qty': 12, 'stock_uom': 'Nos', 'warehouse': 'Stores A'},
        {'item_code': 'FG-1', 'bal_qty': 8, 'warehouse': 'Stores B'},
        {'item_code': 'FG-2', 'balance_qty': '3.5', 'stock_uom': 'Mtr'},
        {'item_code': '', 'bal_qty': 99},
      ];
      final map = GlobalSearchService.aggregateByItem(rows);
      expect(map.length, 2);
      expect(map['FG-1']!.balanceQty, 20); // 12 + 8 across two warehouses
      expect(map['FG-1']!.itemName, 'Blue Strap'); // first row carrying it
      expect(map['FG-1']!.uom, 'Nos');
      expect(map['FG-2']!.balanceQty, 3.5); // legacy balance_qty, string-parsed
      expect(map['FG-2']!.itemName, ''); // no name present
      expect(map.containsKey(''), isFalse); // blank code skipped
    });

    test('empty rows -> empty map', () {
      expect(GlobalSearchService.aggregateByItem(const []), isEmpty);
    });

    test('uom/name taken from the first row that carries a value', () {
      final rows = <Map<String, dynamic>>[
        {'item_code': 'X', 'bal_qty': 1}, // no uom, no name
        {'item_code': 'X', 'bal_qty': 2, 'stock_uom': 'Kg', 'item_name': 'Widget'},
      ];
      final map = GlobalSearchService.aggregateByItem(rows);
      expect(map['X']!.balanceQty, 3);
      expect(map['X']!.uom, 'Kg');
      expect(map['X']!.itemName, 'Widget');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_stock_balance_test.dart`
Expected: FAIL — `aggregateByItem` not defined (and the old `mapStockLines`/`itemCodesFrom` tests are gone).

- [ ] **Step 3: Replace the service methods**

In `lib/app/data/services/global_search_service.dart`, delete the three methods `stockBalanceForQuery` (lines 144–167), `itemCodesFrom` (169–174), and `mapStockLines` (176–194), and put these two in their place (keep the `_num` and `_today` helpers that follow):

```dart
  /// Default-warehouse balances for [itemCodes], aggregated per item code.
  /// Returns an empty map for empty input. Errors propagate to the caller (the
  /// delegate falls back to the chevron). A group warehouse is summed via
  /// [aggregateByItem]. The returned rows are narrowed to [itemCodes] first, so
  /// an older instance that couldn't push a multi-item filter server-side still
  /// yields only the requested items.
  Future<Map<String, WarehouseStockLine>> warehouseBalances(
    List<String> itemCodes,
    String warehouse,
  ) async {
    final codes = itemCodes.where((c) => c.isNotEmpty).toList();
    if (codes.isEmpty) return const {};
    final today = _today();
    final result = await _apiProvider.getStockBalanceReport(
      fromDate: today,
      toDate: today,
      itemCodes: codes,
      warehouse: warehouse,
    );
    final allowed = codes.toSet();
    final rows = result.rows
        .where((r) => allowed.contains((r['item_code'] ?? '').toString()))
        .toList();
    return aggregateByItem(rows);
  }

  /// Aggregates Stock Balance report [rows] into one [WarehouseStockLine] per
  /// item code, SUMMING the balance (`bal_qty`, legacy `balance_qty`) across all
  /// rows for that item — so a group warehouse (which the report expands to its
  /// descendant leaf rows) yields the group total. `item_name` / `stock_uom` are
  /// taken from the first row that carries a non-empty value. Blank item codes
  /// are skipped. Pure.
  static Map<String, WarehouseStockLine> aggregateByItem(
    List<Map<String, dynamic>> rows,
  ) {
    final qty = <String, double>{};
    final name = <String, String>{};
    final uom = <String, String>{};
    final order = <String>[];
    for (final r in rows) {
      final code = (r['item_code'] ?? '').toString();
      if (code.isEmpty) continue;
      if (!qty.containsKey(code)) {
        qty[code] = 0;
        name[code] = '';
        uom[code] = '';
        order.add(code);
      }
      qty[code] = qty[code]! + _num(r, const ['bal_qty', 'balance_qty']);
      if (name[code]!.isEmpty) {
        final n = (r['item_name'] ?? '').toString();
        if (n.isNotEmpty) name[code] = n;
      }
      if (uom[code]!.isEmpty) {
        final u = (r['stock_uom'] ?? '').toString();
        if (u.isNotEmpty) uom[code] = u;
      }
    }
    return {
      for (final code in order)
        code: WarehouseStockLine(
          itemCode: code,
          itemName: name[code]!,
          balanceQty: qty[code]!,
          uom: uom[code]!,
        ),
    };
  }
```

Note: `GlobalSearchItem` is still imported/used elsewhere in this file (`search`, `_mapToModel`), so its import stays. `WarehouseStockLine` import stays (used by the new method's return type).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/global_search_stock_balance_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Confirm no analyzer regressions in the file**

Run: `flutter analyze lib/app/data/services/global_search_service.dart`
Expected: only the two pre-existing `avoid_print` infos (lines ~84 and ~277); no new issues, no "unused element" for the removed methods.

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/services/global_search_service.dart test/unit/global_search_stock_balance_test.dart
git commit -m "refactor(search): warehouseBalances + aggregateByItem (group-warehouse sum)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Delegate — inline Item-row balance (remove the footer section)

**Files:**
- Modify: `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- Delete: `test/widget/stock_balance_search_section_test.dart` (the footer renderer no longer exists)
- Test: `test/widget/global_document_search_delegate_test.dart` (add inline-balance cases)

**Interfaces:**
- Consumes: `GlobalSearchService.warehouseBalances(List<String>, String)` → `Future<Map<String, WarehouseStockLine>>` (Task 1); `WarehouseStockLine(itemCode, itemName, balanceQty, uom)`; existing `_defaultWarehouse`, `_itemReadable`, `_qtyLabel`, `_leadingIcon`, `_sectionHeader`.
- Produces: `buildResultsList(context, groups, onTap, {Map<String, WarehouseStockLine>? balances, bool balancesLoading = false})` (the `footer` param is removed); a private `_SearchResultsList` widget.

- [ ] **Step 1: Update the widget tests (add inline cases)**

First delete the obsolete footer test:

```bash
git rm test/widget/stock_balance_search_section_test.dart
```

Then append these tests to `test/widget/global_document_search_delegate_test.dart` inside `main()` (the file already imports `flutter/material.dart`, `flutter_test`, the delegate, `global_search_targets`, `global_search_item`; add the `WarehouseStockLine` import at the top):

Add import near the other imports:
```dart
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
```

Add tests:
```dart
  testWidgets('Item row shows the inline warehouse balance and no chevron',
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
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balances: const {
              'FG-1': WarehouseStockLine(
                  itemCode: 'FG-1',
                  itemName: 'Blue Strap',
                  balanceQty: 12,
                  uom: 'Nos'),
            },
          ),
        ),
      ),
    ));

    expect(find.text('12 Nos'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('Item row shows a loader while balances are loading',
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
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balancesLoading: true,
          ),
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('Item with no stock row shows 0 once balances are loaded',
      (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-9', title: 'Ghost Item', rawData: const {}),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {},
            balances: const <String, WarehouseStockLine>{}, // loaded, empty
          ),
        ),
      ),
    ));

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('non-Item row keeps the chevron even when balances are present',
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
            balances: const {
              'KA-DN-1': WarehouseStockLine(
                  itemCode: 'KA-DN-1', itemName: '', balanceQty: 5, uom: 'Nos'),
            },
          ),
        ),
      ),
    ));

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.text('5 Nos'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: FAIL — `buildResultsList` has no `balances`/`balancesLoading` params yet (compile error).

- [ ] **Step 3: Remove the footer-section code**

In `lib/app/modules/global_widgets/global_document_search_delegate.dart`:

(a) Delete `_sbScopeAllowed` (lines 58–60) and `_itemTarget` (lines 72–73).

(b) Update the `_itemReadable` doc comment (lines 62–66) so it no longer says "footer" — replace its comment block with:

```dart
  /// Item read access, mirroring [_permittedTargets] semantics: permissive when
  /// PermissionService isn't registered (widget tests) or access is unknown
  /// (null / cache not warm); only a definite `false` hides the balances. The
  /// inline Item-row balances come from a Stock Balance query, so they must
  /// honour the same Item gate the grouped results already apply.
```

(c) Delete the entire `_StockBalanceSection` class (lines 442–499) and the `buildStockBalanceSection` function (lines 504–602). KEEP the top-level `_qtyLabel` function (lines 501–502) — it is reused for the inline qty.

- [ ] **Step 4: Rewrite the results wiring + tile for inline balance**

(a) Replace the success branch of `_buildResultsArea` (currently lines 214–246, from `final groups = snapshot.data ?? const [];` through the closing of the `buildResultsList(...)` call) with:

```dart
        final groups = snapshot.data ?? const [];
        if (groups.isEmpty) {
          return _messageState(
            context,
            icon: Icons.search_off,
            message: 'No documents found matching "$query"',
          );
        }
        return _SearchResultsList(
          delegate: this,
          groups: groups,
          warehouse: _defaultWarehouse,
          itemReadable: _itemReadable,
          service: _service,
          onTap: (target, item) {
            close(context, null);
            Get.toNamed(target.route, arguments: target.argsFor(item.id));
          },
        );
```

(b) Replace `buildResultsList` (lines 302–328) with (drop `footer`, add balance params, thread to `_resultTile`):

```dart
  /// Flat scroll list: a header row per group, then its result rows. Item rows
  /// render the inline Default-Warehouse balance from [balances] (or a loader
  /// while [balancesLoading]); with neither set they fall back to the chevron.
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap, {
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading = false,
  }) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
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

(c) Replace `_resultTile` (lines 352–378) with (adds the balance params + `_trailingFor`):

```dart
  Widget _resultTile(
    BuildContext context,
    GlobalSearchTarget target,
    GlobalSearchItem item,
    void Function(GlobalSearchTarget, GlobalSearchItem) onTap, {
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading = false,
  }) {
    final scheme = context.scheme;
    return ListTile(
      leading: _leadingIcon(target, item.imageUrl),
      title: Text(
        item.title,
        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.subtitle != null
          ? Text(
              item.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.textMuted),
            )
          : null,
      trailing: _trailingFor(context, target, item, balances, balancesLoading),
      onTap: () => onTap(target, item),
    );
  }

  /// The trailing widget for a result row. Item rows show the Default-Warehouse
  /// balance (bold qty + uom), a small loader while it's fetching, or `0` once
  /// loaded with no stock row; every other case (non-Item row, or feature off)
  /// shows the chevron.
  Widget _trailingFor(
    BuildContext context,
    GlobalSearchTarget target,
    GlobalSearchItem item,
    Map<String, WarehouseStockLine>? balances,
    bool balancesLoading,
  ) {
    final scheme = context.scheme;
    final chevron = Icon(Icons.chevron_right, color: scheme.textSubtle);
    if (target.doctype != 'Item') return chevron;
    if (balancesLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (balances == null) return chevron; // feature off / error
    final line = balances[item.id];
    final label = line == null
        ? '0'
        : '${_qtyLabel(line.balanceQty)} ${line.uom}'.trim();
    return Text(
      label,
      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.text),
    );
  }
```

- [ ] **Step 5: Add the `_SearchResultsList` widget**

At the end of the file (after the `GlobalDocumentSearchDelegate` class closes, alongside `_qtyLabel`), add:

```dart
/// Renders the grouped search results immediately, then — when a Default
/// Warehouse is set and Item is readable — fetches the warehouse balances for
/// the Item group's already-known codes and rebuilds so each Item row shows its
/// balance inline. Fetch failure falls back to the chevron (search never breaks).
class _SearchResultsList extends StatefulWidget {
  const _SearchResultsList({
    required this.delegate,
    required this.groups,
    required this.warehouse,
    required this.itemReadable,
    required this.service,
    required this.onTap,
  });

  final GlobalDocumentSearchDelegate delegate;
  final List<GlobalSearchGroup> groups;
  final String? warehouse;
  final bool itemReadable;
  final GlobalSearchService service;
  final void Function(GlobalSearchTarget, GlobalSearchItem) onTap;

  @override
  State<_SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends State<_SearchResultsList> {
  Map<String, WarehouseStockLine>? _balances; // null = feature off / loading / error
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_SearchResultsList old) {
    super.didUpdateWidget(old);
    if (old.warehouse != widget.warehouse ||
        _itemCodesOf(old.groups) != _itemCodesOf(widget.groups)) {
      _fetch();
    }
  }

  bool get _active => widget.warehouse != null && widget.itemReadable;

  static String _itemCodesOf(List<GlobalSearchGroup> groups) {
    for (final g in groups) {
      if (g.target.doctype == 'Item') {
        return g.items.map((i) => i.id).join(',');
      }
    }
    return '';
  }

  Future<void> _fetch() async {
    final codesKey = _itemCodesOf(widget.groups);
    if (!_active || codesKey.isEmpty) {
      setState(() {
        _balances = null;
        _loading = false;
      });
      return;
    }
    final codes = codesKey.split(',').where((c) => c.isNotEmpty).toList();
    setState(() {
      _balances = null;
      _loading = true;
    });
    try {
      final result =
          await widget.service.warehouseBalances(codes, widget.warehouse!);
      if (!mounted) return;
      setState(() {
        _balances = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Fail closed: fall back to the chevron; never break document search.
      setState(() {
        _balances = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.delegate.buildResultsList(
      context,
      widget.groups,
      widget.onTap,
      balances: _balances,
      balancesLoading: _loading,
    );
  }
}
```

- [ ] **Step 6: Run the delegate tests to verify they pass**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: PASS — the 4 existing tests (which call `buildResultsList` with no balance args → chevron) plus the 4 new inline-balance cases.

- [ ] **Step 7: Confirm no analyzer regressions in the file**

Run: `flutter analyze lib/app/modules/global_widgets/global_document_search_delegate.dart`
Expected: No issues found (no unused `WarehouseStockLine` import — it's used by the new params; no leftover references to the deleted `_StockBalanceSection`/`buildStockBalanceSection`/`_sbScopeAllowed`/`_itemTarget`).

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/global_widgets/global_document_search_delegate.dart test/widget/global_document_search_delegate_test.dart
git commit -m "feat(search): inline Default-Warehouse balance on Item result rows

Replaces the separate Stock Balance footer with a bold trailing qty on each
Item row (loader while fetching), summed across children for a group warehouse.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count is ≤ the prior baseline (387) and no new issues reference `global_search_service.dart`, `global_document_search_delegate.dart`, or the test files beyond the known pre-existing `avoid_print` infos. Grep aid: `flutter analyze 2>&1 | grep -Ei "global_search|global_document_search|stock_balance_search|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass. The deleted `stock_balance_search_section_test.dart` is gone; the service and delegate tests are updated. If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout before treating it as a regression (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual)**

Verify on device:
- Set a Default Warehouse (Session Defaults) that is a **leaf** warehouse → Dashboard search, type ≥3 chars matching items → each Item row shows a bold trailing qty (brief loader first); tapping the row opens the Item.
- Set a Default Warehouse that is a **group** warehouse → the same Item shows the **summed** qty across its child warehouses.
- An item with no stock in the warehouse shows `0`.
- Clear the Default Warehouse → Item rows show the chevron again (no balance).

---

## Notes / deviations from the spec

- Removed the client-side "narrow to matched codes" only where it was redundant; kept it in `warehouseBalances` to bound the map on older ERPNext instances that can't push a multi-item filter.
- On fetch error the Item rows fall back to the **chevron** (not `0`), so an error never masquerades as "zero stock". `0` is shown only after a *successful* load where the item has no row in that warehouse.
- `itemCodesFrom`/`mapStockLines`/`stockBalanceForQuery` are removed; the delegate derives item codes directly from the Item search group (no second Item search — also removes the duplicate-search inefficiency flagged in the prior review).

## Versioning

Same unreleased feature → **MINOR** bump at release time per `docs/versioning_conventions.md`. Not part of this plan.
