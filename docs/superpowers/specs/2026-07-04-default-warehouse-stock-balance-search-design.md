# Default Warehouse + Dashboard-search Stock Balance — Design

**Date:** 2026-07-04
**Status:** Proposed

## Summary

Two linked changes:

1. **Session Defaults → Default Warehouse.** Add an optional "Default Warehouse"
   picker to the Session Defaults screen (Menu → Account & settings → Session
   Defaults), in the **SESSION** group directly under Company. Persisted per
   device via `StorageService`.

2. **Dashboard search → Stock Balance section.** In the Dashboard global search
   overlay (`GlobalDocumentSearchDelegate`), **after** the normal document
   results are displayed, fetch and show a **"Stock Balance · &lt;Warehouse&gt;"**
   section for the items **matching the query**, scoped to the Default Warehouse,
   with its own loading feedback. Only shown when a Default Warehouse is set.

The two are linked: the setting from (1) is the warehouse used by (2).

## Task 1 — Default Warehouse setting

### StorageService (`lib/app/data/services/storage_service.dart`)

- New key: `_defaultWarehouseKey = 'session_default_warehouse'`.
- `Future<void> saveDefaultWarehouse(String? warehouse)` — writes the value, or
  **removes** the key when `warehouse` is null/empty (so "unset" is a real state,
  distinct from company's always-defaulted `getCompany()`).
- `String? getDefaultWarehouse()` — returns the stored value, or `null` when unset.

Default Warehouse is **optional** (company stays required). Unset = the search
Stock Balance section simply doesn't appear.

### SessionDefaultsController (`.../session_defaults/session_defaults_controller.dart`)

- New observables: `warehouses = <String>[].obs`, `selectedWarehouse = RxnString()`,
  `isLoadingWarehouses = false.obs`.
- Lazy `WarehouseProvider` (same pattern as the lazy `ApiProvider` field), so
  constructing the controller never forces DI to be warm (keeps `persist()`
  unit-testable).
- `load()`: set `selectedWarehouse.value = _storage.getDefaultWarehouse();` and
  fetch the warehouse list via `WarehouseProvider.getWarehouses()` (small,
  non-group, non-disabled list). A fetch failure is **non-fatal** — warn and
  leave the picker empty (warehouse is optional).
- `persist()`: after the existing saves, `await _storage.saveDefaultWarehouse(
  selectedWarehouse.value)`. Passing `null` clears it. Does **not** affect the
  "company required" gate.
- `clearWarehouse()` → `selectedWarehouse.value = null`.

Warehouse source is **all** non-group, non-disabled warehouses (not
company-filtered). The app is effectively single-company (`Multimax` default);
company-scoping is a possible future refinement, deliberately out of scope here.

### SessionDefaultsScreen (`.../session_defaults/session_defaults_screen.dart`)

- Add `_warehouseField(context)` as a second child of the **SESSION**
  `SettingsGroup`, under the existing `_companyField`.
- Mirrors the Company field's styling exactly (label + `InkWell` tile + subtle
  fill + helper line), differing only in:
  - label `Default Warehouse`,
  - leading icon `Icons.warehouse_outlined`,
  - placeholder `Select warehouse (optional)`,
  - helper `Used for the Dashboard search Stock Balance shortcut.`,
  - a trailing **clear (×)** affordance shown only when a warehouse is set
    (calls `controller.clearWarehouse()`), since it's optional.
- Tapping the tile opens the existing **`WarehousePickerSheet`** (searchable),
  fed `controller.warehouses` / `isLoadingWarehouses`, with
  `onSelected: (wh) => controller.selectedWarehouse.value = wh`.

All colours via `context.scheme` (verified on the dark surface in the provided
screenshot — same treatment as Company).

## Task 2 — Stock Balance section in Dashboard search

### GlobalSearchService (`lib/app/data/services/global_search_service.dart`)

- New model `WarehouseStockLine` (small value type: `itemCode`, `itemName`,
  `balanceQty`, `uom`, `imageUrl`) — its own file
  `lib/app/data/models/warehouse_stock_line.dart`.
- `Future<List<WarehouseStockLine>> stockBalanceForQuery(String query, String warehouse)`:
  1. `items = await search('Item', query)` → take `kGroupCap` → item codes.
  2. If no matches → return `[]`.
  3. `result = await _apiProvider.getStockBalanceReport(warehouse: warehouse,
     itemCodes: codes, fromDate: today, toDate: today)` (today = local date,
     `yyyy-MM-dd`).
  4. Narrow rows to the matched codes client-side (safety on ≤ v15.71, no-op on
     v15.72+; mirrors `StockBalanceController`), then `mapStockLines(rows)`.
