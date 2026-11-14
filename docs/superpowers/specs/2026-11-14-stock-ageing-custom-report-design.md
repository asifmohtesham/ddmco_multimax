# Stock Ageing - Custom Report — Design Spec

**Date:** 14 November 2026
**Feature:** Stock → Reports → Stock Ageing
**Status:** approved by the user on 14/11/2026

## Intent

Put the ERP's `Stock Ageing - Custom` report at the user's fingertips on the
phone, behaving exactly as the Desk (web) version does.

## Server facts (verified 14/11/2026 on `erp.domain.com`, frappe 15)

- `Stock Ageing - Custom` is a Frappe **Custom Report** over core
  `Stock Ageing` (`ref_doctype = Item`, `prepared_report = 0`).
- Saved filters: company, `to_date` (rewritten to today hourly by a Server
  Script), `warehouse = Finished Goods - KA`, `range = "90, 180, 360, 720"`,
  `show_warehouse_wise_stock = 1`.
- 24 frozen columns: item code, image, variant of, item name, country of
  origin, description, item group, brand, warehouse, qty, average age,
  `rangeN` / `rangeNvalue` for five buckets, earliest, latest, UOM.
- A default run returns ~2,500 item × warehouse rows (dicts), ~1.1 MB, ~18 s.
- `frappe.desk.query_report.run`:
  - without `are_default_filters` (defaults to true) the saved filters
    **replace** the caller's and are echoed back as `message.custom_filters`;
  - with `are_default_filters=false` the caller's filters are used and
    `company`, `to_date` and `range` become mandatory.

## Goals

- Same behaviour as the Desk: saved defaults apply until the user changes a
  filter; after that the user's filters are sent.
- Opening the screen shows data immediately (device cache of the default run).
- Bucket labels come from the returned columns, never hard-coded.

## Non-goals

- Editing the report definition from the app.
- Charts, export, the `Stock Ageing - Multiselect` report.
- Item images (a follow-up if wanted).

## Approaches considered

1. **Call the Custom Report, mirror the Desk's default-filter rule** — chosen.
   Keeps the saved columns and defaults in one place (the Desk).
2. Call core `Stock Ageing` with app-owned filters — loses the saved columns
   and duplicates the defaults in the app.
3. Always send `are_default_filters=false` — rejected by the user.

## Behaviour

### Filters (mirror `stock_ageing.js`)

| Key | Sheet control | Notes |
|-----|---------------|-------|
| `to_date` | date picker | required |
| `warehouse_type` | Warehouse Type link | |
| `warehouse` | Warehouse link | |
| `item_code` | Item link | |
| `brand` | Brand link | |
| `range` | text | required, e.g. `90, 180, 360, 720` |
| `show_warehouse_wise_stock` | toggle | |

`company` is not editable: it is taken from the server defaults, falling back
to the session default company.

- First load sends `filters={}` with no `are_default_filters`. The filter
  sheet is then pre-filled from `message.custom_filters`.
- On *Run Report*, the sheet's values are compared with those defaults. Equal
  → default call again. Different → full filter map with
  `are_default_filters=false`.
- *Clear* restores the server defaults.
- Active-filter chips show only the filters that differ from the defaults.

### Device cache (builder's call, approved)

- Only the default-filter result is cached, as one JSON file in the app
  support directory, with the fetch time.
- On open: show the cache at once; refresh automatically only when the cache
  is stale (policy in `StockAgeingController.shouldAutoRefresh`).
- Pull-to-refresh always refetches. A failed refresh keeps the cached rows.
- Header subtitle: `As on DD/MM/YYYY · fetched HH:mm`.

### On-phone view

- Search over item code, item name, variant-of and warehouse.
- Sort: average age (default, oldest first), quantity, oldest-bucket
  quantity, item code.
- Summary strip: total quantity, total value, stacked bar of bucket totals.
- Row tile: item code, name, warehouse, qty + UOM, average age, bucket bar.
- Tap → sheet with every bucket's qty and value, earliest/latest, group,
  brand, variant-of, country of origin.

