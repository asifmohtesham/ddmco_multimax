# BOM Stock with Customer Code — Card Redesign (delta)

**Date:** 2026-06-29
**Status:** Approved, pending implementation
**Branch:** release/play-store
**Builds on:** `2026-06-29-bom-stock-customer-code-report-design.md` (the shipped feature)

## Motivation

On-device smoke showed the result cards are "messy, unclear, hard to read." Root
problems: the redundant full customer name dominated (and overflowed), the
customer code (the report's namesake) was a tiny chip, the empty/broken image box
wasted the left column, and "In Stock / Required / Running" read as three
disconnected numbers. The server report was also updated to compute
**`shortage_qty`** (`required − running`, clamped ≥ 0) per row — the actionable
deficit is now first-class data.

## Decisions (from brainstorming)

- **Card mirrors the POS Upload form's Items list-tile** (`pos_upload_form_screen.dart`:
  the `_PosUploadItemTile` `Card`): bordered `Card` (radius 12, `outlineVariant`
  border, `surfaceContainerLowest`) → header (index badge + item name + status) →
  `Divider` → `_Stat` row → chips `Wrap`. This also retires the thumbnail (the POS
  tile uses an index badge, not an image).
- **Segmented filter row `All | In Stock | Shortage`** above the results
  (client-side, mirroring Stock Balance's `_SegmentedStateFilter`).
- **Customer Codes filter stays chips** — no dropdown, no new dependency
  (reaffirmed; out of scope here).
- Customer name **removed from the card** (already shown as the `Customer:` header
  filter chip).
- **Shortfall** is now `shortage_qty > 0` (server-authoritative), replacing the
  `running < required` derivation.
- **Totals footer** shows `Stock · Need · Short`, computed client-side over the
  **currently-filtered** rows so it stays consistent with the segmented filter.

## Data fields (per result row, unchanged server contract + new field)

`sl_no, image, item_name, item_code, customer_code, customer, item_group,
parent_item_group, bom, in_stock_qty, required_qty, running_total,
shortage_qty (NEW), enough_parts_to_build`. `required_qty`/`shortage_qty` are
populated only when a POS Upload is selected.

## Component changes

### 1. Controller (`BomStockCustomerCodeController`)

- **Redefine** `static bool isShortfall(Map row)` → `final s = toNum(row['shortage_qty']);
  return s != null && s > 0;` (drops the `running < required` body).
- **New segmented-filter state**: `final rowFilter = 'ALL'.obs;` with values
  `'ALL' | 'instock' | 'shortage'`; setter `void setRowFilter(String v) => rowFilter.value = v;`.
- **New static** `static List<Map<String,dynamic>> applyRowFilter(List<Map<String,dynamic>> rows, String filter)`:
  - `'instock'` → rows where `(toNum(r['in_stock_qty']) ?? 0) > 0`
  - `'shortage'` → rows where `isShortfall(r)`
  - else (`'ALL'`) → rows unchanged.
- **New getter** `List<Map<String,dynamic>> get filteredRows => applyRowFilter(reportRows, rowFilter.value);`
- **New static** `static Map<String,num> sumTotals(List<Map<String,dynamic>> rows)` →
  `{'in_stock':Σin_stock_qty, 'required':Σrequired_qty, 'shortage':Σshortage_qty}`
  (each via `toNum(...) ?? 0`).
- **New getter** `Map<String,num> get filteredTotals => sumTotals(filteredRows);`
- `runReport()` unchanged except it already populates `reportRows`; the existing
  `totalRow`/`extractTotalRow` stay (they still keep the server total row OUT of the
  card list) but are no longer used for the footer.
- `clearFilters()` also resets `rowFilter.value = 'ALL'`.

### 2. `BomStockTile` (rebuilt to mirror the POS item tile)

```
Card(elevation 0, clip antiAlias,
     shape: RoundedRectangleBorder(radius 12,
        side: BorderSide(color: shortfall ? cs.error : cs.outlineVariant)),
     color: cs.surfaceContainerLowest,
  child: Padding(12, Column(crossStart, [
    // Header
    Row(crossStart, [
      CircleAvatar(radius 10, bg cs.primaryContainer,
         child Text(sl_no, fontSize 9, bold, cs.onPrimaryContainer)),
      SizedBox(8),
      Expanded(Column(crossStart, [
        Row(crossStart, [
          Expanded(Text(itemName, bodyLarge w600)),
          if (hasReq) _StatusPill(shortage),     // right-aligned
        ]),
        Text(join(' · ', [itemCode, itemGroup]), labelSmall onSurfaceVariant),
      ])),
    ]),
    SizedBox(8), Divider(height 1), SizedBox(8),
    // Stats
    Row(spaceBetween, [
      _StatCell('In Stock', formatQty(inStock)),
      if (hasReq) _StatCell('Need',  formatQty(reqNum)),
      if (hasReq) _StatCell('Short', formatQty(shortageNum), alert: shortage>0),
      if (enough != null) _StatCell('Build', enough.toString()),
    ]),
    // Chips
    if (chips.isNotEmpty) [SizedBox(10), Wrap(spacing6 runSpacing6, chips)],
  ])))
```

- `hasReq = toNum(row['required_qty']) != null` (POS active).
- `shortageNum = toNum(row['shortage_qty']) ?? 0`.
- **`_StatusPill`** (local): rounded pill. `shortage > 0` → `cs.errorContainer` bg /
  `cs.onErrorContainer` fg, warning icon, label `"Short ${formatQty(shortage)}"`.
  `shortage == 0` → `cs.secondaryContainer` bg / `cs.onSecondaryContainer` fg, check
  icon, label `"Covered"`. (Theme-safe; no hardcoded colors.)
- **`_StatCell`** (local, mirrors POS `_Stat`): label `labelSmall onSurfaceVariant`
  over value `bodyMedium w600`; optional `alert` paints the value `cs.error`.
- **Chips** (`Wrap`): customer code (`Icons.qr_code_2`) + BOM (`Icons.account_tree_outlined`,
  only when present). Each chip keeps the overflow-safe `ConstrainedBox + Flexible +
  ellipsis` form already in the file (BOM names can be long). Customer name and the
  item-group chip are gone (item group moved to the header subline).
- Thumbnail (`_thumb`) removed.

### 3. `BomStockTotalsFooter` (computed totals)

- New signature: `const BomStockTotalsFooter({required Map<String,num>? totals, required bool hasDemand})`.
- `totals == null || totals.isEmpty` → `SizedBox.shrink()`.
- Renders `Total` + `Stock` (`totals['in_stock']`) always; `Need` (`totals['required']`)
  and `Short` (`totals['shortage']`) **only when `hasDemand`** (a POS Upload is active).
  Same `Material elevation 8 / surfaceContainerHighest / SafeArea` shell + `_cell`.

### 4. Screen (`BomStockCustomerCodeScreen`)

- After the POS banner and before the body, when `reportRows` is non-empty, insert a
  `SliverToBoxAdapter` with a padded **`_SegmentedRowFilter`** (`All | In Stock |
  Shortage`, mirroring Stock Balance's `_SegmentedStateFilter`) bound to
  `controller.rowFilter.value` / `controller.setRowFilter`.
- List builds from **`controller.filteredRows`** (not `reportRows`).
- When `reportRows` non-empty but `filteredRows` empty (filter hides everything),
  show a small inline "No items match this filter" message (not the big set-filters
  empty state).
- Footer: `BomStockTotalsFooter(totals: controller.filteredTotals, hasDemand:
  controller.posUpload.value != null)`.

## Out of scope

Filters, API layer, routing, drawer, the filter sheet — unchanged. No server changes
(the report already emits `shortage_qty`).

## Testing

- **Controller unit**: `applyRowFilter` (ALL/instock/shortage); `sumTotals`;
  `isShortfall` redefined on `shortage_qty`. Update the existing `isShortfall` tests
  (which keyed on required/running) to the new `shortage_qty` contract.
- **Tile widget**: status pill Covered vs Short; `Need`/`Short` shown only when a POS
  row (`required_qty` present); `Build` only when `enough_parts_to_build` present;
  long BOM name does not overflow.
- **Footer widget**: `Stock` always; `Need`/`Short` only when `hasDemand`; null totals
  render nothing.
- **Segmented filter widget**: renders three segments; tapping invokes the callback.
