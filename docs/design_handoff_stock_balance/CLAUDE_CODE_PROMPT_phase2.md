# Claude Code prompt — Phase 2: operational enhancements

Builds on the shipped tile (Phase 1). Reference: `Stock Balance Report v2.html`
(behaviour in `stock_balance_app.js`). Four additions, all client-side over the
already-loaded `reportData` — **no new API calls** except lazy item images.
Paste the block below into Claude Code from `ddmco_multimax/`.

---

```
Extend the Stock Balance report (lib/app/modules/stock/reports/stock_balance/)
with four operational features. Behaviour reference:
design_handoff_stock_balance/Stock Balance Report v2.html. All filtering/sorting
is client-side over the rows already in StockBalanceController.reportData — do
NOT re-run the report for these. Keep everything theme-derived (light/dark).

1. HIDE OUT-OF-STOCK
   - Add `final hideEmpty = false.obs;` to the controller. A toggle Switch in
     the _SummaryStrip flips it. When on, the list excludes rows where
     bal_qty == 0. The summary count reflects the FILTERED count ("N shown");
     keep the total negative count from the full set.
   - Persist the choice with GetStorage (key 'sb_hide_empty') so it survives
     navigation, like the web report's "Hide" preference.

2. ITEM IMAGES
   - Show a 46x46 rounded thumbnail at the leading edge of the tile head from
     the item `image` field. The Stock Balance response does NOT include it, so
     add a controller step mirroring the existing customer_code enrichment:
     batch-fetch Item.image for the displayed item codes
     (_api.getItemImages(codes) → Map<code,url>) and attach as row['item_image'].
     Use frappe file URLs (prefix the site base if the path is relative).
   - CachedNetworkImage with a graceful fallback: when image is null/empty,
     render a tinted box with the item's initials (NOT a broken image). Lazy
     load (the list is already a SliverList, so off-screen rows don't fetch).
   - Add an `showImages` toggle (controller bool + Switch in the summary strip,
     persisted) so users can collapse to the dense, image-less layout.

3. QUICK FILTERS (client-side, distinct from the report-options sheet)
   - A control bar below the summary strip with: a search field (matches
     item_code OR item_name), a warehouse dropdown built from the distinct
     warehouses present in reportData, a sort dropdown
     (Balance ascending [surfaces negatives], Value descending, Movement
     [|in|+|out|], Code), and a 4-way segmented state filter
     (All / In stock / Negative / Empty).
   - Hold these as controller observables; expose a derived
     `List<Map> visibleRows` getter that applies search + warehouse + state +
     hideEmpty + sort, and drive the SliverList from it. The summary strip's
     negative chip is itself a toggle for the Negative segment.
   - Tapping a tile's warehouse text sets the warehouse quick-filter to that
     value (don't navigate away).
   - Empty result → an inline "no matches / clear quick filters" state.
   These are VIEW filters over loaded rows; the existing filter sheet (which
   re-queries the server) stays as-is.

4. TAP-TO-NAVIGATE (drill-downs as modal bottom sheets)
   - Tile body / ledger strip → Stock Ledger for that item+warehouse+period.
     Reuse the app's Stock Ledger route if one exists
     (Get.toNamed(Routes.stockLedger, parameters: {...})); otherwise open a
     bottom sheet listing the ledger entries (date, voucher, qty in/out,
     running balance) with a CTA to the full report. The sheet's running
     balance must reconcile with the tile's Opening→In→Out→Balance strip.
   - Reserved figure (in the availability bar) → bottom sheet listing the Sales
     Orders reserving the stock (SO no., customer, qty), only tappable when
     reserved > 0.
   - Customer-code tag → bottom sheet of items mapped to that customer code
     (reuse the customer_code resolution already in the controller) with an
     action to filter the report to that customer.
   - Use showModalBottomSheet with the app's standard sheet styling
     (drag handle, rounded top, a route/breadcrumb line naming the destination).

CONSTRAINTS
- Reuse Phase-1 widgets (_BalanceTile, _Ledger, _AvailabilityBar, etc.); add
  small private widgets for the control bar, thumbnail and each sheet.
- No layout regressions: the tile must still render all four health states and
  survive long item names (ellipsis).
- Run flutter analyze clean; extend the widget test to cover: hideEmpty filter,
  image fallback, each quick-filter, and that each tap target opens its sheet.
```