### Placement and permission

`NavLink` under Stock → Reports, gated on `Item` / `report` (already in
`kStockPermissions`). Route `/stock/reports/stock-ageing`.

## Left to the builder

File layout follows `stock/reports/stock_balance`; pure static helpers on the
controller / `ApiProvider` carry the logic so it is unit-testable.

---

## As built (v2.32.0+108, amended in v2.34.0+111)

The sections above are the design as first approved. The screen that shipped
differs in the ways below; where they conflict, this section is correct.

### Report name

The server report is `Stock Ageing - Custom` (`ApiProvider.kStockAgeingReport`).
The nav link uses that server name with the label "Stock Ageing", because the
drawer mirrors the Desk sidebar by report name.

### Cache staleness

`StockAgeingLogic.shouldAutoRefresh`: the cached default run is refetched in
the background when it is from an earlier calendar day, is four hours old or
more (`maxCacheAge`), or carries a fetch time ahead of the device clock.

### Runs requested mid-refresh

A run requested while one is in flight is queued and started when the current
one finishes; it is never dropped. A default run that finishes while the user
has edited the filter sheet does not overwrite those edits.

### Default-filter check

Only the filters the sheet can edit are compared with the saved defaults
(`_sheetIsDefault`), so a saved company or any other saved key never makes an
untouched sheet look edited. Saved filters the sheet cannot edit are carried
along on user-filter runs.

### Age buckets come from the range in effect

A Frappe Custom Report freezes its column list, so the server returns the saved
bucket titles ("Age (0 - 90)"…) whatever range the rows were calculated with,
and omits columns for buckets the saved list never had.
`StockAgeingLogic.applyRange` rebuilds the bucket columns (`rangeN`,
`rangeNvalue`, titled "Age (a - b)" / "Value (a - b)", ending "(n - Above)")
from the range the app sent, or the saved default range. This matches what core
Stock Ageing returns and deliberately differs from the Desk view of the custom
report, which mislabels buckets when the range is changed.

### Cards and the row sheet follow the report's columns

Rules agreed with the user for every Frappe report screen:

- Labels are the report's own column titles, verbatim, read from
  `message.columns` (`StockAgeingLogic.parseColumns`); cells are formatted by
  the column's `fieldtype` (`formatCell`).
- Tapping a card opens a sheet listing **every** report column in report order.
  The item image is shown edge to edge at the top, with the drag handle drawn
  over it; tapping it opens the full-screen preview.
- `Variant Of` is prominent on the card (a tinted badge under the item code).
- No app-invented figures or wording: `Average Age 523`, not "avg 523 days".

Item Code and Available Qty (with UOM) are always on the card. Every other
column is the user's choice, picked in the "Card fields" sheet (header action)
and saved per device (`StorageService` key `sa_card_columns`). The stacked age
bar is the one card element that is not a report column. Defaults: Variant Of,
Item Name, Warehouse, Average Age, age bar.

### Header chips

- Sort choices (Oldest, Quantity, Oldest bucket, Item code) sit in the header's
  chip row via `DocTypeListHeader.quickChips`, after the filter chips.
- Active-filter chips show only filters that differ from the saved defaults.
  Tapping a chip opens the filter sheet on that filter, ready to edit
  (`FilterChipWidget.onTap` → `showReportFilterSheet(focusKey:)`: text fields
  take focus, date and link fields open their picker). The × clears it.
- The header repaints on a change in filter *count*; this screen folds the chip
  texts into `quickChipsKey` so a changed value is redrawn too.

### Search

An inline search field in the body (item code, item name, variant-of,
warehouse). The header's own search is wired to DocType search and is not used.

### Other

- The report call allows a 120 s receive timeout; a default run takes ~18 s.
- Bucket colours are a fixed green-to-red ramp, not theme colours.
