# Stock Ageing - Custom Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Stock → Reports → Stock Ageing screen that shows the ERP's `Stock Ageing - Custom` report with the same default-filter behaviour as the Desk.

**Architecture:** A GetX binding/controller/screen under `lib/app/modules/stock/reports/stock_ageing/`, following `stock_balance`. All decisions (filter payload, default detection, bucket parsing, search/sort, totals, staleness) are pure static functions so they are unit-tested without widgets. The default-filter result is cached as one JSON file.

**Tech Stack:** Flutter, GetX, Dio (`ApiProvider`), `path_provider`, `intl`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-14-stock-ageing-custom-report-design.md`

## Global Constraints

- Report name on the wire is exactly `Stock Ageing - Custom`.
- Default run: `filters={}`, `ignore_prepared_report=true`, **no** `are_default_filters` key.
- User-filter run: full filter map, `are_default_filters=false`; `company`, `to_date`, `range` always present.
- Bucket labels come from `message.columns`; never hard-code 90/180/360/720.
- Must work on ERPNext v15 and v16 (no version-specific fields are used).
- British English in comments, copy and commit messages; dates shown as DD/MM/YYYY.
- Never write the real ERP hostname in code or docs; use `erp.domain.com`.

## Review Focus

1. Server has no saved filters (`custom_filters` null) → the app must not loop or crash; it shows the server's error and leaves the filter sheet usable.
2. Result rows that are not maps (a total row as a list) → skipped, not thrown on.
3. Numeric cells arriving as `int`, `double`, `null` or string → treated as numbers, `null` as 0.
4. Corrupt or half-written cache file → treated as no cache.
5. Refresh fails while cached rows are on screen → rows stay, an error snackbar shows.

Tests for 2–4 are in Tasks 2 and 3; 1 and 5 are controller branches in Task 4 (checked on device).

---

### Task 1: API call and filter contract

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (after the Stock Balance report methods)
- Test: `test/unit/stock_ageing_filters_test.dart`

**Interfaces — Produces:**
- `static Map<String, dynamic> ApiProvider.buildStockAgeingFilters({required String company, required String toDate, required String range, String? warehouseType, String? warehouse, String? itemCode, String? brand, bool showWarehouseWiseStock = false})` — empty/blank optionals omitted; toggle encoded as `1` and omitted when off.
- `static Map<String, dynamic> ApiProvider.stockAgeingQuery({Map<String, dynamic>? filters})` — the query parameters without the cache-buster `_`. `filters == null` → `{'report_name': 'Stock Ageing - Custom', 'filters': '{}', 'ignore_prepared_report': 'true'}`; otherwise the JSON-encoded filters plus `'are_default_filters': 'false'`.
- `Future<Response> runStockAgeingCustom({Map<String, dynamic>? filters})` — GET `frappe.desk.query_report.run` with `stockAgeingQuery` + `_`.

- [ ] **Step 1:** Write tests: bare build → exactly `{company, to_date, range}`; all optionals set → all eight keys with `show_warehouse_wise_stock: 1`; blank strings omitted; `stockAgeingQuery()` has no `are_default_filters` key and `filters == '{}'`; `stockAgeingQuery(filters: {...})` has `are_default_filters == 'false'`.
- [ ] **Step 2:** `flutter test test/unit/stock_ageing_filters_test.dart` → fails (undefined).
- [ ] **Step 3:** Implement the three members.
- [ ] **Step 4:** Re-run → passes.
- [ ] **Step 5:** Commit `feat(stock-ageing): add report API call and filter contract`.

### Task 2: Pure report logic

**Files:**
- Create: `lib/app/modules/stock/reports/stock_ageing/stock_ageing_logic.dart`
- Test: `test/unit/stock_ageing_logic_test.dart`

**Interfaces — Produces:**
- `class AgeBucket { final String qtyKey; final String valueKey; final String label; }`
- `class StockAgeingTotals { final double qty; final double value; final List<double> bucketQty; }`
- `abstract final class StockAgeingLogic` with statics:
  - `double num_(dynamic v)` — int/double/numeric string → double; anything else 0.
  - `List<AgeBucket> parseBuckets(List<dynamic> columns)` — columns whose `fieldname` matches `^range\d+$`, in order; label = column label with a leading `Age (` and trailing `)` stripped (`Age (0 - 90)` → `0 - 90`); `valueKey = '${fieldname}value'`.
  - `List<Map<String, dynamic>> parseRows(dynamic result)` — only `Map` entries, copied to `Map<String, dynamic>`.
  - `List<Map<String, dynamic>> filterAndSort(List<Map<String, dynamic>> rows, {String search = '', String sort = 'age', List<AgeBucket> buckets = const []})` — case-insensitive contains over `item_code`, `item_name`, `variant_of`, `warehouse`; sort keys `age` (`average_age` desc), `qty` (`qty` desc), `old` (last bucket qty desc), `code` (`item_code` asc); ties by `item_code` asc; returns a new list.
  - `StockAgeingTotals totals(List<Map<String, dynamic>> rows, List<AgeBucket> buckets)` — value = sum of every bucket value.
  - `bool sameFilters(Map<String, dynamic> a, Map<String, dynamic> b)` — equal after dropping null/blank/`0` entries and comparing values as trimmed strings.
  - `bool shouldAutoRefresh({required DateTime fetchedAt, required DateTime now})` — **left as `TODO(human)`**; staleness policy for the cached default run.

- [ ] **Step 1:** Write tests with the real column shapes (`range1`…`range5`, labels `Age (0 - 90)` … `Age (721 - Above)`): bucket count 5, first label `0 - 90`, last `721 - Above`, value key `range5value`; `parseRows` drops a list row; `num_` over `3`, `2.5`, `'4'`, `null`, `'x'` → 3, 2.5, 4, 0, 0; search `wal` matches item name `WALLETS COW`; each sort key's first row; totals over two rows; `sameFilters({'a': 1, 'b': ''}, {'a': '1'})` true and `{'a': 1}` vs `{'a': 2}` false.
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement everything except `shouldAutoRefresh` (stub returns `false` with the TODO).
- [ ] **Step 4:** Run → passes.
- [ ] **Step 5:** Commit `feat(stock-ageing): add pure report logic`.

### Task 3: Device cache

**Files:**
- Create: `lib/app/modules/stock/reports/stock_ageing/stock_ageing_cache.dart`
- Test: `test/unit/stock_ageing_cache_test.dart`

**Interfaces — Produces:**
- `class StockAgeingSnapshot { final DateTime fetchedAt; final List<dynamic> columns; final List<Map<String, dynamic>> rows; final Map<String, dynamic> defaults; }`
- `class StockAgeingCache { StockAgeingCache({Future<Directory> Function()? directory}); Future<StockAgeingSnapshot?> read(); Future<void> write(StockAgeingSnapshot s); Future<void> clear(); }` — file `stock_ageing_custom.json` in `getApplicationSupportDirectory()` by default; `read` returns null on a missing or undecodable file; `write` goes via a temp file then rename.

- [ ] **Step 1:** Tests using `Directory.systemTemp.createTemp`: round trip preserves rows, defaults and `fetchedAt`; missing file → null; file containing `{oops` → null; `clear` then `read` → null.
- [ ] **Step 2:** Run → fails. **Step 3:** Implement. **Step 4:** Run → passes.
- [ ] **Step 5:** Commit `feat(stock-ageing): cache the default report run on device`.

### Task 4: Controller and binding

**Files:**
- Create: `lib/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart`, `stock_ageing_binding.dart`

**Interfaces — Consumes:** Tasks 1–3. **Produces** (used by the screen):
- Observables: `isLoading`, `isRefreshing`, `rows` (`RxList<Map<String, dynamic>>`), `buckets` (`RxList<AgeBucket>`), `searchQuery` (`RxString`), `sort` (`RxString`, default `'age'`), `activeFilters` (`RxMap<String, String>`), `fetchedAt` (`Rxn<DateTime>`), `asOn` (`RxString`, yyyy-MM-dd), `errorMessage` (`RxnString`).
- `filterControllers` keys: `to_date`, `warehouse_type`, `warehouse`, `item_code`, `brand`, `range`, `show_warehouse_wise_stock`; `filterFields`, `filterToggles`.
- Getters `visibleRows`, `totals`; methods `runReport()`, `refreshReport()`, `clearFilters()`, `clearFilter(String key)`, `setSort(String)`, `onSearchChanged(String)`.

Behaviour: `onInit` reads the cache → shows it and seeds the filter controllers from its `defaults`; fetches when there is no cache or `shouldAutoRefresh` is true. `runReport` builds the filter map; `sameFilters(current, defaults)` or unknown defaults → default call, and the response's `custom_filters` become the new defaults, controllers are re-seeded and the snapshot is cached; otherwise a user-filter call that is never cached. `company` = `defaults['company']` else `StorageService.getCompany()`. Blank `to_date`/`range` on a user-filter run → warning snackbar, no call. Errors: keep existing rows, `GlobalSnackbar.error`; with no rows set `errorMessage`. `activeFilters` lists only keys whose value differs from the defaults. Dispose the text controllers in `onClose`.

- [ ] **Step 1:** Implement controller and binding.
- [ ] **Step 2:** `flutter analyze lib/app/modules/stock/reports/stock_ageing` → no issues.
- [ ] **Step 3:** Commit `feat(stock-ageing): add report controller`.

### Task 5: Screen, route and navigation

**Files:**
- Create: `lib/app/modules/stock/reports/stock_ageing/stock_ageing_screen.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (`STOCK_AGEING = '/stock/reports/stock-ageing'`), `lib/app/data/routes/app_pages.dart` (GetPage, `rightToLeftWithFade`), `lib/app/modules/global_widgets/workspace_menu.dart` (`NavLink('Report', 'Stock Ageing', 'Stock Ageing', Icons.hourglass_bottom_rounded, AppRoutes.STOCK_AGEING, _rep('Item'), 'Stock', 'Reports')` after Stock Balance)

Screen: `AppShellScaffold` + `RefreshIndicator(onRefresh: controller.refreshReport)` + `DocTypeListHeader(title: 'Stock Ageing', searchQuery, onSearchChanged, activeFilters, onFilterTap → showReportFilterSheet(... toggles: controller.filterToggles), filterChipsBuilder, onClearAllFilters)`. Below it: a summary card (`As on DD/MM/YYYY · fetched HH:mm`, total qty, total value, stacked bucket bar with legend), a row of sort `ChoiceChip`s (Oldest, Quantity, Oldest bucket, Item code), then a lazy `SliverList` of tiles (item code in the theme's mono style, name, warehouse, qty + UOM, `avg N days`, bucket bar). Tapping a tile opens a modal sheet listing each bucket's qty and value plus earliest/latest, item group, brand, variant-of, country of origin. Bucket colours: a five-step ramp from `cs.primary` to `cs.error` by index. Loading with no rows → centred progress; no rows → empty state with the error text or "No stock found for these filters".

- [ ] **Step 1:** Implement screen, route, nav link.
- [ ] **Step 2:** `flutter analyze` → no new issues against the baseline; `flutter test test/unit/stock_ageing_*` → all pass.
- [ ] **Step 3:** Commit `feat(stock-ageing): add Stock Ageing report screen`.
