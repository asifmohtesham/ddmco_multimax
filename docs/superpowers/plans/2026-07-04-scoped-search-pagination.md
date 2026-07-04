# Scoped Search Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the single-doctype scoped search view, page results in on scroll (20 at a time) until the end, with an "End of results" marker; the "All" fan-out stays a capped preview.

**Architecture:** `GlobalSearchService.search` gains `limitStart`/`pageSize`. A new `_ScopedResults` StatefulWidget in the search delegate owns a `ScrollController`, loads pages via an injected fetcher (debounced on query change, load-more at 90% depth), reuses the delegate's `_sectionHeader`/`_resultTile` and the shared `ListEndFooter`, and (for Item scope) merges per-page Default-Warehouse balances. `_buildResultsArea` routes `scope != null` to `_ScopedResults`, `scope == null` to the existing grouped preview.

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), `flutter_test`.

## Global Constraints

- Page size **20**; auto-load at **90%** scroll depth (mirrors `ListScrollMixin`); no separate "Load More" button.
- Query changes in the scoped view are **debounced 300ms** before refetching (the delegate rebuilds per keystroke — direct fetch would fire per keystroke).
- Reuse the shared **`ListEndFooter`** (spinner while `hasMore`, else "End of results"); pass the `MediaQuery` bottom inset as its `bottomPadding`.
- The **"All" fan-out is unchanged** (grouped capped preview via `_SearchResultsList`); `searchAll` fetches `pageSize: kGroupCap`.
- Item-scope rows keep the inline Default-Warehouse balance (fetched per page); balances only apply when `scope.doctype == 'Item'`, a Default Warehouse is set, and Item is readable.
- Never hardcode surface/ink colours — use `context.scheme.*`. No crash on fetch error (first page → error state; later page → stop; balance error → caught).
- No new analyzer warnings/errors in touched files.

---

### Task 1: Service pagination params

**Files:**
- Modify: `lib/app/data/services/global_search_service.dart`

**Interfaces:**
- Produces: `Future<List<GlobalSearchItem>> GlobalSearchService.search(String doctype, String query, {int limitStart = 0, int pageSize = 20})`.

- [ ] **Step 1: Add the params to `search`**

In `lib/app/data/services/global_search_service.dart`, change the `search` signature (line 24) from:

```dart
  Future<List<GlobalSearchItem>> search(String doctype, String query) async {
```
to:
```dart
  Future<List<GlobalSearchItem>> search(
    String doctype,
    String query, {
    int limitStart = 0,
    int pageSize = 20,
  }) async {
```

In the two `getDocumentList` calls inside `search` (the `tokens.length <= 1` branch and the `else` branch), change each `limit: 20,` line to:

```dart
              limit: pageSize,
              limitStart: limitStart,
```

- [ ] **Step 2: Make the fan-out request only the group cap**

In the same file, `searchAll` (around line 176) — change the searcher from:

```dart
      searcher: (doctype) => search(doctype, query),
```
to:
```dart
      searcher: (doctype) => search(doctype, query, pageSize: kGroupCap),
```

- [ ] **Step 3: Verify existing callers + analyzer**

