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
