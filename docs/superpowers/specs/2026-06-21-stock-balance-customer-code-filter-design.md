# Stock Balance — Customer Code Filter

**Date:** 2026-06-21
**Status:** Approved (design)

## Goal

Add a "Customer Code" filter to the Stock Balance report filter sheet
(Menu → Stock → Stock Balance → Filters), so users can narrow the report to
items matching a given customer code — mirroring the column filter they
already use in the ERPNext web report grid.

## Background

- "Customer Code" in the ERPNext Stock Balance report is a column the user
  added (via *Add Column → Item → Customer Code*). It is sourced from the
  Item's **Customer Items** child table (`customer_items`, the standard
  `Item Customer Detail` doctype) → **`ref_code`** field.
- The ERPNext `Stock Balance` query report has **no server-side customer
  filter**. Its only Item-level filters are `item_group`, `item_code`, and
  `brand`. There is therefore no native filter key to pass through.
- The web grid filters this column **client-side** (a "like"/contains filter
  in the datatable). We mirror that behaviour.
- `ApiProvider.parseStockBalanceResponse` (api_provider.dart) already
  preserves **every** column the report returns, including `customer_code`,
  in each row map. So the value is already available app-side once a report
  runs — no new endpoint is required.

## Approach

Pure **client-side view filter** on the rows the report already returns.
No new API call, no dependency on the Item child fieldname.

### 1. Filter field

Add to `StockBalanceController.filterFields` (after Item Group):

```dart
const ReportFilterField(
  key:        'customer_code',
  label:      'Customer Code',
  type:       ReportFilterType.text,
  prefixIcon: Icons.badge_outlined,
),
```

Supporting wiring in `StockBalanceController`:

- New `customerCodeController = TextEditingController()`.
- Register `'customer_code': customerCodeController` in `filterControllers`
  (drives active-filter count + chip automatically).
- Reset it in `clearFilters()`.
- Add `'customer_code': 'Customer'` (or `'Customer Code'`) to `_filterLabels`
  so the active-filter chip reads sensibly.

The existing `activeFilterCount`, `clearFilter`, and `_rebuildActiveFilters`
machinery cover the new field with no further change.

### 2. Apply the filter in `runReport()`

After `reportColumns`/`reportData` are populated from the API result, if the
trimmed `customer_code` value is non-empty:

1. Find the row key by locating the column in `reportColumns` whose `label`
   equals `"Customer Code"` (case-insensitive); fall back to a column whose
   `fieldname` is `customer_code`.
2. Keep only rows whose value at that key, lower-cased and trimmed,
   **contains** the entered text (lower-cased, trimmed).
3. `reportData.assignAll(filtered)`.

### 3. Fail-open safety

If no matching column is found in the response (report config does not ship
the Customer Code column), **skip** filtering — show all returned rows — and
surface a one-time `GlobalSnackbar.info`/`warning`:
"Customer Code column not available in this report." This guarantees the
result is never silently empty due to a missing column.

## Behaviour & trade-offs

- **Multiple customer rows per item:** the report flattens `customer_items`
  to one displayed Customer Code value; we filter on what is shown, identical
  to the web grid.
- **Re-fetch on Run:** changing only Customer Code and tapping Run re-fetches
  the report; the client-side filter rides on the existing fetch. This keeps a
  single code path and matches current report UX.
- **Display:** no screen change — `stock_balance_screen.dart` already renders
  `reportColumns` dynamically, so the Customer Code column appears whenever the
  report returns it.

## Out of scope

- Server-side filtering / Item child-table pre-query.
- Forcing the Customer Code column into the report if the ERPNext report
  config omits it.
- Filtering against non-displayed `ref_code` values when an item has multiple
  customer rows.

## Files touched

- `lib/app/modules/stock/reports/stock_balance/stock_balance_controller.dart`
  — only file expected to change.

## Testing

- Unit test (`test/unit/`): given a `reportData`/`reportColumns` fixture with a
  Customer Code column, `runReport`'s filter step keeps only matching rows
  (contains, case-insensitive) and is a no-op when the column is absent.
  Refactor the filter into a small pure helper (e.g.
  `filterRowsByCustomerCode(rows, columns, query)`) to make it directly
  testable without HTTP.
- Manual smoke: Stock Balance → Filters → enter a known customer code →
  Run → verify rows narrow to that code; clear → all rows return.