The new params are optional with defaults, so existing callers (`searchAll`, the delegate's `_search`) are unaffected.

Run: `flutter test test/unit/global_search_tokens_test.dart`
Expected: PASS (unchanged).

Run: `flutter analyze lib/app/data/services/global_search_service.dart`
Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/services/global_search_service.dart
git commit -m "feat(search): paginate search() with limitStart/pageSize; fan-out fetches group cap

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `_ScopedResults` paginated list + scoped wiring

**Files:**
- Modify: `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- Test: `test/widget/global_document_search_delegate_test.dart` (add `_ScopedResults` cases)

**Interfaces:**
- Consumes: `GlobalSearchService.search(doctype, query, {limitStart, pageSize})` (Task 1); `GlobalSearchService.warehouseBalances(codes, warehouse)`; the delegate's `_sectionHeader` / `_resultTile` / `_messageState`; `ListEndFooter`; `WarehouseStockLine`.
- Produces: `_ScopedResults` (private StatefulWidget) with constructor `_ScopedResults({Key? key, required GlobalDocumentSearchDelegate delegate, required GlobalSearchTarget target, required String query, required Future<List<GlobalSearchItem>> Function(int limitStart, int pageSize) fetchPage, Future<Map<String, WarehouseStockLine>> Function(List<String> codes)? fetchBalances, required void Function(GlobalSearchItem item) onTap})`.

- [ ] **Step 1: Write the failing widget test**

Append to `test/widget/global_document_search_delegate_test.dart` inside `main()` (the file already imports material, flutter_test, the delegate, `global_search_targets`, `global_search_item`, and `warehouse_stock_line`; add the theme imports below if not present):

```dart
  // ── _ScopedResults pagination ──────────────────────────────────────────────
  // Uses the public test entrypoint the delegate exposes for the scoped list.
  testWidgets('scoped results load page 1, then load more on scroll to the end',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    final calls = <List<int>>[];
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async {
      calls.add([start, size]);
      final n = start == 0 ? 20 : 5; // page 2 is short → end of list
      final tag = start == 0 ? 'A' : 'B';
      return List.generate(
        n,
        (i) => GlobalSearchItem(id: '$tag$i', title: 'Item $tag$i', rawData: const {}),
      );
    }

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'belts reversible',
          fetchPage: fetchPage,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(calls, [
      [0, 20]
    ]);
    expect(find.text('Item A0'), findsOneWidget);

    // Scroll to the bottom → triggers load-more.
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(calls.any((c) => c[0] == 20), isTrue); // page 2 requested at offset 20
    expect(find.text('End of results'), findsOneWidget);
  });

  testWidgets('scoped results: a short first page shows End of results',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async =>
        List.generate(
            3, (i) => GlobalSearchItem(id: 'X$i', title: 'X$i', rawData: const {}));

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'belts',
          fetchPage: fetchPage,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('X0'), findsOneWidget);
    expect(find.text('End of results'), findsOneWidget);
  });

  testWidgets('scoped results: empty first page shows the no-documents message',
      (tester) async {
    final theme = buildAppTheme(AppScheme.light, Brightness.light);
    Future<List<GlobalSearchItem>> fetchPage(int start, int size) async => [];

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: Scaffold(
        body: scopedResultsForTest(
          target: _target('Item'),
          query: 'zzz',
          fetchPage: fetchPage,
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No documents found'), findsOneWidget);
  });
```

Add these imports at the top of the test file if missing:

```dart
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: FAIL — `scopedResultsForTest` not defined.

- [ ] **Step 3: Add imports to the delegate**

In `lib/app/modules/global_widgets/global_document_search_delegate.dart`, add (near the other imports):

```dart
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
```

(`dart:async` and `warehouse_stock_line.dart` are already imported.)

- [ ] **Step 4: Route the scoped view to `_ScopedResults`**

Replace the body of `_buildResultsArea` (currently lines 179–228) so a selected scope paginates and "All" is unchanged:

```dart
  Widget _buildResultsArea(BuildContext context, GlobalSearchTarget? scope) {
    if (query.trim().length < _kMinChars) {
      return _messageState(
        context,
        icon: Icons.search,
        message: 'Type at least $_kMinChars characters',
      );
    }

    // Scoped to a single doctype → paginated infinite-scroll list.
    if (scope != null) {
      final wh = _defaultWarehouse;
      final balancesApply =
          scope.doctype == 'Item' && wh != null && _itemReadable;
      return _ScopedResults(
        key: ValueKey(scope.doctype),
        delegate: this,
        target: scope,
        query: query.trim(),
        fetchPage: (limitStart, pageSize) => _service.search(
          scope.doctype,
          query.trim(),
          limitStart: limitStart,
          pageSize: pageSize,
        ),
        fetchBalances: balancesApply
            ? (codes) => _service.warehouseBalances(codes, wh)
            : null,
        onTap: (item) {
          close(context, null);
          Get.toNamed(scope.route, arguments: scope.argsFor(item.id));
        },
      );
    }

    // "All" → grouped capped preview (unchanged).
    return FutureBuilder<List<GlobalSearchGroup>>(
      future: _search(query.trim(), scope),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return _messageState(
            context,
            icon: Icons.error_outline,
            message: 'Search failed. Please try again.',
            isError: true,
          );
        }
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
      },
    );
  }
```

- [ ] **Step 5: Add the test entrypoint + `_ScopedResults` widget**

At the end of the file (after `buildStockBalanceSection` / `_qtyLabel` and the other private widgets), add a `@visibleForTesting` factory so tests can build the widget without a live service, then the widget itself:

```dart
/// Test-only builder for [_ScopedResults] (its constructor is library-private).
@visibleForTesting
Widget scopedResultsForTest({
  required GlobalSearchTarget target,
  required String query,
  required Future<List<GlobalSearchItem>> Function(int limitStart, int pageSize)
      fetchPage,
  Future<Map<String, WarehouseStockLine>> Function(List<String> codes)?
      fetchBalances,
  required void Function(GlobalSearchItem item) onTap,
}) =>
    _ScopedResults(
      delegate: GlobalDocumentSearchDelegate(),
      target: target,
      query: query,
      fetchPage: fetchPage,
      fetchBalances: fetchBalances,
      onTap: onTap,
    );

/// One doctype's results as a paginated, infinite-scroll list. Loads page 1 on
/// mount, the next page at 90% scroll depth (page size 20), and stops when a
/// page comes back short → [ListEndFooter] shows "End of results". Item-scope
/// rows carry their Default-Warehouse balance (fetched per page).
class _ScopedResults extends StatefulWidget {
  const _ScopedResults({
    super.key,
    required this.delegate,
    required this.target,
    required this.query,
    required this.fetchPage,
    required this.onTap,
    this.fetchBalances,
  });

  final GlobalDocumentSearchDelegate delegate;
  final GlobalSearchTarget target;
  final String query;
  final Future<List<GlobalSearchItem>> Function(int limitStart, int pageSize)
      fetchPage;
  final Future<Map<String, WarehouseStockLine>> Function(List<String> codes)?
      fetchBalances;
  final void Function(GlobalSearchItem item) onTap;

  @override
  State<_ScopedResults> createState() => _ScopedResultsState();
}

class _ScopedResultsState extends State<_ScopedResults> {
  static const int _kPageSize = 20;

  final _scrollController = ScrollController();
  Timer? _debounce;
  int _fetchId = 0;

  List<GlobalSearchItem> _items = [];
  Map<String, WarehouseStockLine>? _balances;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _initialLoading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetch(reset: true);
  }

  @override
  void didUpdateWidget(_ScopedResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query ||
        old.target.doctype != widget.target.doctype) {
      // Debounce so per-keystroke rebuilds don't each fire a network search.
      _debounce?.cancel();
      _debounce =
          Timer(const Duration(milliseconds: 300), () => _fetch(reset: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max > 0 &&
        _scrollController.offset >= max * 0.9 &&
        _hasMore &&
        !_isLoadingMore) {
      _fetch(reset: false);
    }
  }

  Future<void> _fetch({required bool reset}) async {
    if (!reset && (_isLoadingMore || !_hasMore)) return;
    final id = ++_fetchId;
    setState(() {
      _isLoadingMore = true;
      if (reset) _error = false;
    });
    final start = reset ? 0 : _items.length;
    try {
      final page = await widget.fetchPage(start, _kPageSize);
      var bal = const <String, WarehouseStockLine>{};
      if (widget.fetchBalances != null && page.isNotEmpty) {
        final codes =
            page.map((i) => i.id).where((c) => c.isNotEmpty).toList();
        bal = await widget.fetchBalances!(codes);
      }
      if (!mounted || id != _fetchId) return;
      setState(() {
        _items = [...(reset ? const <GlobalSearchItem>[] : _items), ...page];
        if (widget.fetchBalances != null) {
          _balances = reset ? {...bal} : {...?_balances, ...bal};
        }
        _hasMore = page.length == _kPageSize;
        _isLoadingMore = false;
        _initialLoading = false;
      });
    } catch (_) {
      if (!mounted || id != _fetchId) return;
      setState(() {
        _isLoadingMore = false;
        _initialLoading = false;
        if (reset) {
          _error = true;
        } else {
          _hasMore = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error && _items.isEmpty) {
      return widget.delegate._messageState(
        context,
        icon: Icons.error_outline,
        message: 'Search failed. Please try again.',
        isError: true,
      );
    }
    if (_items.isEmpty) {
      return widget.delegate._messageState(
        context,
        icon: Icons.search_off,
        message: 'No documents found matching "${widget.query}"',
      );
    }
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      color: scheme.bg,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _items.length + 2, // header + rows + footer
        itemBuilder: (context, i) {
          if (i == 0) {
            return widget.delegate._sectionHeader(context, widget.target);
          }
          if (i == _items.length + 1) {
            return ListEndFooter(hasMore: _hasMore, bottomPadding: bottom);
          }
          final item = _items[i - 1];
          return widget.delegate._resultTile(
            context,
            widget.target,
            item,
            (_, it) => widget.onTap(it),
            balances: _balances,
            balancesLoading: false,
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: PASS — the 3 new `_ScopedResults` cases plus all pre-existing delegate tests (the "All"/`buildResultsList` tests are untouched).

- [ ] **Step 7: Confirm no analyzer regressions**

Run: `flutter analyze lib/app/modules/global_widgets/global_document_search_delegate.dart`
Expected: No issues found. (`ListEndFooter` import is used; `_ScopedResults` and `scopedResultsForTest` are referenced.)

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/global_widgets/global_document_search_delegate.dart test/widget/global_document_search_delegate_test.dart
git commit -m "feat(search): paginate the scoped single-doctype view with infinite scroll

Tapping a scope chip now loads results 20 at a time, auto-loading on scroll to
'End of results'; Item rows keep their inline Default-Warehouse balance. The
'All' fan-out stays a capped preview.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (full project)**

Run: `flutter analyze`
Expected: issue count ≤ the 386 baseline; no new issues in `global_search_service.dart` or `global_document_search_delegate.dart`. Grep aid: `flutter analyze 2>&1 | grep -Ei "global_search_service|global_document_search|issues found"`.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass (existing + the 3 new scoped-pagination cases). If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual, operator account)**

- Search `belts reversible`, tap the **Items** scope chip → the list loads 20, and scrolling down auto-loads more until **"End of results"** (all ~51 reachable); each Item row shows its Default-Warehouse balance.
- Editing the query in the scoped view refetches from the top (debounced), not per keystroke.
- The **"All"** view still shows the capped grouped preview (unchanged).
- A scope with no matches shows "No documents found"; a transient failure shows the error state without crashing.

---

## Notes / deviations from the spec

- Query-change refetch is debounced 300ms inside `_ScopedResults` (the delegate re-invokes `buildResults`/`buildSuggestions` per keystroke); load-more is not debounced.
- `_ScopedResults` reuses the delegate's private `_sectionHeader`/`_resultTile`/`_messageState` (same library) and is built in tests via the `@visibleForTesting scopedResultsForTest` factory (its constructor is library-private).
- Item-scope balances are committed together with each page's items (no premature `0`).

## Versioning

Search enhancement → **PATCH** at release time, bundled with Part 1.