- `static List<WarehouseStockLine> mapStockLines(List<Map<String,dynamic>> rows)`
  — **pure**, unit-testable: reads `item_code`, `item_name`, balance from
  `bal_qty` / `balance_qty`, `stock_uom`, absolute `item_image`; skips blank
  item codes.

Deriving item codes from a dedicated `search('Item', …)` (Approach A) keeps this
decoupled from whether the Item group renders and from the user's scope chip.

### GlobalDocumentSearchDelegate (`.../global_widgets/global_document_search_delegate.dart`)

- Read the Default Warehouse from `StorageService` lazily (fallback `null` when
  DI isn't warm, so widget tests stay service-free — same guard pattern the
  delegate already uses for `GlobalSearchService`).
- The Stock Balance section renders **when all hold**: query ≥ `_kMinChars`
  (3) **and** a Default Warehouse is set **and** the active scope is `null`
  (All) or the **Item** target (so it stays contextual; hidden when scoped to,
  e.g., Delivery Notes).
- Staging: the section is a **separate `FutureBuilder`** keyed on
  `(query, warehouse)`, appended below the document groups in the results
  `ListView`. The document results come from the existing `_search` future and
  render first; the SB section fills in afterwards — matching "after search
  results are displayed, fetch … with loading feedback."
- Section states:
  - **header** — reuses the group-header style: `STOCK BALANCE · <warehouse>`.
  - **loading** — a visible inline `LinearProgressIndicator` (on `scheme.bg`,
    so default colour is fine) under the header; follows the async-feedback
    convention (immediate, visible, painted).
  - **error** — caught and the section is **silently hidden** (a stock 403 or
    network error must not break document search).
  - **empty** — subtle `No stock for matching items in <warehouse>` line.
  - **rows** — item name/code + balance qty + UOM (+ thumbnail when present),
    each tappable → open the **Item form** (reuses the `Item` target's
    `route`/`argsFor`, consistent with the Item result rows).
- `@visibleForTesting Widget buildStockBalanceSection(context, warehouse, lines)`
  — pure renderer over canned lines, mirroring the existing `buildResultsList`
  test seam.

## Data flow

```
Session Defaults  ──save──▶  StorageService.saveDefaultWarehouse
                                     │
Dashboard search icon                ▼  getDefaultWarehouse()
  → GlobalDocumentSearchDelegate  ──▶ stockBalanceForQuery(query, warehouse)
        │  (doc groups render first)      │  search('Item',q) → codes
        └─ SB FutureBuilder (after) ──────┴─ getStockBalanceReport(wh, codes)
                                              → mapStockLines → rows
```

## Error handling

- Warehouse-list fetch failure (settings): non-fatal warning; picker empty.
- SB fetch failure (search): caught; section hidden. Document search unaffected.
- Default Warehouse unset: SB section never rendered.

## Testing

- **Unit** — `StorageService`: default-warehouse round-trip **and** clear
  (null/empty removes the key; `getDefaultWarehouse()` → null).
- **Unit** — `SessionDefaultsController`: `load()` restores saved warehouse;
  `persist()` writes it; `clearWarehouse()` → null persists as unset.
- **Unit** — `GlobalSearchService.mapStockLines`: maps qty from `bal_qty` and
  legacy `balance_qty`, name/uom/image; skips blank item codes.
- **Unit** — `stockBalanceForQuery`: returns `[]` when the item search yields no
  codes (inject a stub searcher/provider).
- **Widget** — Session Defaults screen shows the Default Warehouse field and
  opens `WarehousePickerSheet` on tap.
- **Widget** — `buildStockBalanceSection` renders header + rows over canned
  lines; loading state shows a visible indicator.

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/services/storage_service.dart` |
| Modify | `lib/app/modules/session_defaults/session_defaults_controller.dart` |
| Modify | `lib/app/modules/session_defaults/session_defaults_screen.dart` |
| Modify | `lib/app/data/services/global_search_service.dart` |
| Modify | `lib/app/modules/global_widgets/global_document_search_delegate.dart` |
| Add    | `lib/app/data/models/warehouse_stock_line.dart` |
| Add    | tests per the Testing section |

## Out of scope / YAGNI

- Company-scoped warehouse filtering in the settings picker.
- A "view full warehouse balance" action (user chose query-matched only).
- Persisting Default Warehouse to the ERPNext backend (device-local, like the
  other session defaults).

## Versioning

New setting + new search capability → **MINOR** bump at release time (per
`docs/versioning_conventions.md`); not bumped as part of this design.
