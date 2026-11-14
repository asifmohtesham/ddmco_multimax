# Scoped search pagination — Design

**Date:** 2026-07-04
**Status:** Proposed
**Part 2 of 2** — builds on the server-side AND fix (Part 1, commit e10f9ff9).

## Problem

With the AND fix, "belts reversible" now matches all 51 items, but the search UI
caps every doctype group at `kGroupCap` (8) with no way to see the rest. The
scoped single-doctype view (tap the "Items" chip) shows 8 and stops.

## Goal

In the **scoped** view (a single-doctype chip selected), page results in on scroll
until the end — page size 20, auto-load near the bottom, "End of results" marker.
The **"All"** fan-out is unchanged (capped grouped preview). Item rows keep their
inline Default-Warehouse balance.

## Components

### `GlobalSearchService.search` (`lib/app/data/services/global_search_service.dart`)

- Signature gains pagination: `search(String doctype, String query, {int limitStart = 0, int pageSize = 20})`.
- Both the 1-token and ≥2-token branches pass `limit: pageSize` and
  `limitStart: limitStart` to `getDocumentList` (which already accepts `limitStart`).
- `searchAll`'s fan-out searcher passes `pageSize: kGroupCap` so the "All" preview
  doesn't over-fetch; `runSearchAll` still `.take(cap)` (now a no-op). Behaviour of
  the grouped preview is otherwise unchanged.

### `_ScopedResults` — new `StatefulWidget` in `global_document_search_delegate.dart`

Renders one doctype's results as a paginated, infinite-scroll list.

- **Inputs (all injected → testable):**
  - `delegate` (to reuse `_sectionHeader` / `_resultTile` — same library, so private
    members are reachable),
  - `target` (the scoped `GlobalSearchTarget`), `query`,
  - `fetchPage`: `Future<List<GlobalSearchItem>> Function(int limitStart, int pageSize)`,
  - `fetchBalances`: `Future<Map<String, WarehouseStockLine>> Function(List<String> codes)?`
    (null when balances don't apply — non-Item scope, no Default Warehouse, or no
    Item read access),
  - `onTap`.
- **State:** `_items`, `_balances` (`Map<String,WarehouseStockLine>?`, null when
  `fetchBalances == null`), `_hasMore`, `_isLoadingMore`, `_initialLoading`,
  `_error`, and a monotonic `_fetchId` (stale-page guard, same pattern as the
  inline-balance widget).
- **Scroll trigger:** a `ScrollController`; on scroll, if depth ≥ 90% of
  `maxScrollExtent`, `_hasMore`, and not `_isLoadingMore` → load the next page
  (mirrors `ListScrollMixin`'s 90% rule; the delegate isn't a GetxController so the
  mixin can't be used directly).
- **Fetch (`_fetch({required bool reset})`):** capture `id = ++_fetchId`; set
  loading; `page = await fetchPage(reset ? 0 : _items.length, 20)`; if
  `fetchBalances != null && page.isNotEmpty`, `bal = await fetchBalances(page item
  codes)`; bail if `!mounted || id != _fetchId`; then append (`reset` replaces):
  `_items = [...(reset ? [] : _items), ...page]`, merge `_balances`,
  `_hasMore = page.length == 20`. Items + their balances are committed together so a
  scrolled-in Item row shows its qty immediately (no premature `0`). Errors: first
  page → `_error = true`; later page → `_hasMore = false` (stop). Never throws out.
- **Lifecycle:** `initState` → `_fetch(reset: true)`. `didUpdateWidget` → if `query`
  or `target.doctype` changed, `_fetch(reset: true)`.
- **Render:**
  - `_initialLoading` → centred spinner.
  - `_error` → the delegate's error message state.
  - loaded + empty → the delegate's "No documents found" message state.
  - else → `ListView(controller: _scrollController)` with: `_sectionHeader(target)`,
    one `_resultTile(target, item, onTap, balances: _balances, balancesLoading: false)`
    per item, then `ListEndFooter(hasMore: _hasMore, bottomPadding: MediaQuery
    bottom inset)` (shared widget: spinner while `hasMore`, else "End of results").

### `_buildResultsArea` wiring (`global_document_search_delegate.dart`)

- `query.trim().length < _kMinChars` → message (unchanged).
- **`scope != null`** (a chip is selected): return `_ScopedResults(...)` with:
  - `fetchPage: (start, size) => _service.search(scope.doctype, query.trim(), limitStart: start, pageSize: size)`,
  - `fetchBalances:` non-null only when `scope.doctype == 'Item' && _defaultWarehouse != null && _itemReadable`, wired to `(codes) => _service.warehouseBalances(codes, _defaultWarehouse!)`,
  - `onTap:` close + `Get.toNamed(scope.route, arguments: scope.argsFor(item.id))`.
- **`scope == null`** ("All"): unchanged — the existing `FutureBuilder` over
  `_search(query, null)` → grouped `_SearchResultsList` (capped preview).

## Data flow (scoped Items)

```
tap [Items] → _ScopedResults(target=Item, query='belts reversible')
  initState → fetchPage(0,20) → 20 items → fetchBalances(codes) → commit
  scroll 90% → fetchPage(20,20) → 20 → commit → … → fetchPage(40,20) → 11 (<20)
       → _hasMore=false → ListEndFooter shows "End of results"
```

## Error handling

- First-page fetch error → error message state (search doesn't crash).
- Later-page error → stop paginating (`_hasMore=false`), keep what loaded.
- Balance fetch failure inside a page → caught; that page's rows show `0` (or the
  chevron) — never blocks the item list.
- Stale pages (query changed mid-fetch) → dropped via the `_fetchId` guard.

## Testing

- **Widget** — `_ScopedResults` with an injected fake `fetchPage` (null
  `fetchBalances`):
  - first page of 20 renders 20 rows + a `ListEndFooter` in its loading (hasMore)
    state; scrolling to the bottom (`tester.drag` / `scrollUntilVisible`) loads a
    second short page (e.g. 5) → 25 rows and `ListEndFooter` shows "End of results";
  - an empty first page → the "No documents found" message;
  - a first page shorter than 20 → no more loads, "End of results" immediately.
- The networked wiring (real `search`/`warehouseBalances`, the balance merge on
  Item scope) is verified on-device.

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/services/global_search_service.dart` (`search` pagination params; fan-out `pageSize: kGroupCap`) |
| Modify | `lib/app/modules/global_widgets/global_document_search_delegate.dart` (`_ScopedResults` + scoped wiring) |
| Modify | `test/widget/global_document_search_delegate_test.dart` (add `_ScopedResults` pagination cases) |

## Out of scope / YAGNI

- Pagination in the "All" fan-out (per-group load-more) — decided against (scoped
  view only).
- A separate "Load More" button (auto infinite-scroll only).
- A result total/count in the end marker (Frappe list call doesn't return it here
  without an extra count query).

## Versioning

Search enhancement → **PATCH** at release time, bundled with Part 1.
