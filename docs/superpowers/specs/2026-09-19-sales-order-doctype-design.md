# Sales Order DocType — design

Date: 2026-09-19 · Branch: `claude/sales-order-doctype` (from `origin/release/play-store` @ 9074fe26, 2.21.4+68) · Release: MINOR

## Scope (confirmed)

In:
1. **List**: search, status chips, filter sheet (customer, delivery date range, status, owner), Mine/Everyone, status pill with `per_delivered` / `per_billed` progress, Draft FAB gated by `DocTypeGuard`.
2. **Form**: view any SO; edit Draft only. Header (customer, transaction date, delivery date, order type, price list, set warehouse, PO no), Items tab + item sheet (item, qty, UOM, rate, delivery date, warehouse), server totals, Save / Submit / Cancel, dirty-dismissal guard.
3. **Lifecycle**: Hold / Resume / Close / Re-open via `update_status`.
4. **Make → Delivery Note** only.
5. **Link-ups**: Stock Balance reservation row → SO form; global search; dashboard actionable strip + preview (Draft / To Deliver); nav drawer (Selling, above Pricing); `digest_service` counts draft SOs.

Out: Make → Pick List (Pick List module not on `release/play-store`), Payment Schedule editing, taxes-template editing, Blanket Orders, Maintenance order type, printing.

## Verified v15 facts (live `erp.multimax.cloud`, ERPNext 15.121.1 / Frappe 15.120.1, read 2026-09-19 via `frappe.desk.form.load.getdoctype`)

**Header fields** (`R` = reqd in meta, `aos` = allow_on_submit):
- `naming_series` Select `SAL-ORD-.YYYY.-` R — server default; not shown.
- `customer` Link Customer R · `title_field` = `customer_name`.
- `order_type` Select `Sales / Maintenance / Shopping Cart` R, default `Sales`. We offer Sales and Shopping Cart only.
- `transaction_date` Date R, default Today.
- `delivery_date` Date, **not reqd in meta**, aos. Enforced in Python (`SalesOrder.validate_delivery_date`, v15 source): when `order_type == "Sales"` and not `skip_delivery_note`, header `delivery_date` is set to the **latest** row date; rows without a date **inherit** the header date; every row date must be ≥ `transaction_date` ("Expected Delivery Date should be after Sales Order Date"); if neither header nor any row has a date → "Please enter Delivery Date". So only ONE date (header or any row) is strictly required.
- `po_no` Data, aos. `set_warehouse` Link Warehouse. `skip_delivery_note` Check (default 0).
- `company` R, `currency` R, `conversion_rate` R, `selling_price_list` R, `price_list_currency` R, `plc_conversion_rate` R — server/session defaults (live: company `Multimax`, currency AED, price list `Standard Selling` from Selling Settings). The client sends company + price list; the server fills the rest on insert.
- `status` Select R ro: `Draft, On Hold, To Deliver and Bill, To Bill, To Deliver, Completed, Cancelled, Closed` (server-derived; never sent).
- `delivery_status`: `Not Delivered, Fully Delivered, Partly Delivered, Closed, Not Applicable`. `billing_status`: `Not Billed, Fully Billed, Partly Billed, Closed`. `per_delivered`, `per_billed`, `per_picked`: Percent ro.
- Totals ro: `total_qty`, `grand_total`, `rounded_total`. `taxes_and_charges` Link (display only).
- Custom fields (UAE VAT): `customer_name_in_arabic`, `company_trn` (Read Only), `permit_no` Data, `vat_emirate` Select, `tourist_tax_return` Currency. Display-only; never posted.

**Item fields** (`Sales Order Item`): reqd = `item_code, item_name, qty, uom, conversion_factor`. `delivery_date` (aos), `warehouse`, `rate` (editable), `price_list_rate` ro, `amount` ro, `stock_uom` ro, `delivered_qty`/`picked_qty`/`stock_reserved_qty` ro, `reserve_stock` (aos). Custom ro: `tax_code, tax_rate, tax_amount, total_amount`.

