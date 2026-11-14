# BOM Stock — Customer-Code Grouped POS View (delta)

**Date:** 2026-06-30
**Status:** Approved, pending implementation
**Branch:** release/play-store
**Builds on:** the card redesign (`2026-06-29-bom-stock-customer-code-card-redesign.md`)

## Motivation

On-device smoke of a POS-Upload run: the flat card list doesn't convey demand *per
customer code*, the running-total depletion (a repeated item's stock consumed by an
earlier line) isn't visible, and the green/red coding isn't apparent enough. Plus a
bug: the filter sheet's **Run Report** button is clipped by the system navigation bar.

Grouping by **Invoice Serial Number** was considered and dropped — the report carries
no per-invoice-line / serial data (only `customer_code` + aggregated `required_qty`),
and invoice serials only exist on linked Delivery Notes/Stock Entries. **Customer Code**
is already on every report row, so grouping by it needs no server change.

## Decisions

- **Group by Customer Code**, only when a **POS Upload is active**; otherwise the
  current flat `BomStockTile` list is unchanged.
- **Collapsed by default**, expand on tap (mirrors the POS Upload form's item card:
  `Card` header + `AnimatedSize` expandable panel).
- **Depletion uses the server's existing `running_total` / `shortage_qty`** — no client
  recomputation, no server change. `running_total` ("Avail") is the stock left for a line
  after prior consumption (a repeated item's later lines read `Avail 0`).
- **Line figures: In Stock · Avail · Need · Short.**
- **Green = covered, Red = shortage**, applied to both the group header and each line
  (left accent + tint + pill). Green = the app's theme-aware success token; red =
  `colorScheme.error`. No hardcoded colors.
- Segmented `All | In Stock | Shortage` filter applies to the rows *before* grouping;
  groups recompute over the filtered set (a group with no matching lines disappears).
  Totals footer unchanged (over filtered rows).
- Fix the filter sheet's clipped Run Report button (bottom safe-area).

## Data (report row, already available)

`sl_no, item_name, item_code, item_group, customer_code, bom, in_stock_qty,
required_qty, running_total, shortage_qty, enough_parts_to_build`. `required_qty` /
`shortage_qty` / a meaningful `running_total` are populated only when a POS Upload is
selected.

## Components

### 1. Controller (`BomStockCustomerCodeController`)

- **New value type** `BomStockGroup`:
  ```dart
  class BomStockGroup {
    final String code;                       // customer_code ('' bucketed last)
    final List<Map<String, dynamic>> rows;
    const BomStockGroup(this.code, this.rows);
    int get itemCount => rows.length;
    num get totalShortage => rows.fold<num>(0, (a, r) => a + (toNum(r['shortage_qty']) ?? 0));
    bool get anyShort => rows.any(BomStockCustomerCodeController.isShortfall);
  }
  ```
- **New static** `static List<BomStockGroup> groupByCustomerCode(List<Map<String,dynamic>> rows)`
  — buckets rows by `customer_code` in first-seen order (preserving the server row order
  within each group), one `BomStockGroup` per distinct code.
- **New getter** `List<BomStockGroup> get groupedRows => groupByCustomerCode(filteredRows);`
- **Expand state** (collapsed by default): `final expandedCodes = <String>{}.obs;`
  `void toggleGroup(String code)` (add/remove); `bool isGroupExpanded(String code) =>
  expandedCodes.contains(code);`. `clearFilters()` also clears `expandedCodes`.

### 2. `BomStockGroupCard` (new widget)

Mirrors the POS Upload item `Card`:
- `Card(elevation 0, radius 12, BorderSide(group.anyShort ? error : success), surfaceContainerLowest)`.
- **Header** `InkWell(onTap: onToggle)`: leading status dot/icon (green/red), `Code {code}`
  (or "No code" when empty) bold, a subtitle `"{itemCount} items"`, a trailing status pill
  (green **"Covered"** / red **"{totalShortage} short"**) + an `AnimatedRotation` chevron.
  Left accent + subtle tint keyed on `anyShort`.
- **Body** `AnimatedSize`: when `expanded`, a bordered panel listing `BomStockLineRow`s
  separated by dividers; when collapsed, `SizedBox.shrink()`.

Signature: `const BomStockGroupCard({required BomStockGroup group, required bool expanded, required VoidCallback onToggle})`.

### 3. `BomStockLineRow` (new widget)

A condensed item line for inside a group:
- Item name (`bodyMedium w600`) + subline `item_code · item_group`.
- Figures via the `_StatCell` style: **In Stock** (`in_stock_qty`) · **Avail**
  (`running_total`) · **Need** (`required_qty`) · and the coverage pill (green **Covered** /
  red **Short N** from `shortage_qty`); `Short`/`Avail` go red on shortfall.
- Left accent keyed on `isShortfall(row)` (green/red).

Signature: `const BomStockLineRow({required Map<String,dynamic> row})`.

### 4. Screen (`BomStockCustomerCodeScreen`)

- In the results body (the non-empty branch), when `controller.posUpload.value != null`,
  render the grouped list: one `BomStockGroupCard` per `controller.groupedRows`, wired to
  `controller.isGroupExpanded(code)` / `controller.toggleGroup(code)`. Otherwise keep the
  flat `BomStockTile` list over the snapshot `rows`.
- Segmented filter, loading/empty arms, footer, and the footer guard are unchanged.
  (The "filter hides everything" empty arm uses `rows.isEmpty`, which still works since
  `groupedRows` derives from `filteredRows`.)

### 5. Filter sheet (`bom_stock_filter_sheet.dart`)

- Wrap the bottom **Run Report** button in `SafeArea(top: false, child: …)` (or add
  `MediaQuery.of(context).viewPadding.bottom` to the sheet's bottom padding) so it always
  clears the system navigation bar.

### 6. Color tokens

A theme-aware **success** (green) color is needed for "covered". Use the app's existing
semantic success token if one exists in the design system (`AppColors`/`AppScheme`);
otherwise add a small theme-aware green helper. Confirm the exact token during
implementation. Red uses `colorScheme.error`.

## Out of scope

API layer, routing, drawer, the report's server logic (`running_total`/`shortage_qty`
already provided). The flat (non-POS) `BomStockTile` view is unchanged.

## Testing

- **Controller unit**: `groupByCustomerCode` (bucketing, first-seen order, empty-code
  handling); `BomStockGroup` getters (`itemCount`, `totalShortage`, `anyShort`);
  `toggleGroup`/`isGroupExpanded` (collapsed by default).
- **`BomStockGroupCard` widget**: collapsed shows header only (no line rows); expanded
  shows the line rows; header status is green when `anyShort` is false, red when true.
- **`BomStockLineRow` widget**: shows In Stock/Avail/Need/Short; Covered vs Short pill;
  alert styling on shortfall.
- **Screen widget**: grouped cards render when `posUpload` is set; flat tiles when null.
- Filter-sheet Run button safe-area: manual/on-device (layout inset).
