# Inline Warehouse Balance on Item Search Results — Design (revision)

**Date:** 2026-07-04
**Status:** Proposed
**Supersedes:** the Stock Balance *footer section* from
`2026-07-04-default-warehouse-stock-balance-search-design.md` (Task 5). The
Session Defaults "Default Warehouse" setting from that spec is unchanged.

## Why

The shipped design put the default-warehouse Stock Balance in a **separate list
below the document results**. That defeats "information at your fingertips" —
the balance is detached from the item it describes. This revision moves the
balance **inline, onto each Item search-result row**, adjacent to the item, and
adds **group-warehouse summation**.

## What changes

1. **Inline balance.** Each Item row in the Dashboard global-search results
   shows its Default-Warehouse balance as a **bold trailing quantity + UOM**
   (right-aligned, replacing the chevron for Item rows only). Non-Item rows are
   unchanged (keep the chevron). The whole row still taps through to the Item.
2. **Group warehouse.** When the Default Warehouse is a **group** warehouse, the
   displayed qty is the **sum** of its descendant leaf-warehouse balances.
3. **Remove the footer section** entirely (`_StockBalanceSection`,
   `buildStockBalanceSection`, `_qtyLabel`, `_sbScopeAllowed`, the `footer`
   param, `_itemTarget`).

## Staged loading

Document results render immediately. When a Default Warehouse is set **and** the
user has Item read access, a single balance fetch fires for the Item group's
item codes; the Item rows show a small **trailing loader** in the qty slot until
it resolves, then swap to the qty. This preserves the earlier "results first,
balance fills in with loading feedback" behaviour, now per-row.

## Architecture

A small stateful `_SearchResultsList` widget owns the fetch/rebuild:

- Renders the groups immediately (via the pure `buildResultsList`).
- In `initState` (and `didUpdateWidget` when the groups/query change), if
  `_defaultWarehouse != null` and `_itemReadable`, fires
  `GlobalSearchService.warehouseBalances(itemCodes, warehouse)` for the Item
  group's codes (reusing the codes already in `group.items` — **no second Item
  search**, which also removes the old duplicate-search inefficiency).
- Holds `Map<String, WarehouseStockLine>? _balances` (null = still loading) and
  `setState`s when it resolves. On error the map resolves to empty and Item rows
  fall back to the chevron (document search never breaks).

Rejected alternatives: a per-row `FutureBuilder` (N calls); fetching before
rendering results (delays the results).

## Service delta (`lib/app/data/services/global_search_service.dart`)

Replace `stockBalanceForQuery` / `mapStockLines` / `itemCodesFrom` with:

- `Future<Map<String, WarehouseStockLine>> warehouseBalances(List<String> itemCodes, String warehouse)`
  — returns `{}` for empty input; else `getStockBalanceReport(fromDate: today,
  toDate: today, itemCodes: codes, warehouse: warehouse)` then `aggregateByItem`.
- `static Map<String, WarehouseStockLine> aggregateByItem(List<Map<String,dynamic>> rows)`
  — **pure**. Groups rows by `item_code` (skipping blank codes), **sums** the
  balance (`bal_qty`, legacy fallback `balance_qty`) across all rows for that
  item, and takes `item_name` / `stock_uom` from the first row that carries
  them. Returns a map keyed by item code. This is what makes group warehouses
  work: ERPNext's Stock Balance `warehouse` filter expands a group warehouse to
  its descendant leaf rows, so summing per item yields the group total; a leaf
  warehouse returns a single row. (Assumption to confirm on-device.)

Keep the `_num` / `_today` helpers. `WarehouseStockLine` (itemCode, itemName,
balanceQty, uom) is unchanged.

## Delegate delta (`lib/app/modules/global_widgets/global_document_search_delegate.dart`)

- Keep `_defaultWarehouse` (guarded by `Get.isRegistered<StorageService>()`) and
  `_itemReadable` (mirrors `_permittedTargets` permission semantics).
- Remove all footer-section code listed above.
- `_buildResultsArea` success branch returns `_SearchResultsList(groups, onTap,
  warehouse: _defaultWarehouse, itemReadable: _itemReadable, service: _service)`
  instead of calling `buildResultsList` directly.
- `buildResultsList` gains an optional `{Map<String, WarehouseStockLine>? balances, bool balancesLoading = false}`.
  For **Item** rows (`target.doctype == 'Item'`): if `balancesLoading` → trailing
  small loader; else if `balances` has the code → bold trailing `'<qty> <uom>'`;
  else if `balances != null` (loaded, no row) → bold trailing `'0'`; else (feature
  off / `balances == null && !balancesLoading`) → the normal chevron. Non-Item
  rows always render the chevron. Default args (`null`, `false`) reproduce the
  current behaviour, so existing callers/tests are unaffected.
- `_resultTile` takes the optional balance/loading state and renders the trailing
  widget accordingly. Bold qty uses `scheme.text`; the loader is a small
  `SizedBox`-constrained `CircularProgressIndicator` visible on `scheme.bg`.
- Qty formatting: whole numbers render without decimals, else two decimals
  (e.g. `12 Nos`, `3.5 Mtr`).

## Data flow

```
Item search group (codes already known)
      │  warehouseBalances(codes, defaultWarehouse)
      ▼
getStockBalanceReport(today, codes, warehouse)  ── group wh → child rows
      │
aggregateByItem  ── sum bal_qty per item, uom from first row
      ▼
Map<itemCode, WarehouseStockLine>  → inline trailing qty on each Item row
```

## Error handling

- No Default Warehouse, or Item not readable → no fetch; Item rows keep the
  chevron (feature simply off).
- Fetch error → `_balances` resolves empty; Item rows show `0`/chevron; document
  search unaffected.

## Testing

- **Unit** — `aggregateByItem`: sums `bal_qty` across multiple rows for one item
  (group case); reads legacy `balance_qty` and string-parseable qty; takes
  uom/name from the first row; skips blank item codes; empty rows → empty map.
- **Widget** — `buildResultsList`:
  - with `balances` containing an Item's summed line → that Item row shows the
    bold trailing `'12 Nos'` and NO chevron;
  - with `balancesLoading: true` → Item row shows the trailing loader;
  - with defaults (no balances, not loading) → Item row shows the chevron
    (this is what keeps the existing delegate tests green);
  - a non-Item row always shows the chevron regardless of balances.

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/services/global_search_service.dart` (replace query/map/codes helpers with `warehouseBalances` + `aggregateByItem`) |
| Modify | `lib/app/modules/global_widgets/global_document_search_delegate.dart` (remove footer section; add `_SearchResultsList` + inline Item-row balance) |
| Modify | `test/unit/global_search_stock_balance_test.dart` (replace mapStockLines/itemCodesFrom tests with `aggregateByItem`) |
| Delete | `test/widget/stock_balance_search_section_test.dart` (the footer renderer no longer exists) |
| Modify | `test/widget/global_document_search_delegate_test.dart` (add inline-balance render cases) |

## Out of scope / YAGNI

- Fetching UOM for zero-stock items (absent row → show `0`, no UOM).
- Per-warehouse breakdown of a group total (only the summed qty is shown).
- Session Defaults setting behaviour (unchanged from the prior spec).

## Versioning

Still part of the same unreleased feature → **MINOR** bump at release time; not
bumped here.