**Settings**:
- Stock Settings `enable_stock_reservation = 0` → `reserve_stock` hidden; Submit creates no Stock Reservation Entries. Live SRE count = 0.
- Stock Settings `auto_indent = 1` → submitted SOs raise Bin `reserved_qty`, which can trigger real Material Requests on items with reorder levels.
- Selling Settings `editable_price_list_rate = 0`. **Correction (v15 source, `sales_common.js` `toggle_editable_price_list_rate`)**: this setting only makes the row's **Price List Rate** column editable (it flips `price_list_rate.read_only` to 0). The row **`rate` is always editable** in desk regardless. The app never edits `price_list_rate` (it shows it read-only), so the setting needs no client handling. It is stored as a global default (`frappe.db.set_default`); Selling Settings itself is readable only by System Manager / Sales Manager. `selling_price_list = Standard Selling`. `so_required = No`, `dn_required = No`, `allow_multiple_items = 1`, `allow_negative_rates_for_items = 0`.

**DocPerms** (permlevel 0, `r c w s x a d`):
| Role | r | c | w | s | x | a | d |
|---|---|---|---|---|---|---|---|
| Sales User | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| Sales Manager | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| Maintenance User | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| Marketing User | 1 | 1 | 1 | 0 | 0 | 0 | 0 |
| Accounts User | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| Stock User | 1 | 0 | 0 | 0 | 0 | 0 | 0 |

Sales Manager also has permlevel 1 write. **System Manager has no row**: a pure SM cannot read SOs. The whitelisted `update_status` calls `frappe.has_permission("Sales Order", "submit", name, throw=True)` (v15 source), and desk shows the Status buttons only under `frm.has_perm("submit")`. So Hold/Resume/Close/Re-open gate on **submit**; Cancel on `cancel`; Submit on `submit`; Save on `write`. A Marketing User can create/save but cannot submit or change status.

**Desk lifecycle (v15 `sales_order.js` refresh, docstatus 1, `has_perm("submit")`)**:
- status `On Hold` → **Resume** = `update_status("Draft")`; **Close** if `per_delivered < 100 || per_billed < 100`.
- status `Closed` → **Re-open** = `update_status("Draft")` (server re-derives status; re-runs credit-limit check).
- other open statuses → **Hold** + **Close** if `per_delivered < 100 || per_billed < 100`.
- **Hold** requires a reason: desk posts `frappe.desk.form.utils.add_comment(reference_doctype, reference_name, content: "Reason for hold: …", comment_email, comment_by)` then `update_status("On Hold")`.
- **Close** = `update_status("Closed")`.
- **Make → Delivery Note** allowed when status ∉ {Closed, On Hold}, not `skip_delivery_note`, and some row has `delivered_by_supplier == 0 && qty > delivered_qty`.

**Whitelisted methods** (probed live; each returns `TypeError` for missing args, not `PermissionError`):
- `erpnext.selling.doctype.sales_order.sales_order.update_status(status, name)`: status ∈ {`On Hold`, `Closed`, `Draft`}
- `frappe.desk.form.utils.add_comment` (Hold reason)
- `erpnext.selling.doctype.sales_order.sales_order.make_delivery_note(source_name, target_doc=None, kwargs=None)`
- `erpnext.selling.doctype.sales_order.sales_order.create_pick_list` (not used this release)
- `erpnext.stock.get_item_details.get_item_details(args, doc=None, for_validate=False, overwrite_warehouse=True)`
- `frappe.client.insert(doc)`

**Live data**: 11 SOs, **all Draft**. No SO has ever been submitted on this site.

## Architecture

Mirrors `lib/app/modules/purchase_order/**` file for file.

