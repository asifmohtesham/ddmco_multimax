# Sales Order → Delivery Note (scan-to-pick)

Dashboard → **Sales Order** tile → sheet of open orders → tap one → Delivery Note
bound to that order. Built for Sales Users picking at the warehouse.

## Open orders sheet
- `docstatus = 1`, `status in (To Deliver and Bill, To Deliver)`, `per_delivered < 100`,
  ordered by `delivery_date asc` (most urgent first). Due chip: Overdue / Due today / Due <date>.
- Selecting an order **resumes** its draft DN if one exists
  (`Delivery Note Item.against_sales_order = SO`, `docstatus = 0`); otherwise starts a new one
  with `salesOrderName` in the route arguments.

## SO-bound Delivery Note (`delivery_note/form`, logic in `so_pick.dart`)
- New DN header comes from ERPNext's own `make_delivery_note` mapper (company, price list,
  taxes, addresses, set_warehouse) with **items dropped** — only scanned items are delivered.
- An existing DN enters SO mode when any row has `against_sales_order`.
- Scans are gated: an item not on the order → "Not on this order"; a fully picked item →
  "Already picked". The scan binds to the first SO line for that item with room.
- Qty cap per row = SO line open qty (`qty − delivered_qty`) − qty already in this DN,
  combined with the existing batch/rack balance caps.
- Each row carries `against_sales_order`, `so_detail`, the SO rate/UOM/conversion factor and
  `custom_invoice_serial_number = SO line idx` (that custom field is a mandatory Int on DN and
  Packing Slip items; SO idx plays the same role the POS Upload idx does).
- Duplicate rescans merge only when `so_detail` also matches.
- An item-less new DN is never saved (ERPNext would reject it) and is not "dirty".
- DNs stay **draft** in-app, like every other DN; submit in Desk.

## Server prerequisites
- ERPNext v15 and v16. On v16 the session carries a CSRF token, so cookie-session writes need
  `X-Frappe-CSRF-Token`; `CsrfInterceptor` fetches it from the desk boot page on the first
  `CSRFTokenError` and retries once (see `lib/app/data/providers/csrf_interceptor.dart`).