- `lib/app/data/models/sales_order_model.dart`: `SalesOrder`, `SalesOrderItem` (`fromJson` / `toJson`; ro fields parsed, not serialised).
- `lib/app/data/providers/sales_order_provider.dart`: `getSalesOrders`, `getSalesOrder`, `createSalesOrder`, `updateSalesOrder`, `submit`, `cancel`, `updateStatus(name, status)`, `makeDeliveryNote(name)` (calls the mapper and then `frappe.client.insert`, returns the new DN name), `getItemDetails(...)`.
- `lib/app/modules/selling/sales_order/`
  - `sales_order_binding.dart`, `sales_order_controller.dart`, `sales_order_screen.dart`, `widgets/sales_order_filter_bottom_sheet.dart`
  - `form/sales_order_form_binding.dart`, `form/sales_order_form_controller.dart`, `form/sales_order_form_screen.dart`, `form/sales_order_item_form_controller.dart`, `form/widgets/sales_order_item_form_sheet.dart` (wraps `global_item_form_sheet` / `universal_item_form_sheet` as PO does)
  - `sales_order_logic.dart`: **pure Dart, no Flutter/GetX**; every unit test targets this file.
- Shared widgets reused, not re-implemented: `DocTypeListHeader`, list-view widgets + RxMap filter contract, form header, `DocDetailRow`, `FormEmptyState`, `DocPickerField`, `InlineBanner`, `AsyncIconButton` / `AsyncFilledButton`, `StatusPill`, `DocTypeGuard`.
- Hand-built layout (not the unreleased metadata-driven renderer).

### Wiring
`app_routes.dart` (`SALES_ORDER`, `SALES_ORDER_FORM`), `app_pages.dart`, `app_nav_drawer.dart` (Selling group, above Pricing), `permission_entries.dart` → `kSellingPermissions` (read/create/write for `Sales Order` only: `PermissionService` resolves create/write from getdoctype but probes every other permType with a read-level `get_list`, so submit/cancel there would wrongly pass for Stock/Accounts Users. Submit, cancel and status changes are checked per document with `frappe.client.has_permission` (`ApiProvider.hasDocPermission`), fail-closed, as Stock Entry Submit does), `global_search_targets.dart`, `home/widgets/dashboard_actionable_strip.dart` + `dashboard_actionable_preview.dart` + `home_controller.dart`: ONE `Sales Order` chip (the strip, count cache and preview cache are keyed one-chip-per-doctype) whose filter is `status in [Draft, To Deliver and Bill, To Deliver]`; its preview row shows `customer · owner · delivery date` plus the status, `digest_service.dart` (draft SOs, like PO), `stock_balance_sheets.dart` reservation row → `Get.toNamed(SALES_ORDER_FORM, {name, mode: 'view'})`.

## Data flow

- **List**: `getDocumentList('Sales Order')` with RxMap filters → `status`, `customer`, `delivery_date` between, `owner` (Mine/Everyone). Fields: name, customer, customer_name, status, transaction_date, delivery_date, grand_total, currency, per_delivered, per_billed, owner, modified.
- **Form load**: `getdoc` → `SalesOrder`. `docstatus != 0` is read-only.
- **New**: defaults `transaction_date = today`, `order_type = Sales`, `company` / `selling_price_list` from session defaults / Selling Settings; the header `delivery_date` pre-fills each new row.
- **Item pick**: `getItemDetails({item_code, customer, company, selling_price_list, price_list_currency, plc_conversion_rate, conversion_rate, currency, transaction_date, qty, uom, doctype: 'Sales Order', warehouse})` → fills `item_name`, `uom`, `conversion_factor`, `price_list_rate`, `rate`, `warehouse`. `rate` stays editable (v15); `price_list_rate` is shown read-only under it when > 0. The sheet shows the provisional `qty × rate` labelled as an estimate; the server recomputes on save.
- **Save**: POST (new) or PUT (draft) with editable fields only (`sales_order_logic.buildPayload`). The response's totals, VAT columns and status are re-rendered.
- **Submit / Cancel**: `frappe.client.submit` / `cancel`, then reload.
- **Lifecycle**: Hold → reason sheet (required text) → `add_comment` → `update_status('On Hold')`; Resume / Re-open → `update_status('Draft')`; Close → `update_status('Closed')` behind a confirm dialog; then reload.
- **Make → DN**: `make_delivery_note(source_name)` → `frappe.client.insert(mapped)` → `Get.toNamed(DELIVERY_NOTE_FORM, {name, mode: 'edit'})`. The DN form is unchanged.

## Pure logic (`sales_order_logic.dart`, TDD)

- `progressFraction(percent)` → 0.0–1.0 for the delivered / billed bars.
- `allowedActions(so, perms, canCreateDn)` → set of `{save, submit, cancel, hold, resume, close, reopen, makeDn}`, mirroring desk `refresh`:
  - docstatus 0: save if write; submit if submit.
  - docstatus 1 + submit perm: On Hold → resume, and close if not fully delivered+billed; Closed → reopen; other → hold + close if `per_delivered < 100 || per_billed < 100`.
  - docstatus 1 + cancel perm: cancel (all statuses except Cancelled; server blocks if linked DNs exist → banner).
  - makeDn: docstatus 1, status ∉ {Closed, On Hold}, not `skip_delivery_note`, some row `qty > delivered_qty` and not `delivered_by_supplier`, and `canCreateDn`.
  - Completed: only cancel (if perm). Cancelled (docstatus 2): none.
  - Perms unresolved (null) → **empty set** (fail closed, like `canCreateReceipt`).
- `isDirty(original, current)`: diff over editable header fields + item rows (item_code, qty, uom, rate, delivery_date, warehouse).
- `buildPayload(so)`: editable fields only; drops ro / computed / custom-VAT fields and empty optionals.
- `validateRow(row, transactionDate)` → field→message map: item_code non-empty; qty > 0; delivery_date (if set) ≥ transaction_date.
- `validateOrder(so)` → header-level: customer set; ≥ 1 item; when `order_type == Sales` and not skip_delivery_note, header or some row has a delivery date; header date ≥ transaction_date.
- `parseItemDetails(message)` → typed defaults from the `get_item_details` response.
- `statusFilterLabel(value)` → chip text for a `status` filter that is a String or `['in', [...]]`.
- Pill colour is NOT in this file: `StatusPill` gains `To Deliver and Bill` / `To Deliver` in its orange group (next to the PO analogues `To Receive and Bill` / `To Receive`).

## Error handling

- Server 417 / `_server_messages` → `InlineBanner` in the form. Item-sheet validation keeps the sheet open (PO re-order Done pattern).
- Async buttons use `AsyncFilledButton` / `AsyncIconButton` (spinner + re-entrancy guard + finally).
- `getItemDetails` failure → banner in the sheet, rate left editable at 0 (fail open to manual entry; the server re-validates on save).
- Known traps honoured: Rx reads hoisted out of `headerSliverBuilder`; `SliverOverlapAbsorber` + per-tab `SliverOverlapInjector`; no zero-Rx outer `Obx` around the FAB; no error-Rx-only rebuilds; `ListTile` in a coloured `Container` → `Material(transparent)`; reactive header actions in their own `Obx`; `Scrollbar` + shared controller, nav-bar padding, "End of list" marker; AppColors x700/x300 ramp.

## Testing

- `test/sales_order_logic_test.dart`: status/progress, `allowedActions` matrix incl. fail-closed, dirty diff, payload builder, row validation, rate lock.
- A widget test for the Stock Balance reservation row tap → `SALES_ORDER_FORM` route with the SO name.
- `flutter analyze` then `flutter test`, **sequentially**; compare against the baseline, no new failures.

## Smoke (device, side-by-side install)

Temporary `applicationIdSuffix` + label, reverted before commit. As a **Sales User (asrar)** and as an **SM account that also holds Sales User** (a pure SM can't read SOs; record that as expected). Light and dark mode.

Checklist: list filters + Mine/Everyone; create a Draft with 3+ items (rate prefilled from price list, still editable); Save; Submit; Hold → Resume; Close → Re-open; Make DN opens our DN form; reservation → SO.

Live-site safety:
- Use items with **no reorder levels** (`auto_indent = 1`).
- **User** temporarily enables Stock Settings → Stock Reservation to smoke the reservation tap, then disables it.
- Afterwards, cancel the smoke SOs and delete the draft DNs we created.
