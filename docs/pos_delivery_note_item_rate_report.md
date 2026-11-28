# POS and Delivery Note Item Rate — Report Implementation Guide

> **Scope:** This is a **backend (ERPNext Desk) artifact**, not Flutter code. It
> lives on the Frappe instance (`erp.multimax.cloud`) as a no-app **Script Report**
> plus a **Client Script**. Because Desk artifacts are not under source control,
> this document and the code in the private `erp-scripts` repository
> (`reports/pos-and-delivery-note-item-rate/`) are the reproducible source — recreate the report from
> here if it is ever lost, migrated, or needs to be rebuilt on another instance.

The report bridges `POS Upload Item.ref_code` (the customer's own item code) to the
ERPNext `Item.item_code`, using submitted **Delivery Notes as the evidence**. It was
built to ease a one-off backfill: mapping new customer codes into
`Item` → **Customer Items** (`Item Customer Detail`), which are entered **manually**
after reviewing the report. There is no write-back / Apply feature by design.

- **Report name:** `POS and Delivery Note Item Rate`
  (formerly `Customer Code Backfill (POS Upload to Delivery Note)`)
- **Report type:** Script Report · **Is Standard:** No · **Module:** Stock
- **Ref DocType:** POS Upload

---

## 1. Prerequisites

| Requirement | Detail |
|---|---|
| Server-side scripts enabled | `server_script_enabled = 1` in `site_config.json` (needed for non-standard Script Reports). |
| Custom field | `Delivery Note Item.custom_invoice_serial_number` must exist and be populated — it carries the source `POS Upload Item.idx`. |
| Link field | `Delivery Note.po_no` must hold the source `POS Upload.name`. |
| Roles | Grant the report to whichever roles need it (read-only; no writes performed). |
| System Manager | Required to create the Report + Client Script and (if renaming) to Duplicate/Delete. |

---

## 2. The join model

A POS Upload is the source of a Delivery Note. Each upload **line** resolves to a DN
**line**, which supplies the ERPNext `item_code`; the DN supplies the `customer`.

```
POS Upload  ──(name = po_no)──▶  Delivery Note
   │ item (idx)                      │ item (custom_invoice_serial_number = idx)
   ▼                                 ▼
POS Upload Item.ref_code   →   Delivery Note Item.item_code + DN.customer
                           →   proposed (item_code, customer, ref_code) triple
```

- **Parent join:** `Delivery Note.po_no = POS Upload.name` (submitted DNs only, `docstatus = 1`).
- **Line join:** `Delivery Note Item.custom_invoice_serial_number = POS Upload Item.idx`
  (positionally sound on real data — verified).
- **Mapping target:** `Item Customer Detail`, keyed on the **full triple**
  `(item_code, customer_name, ref_code)`. The relationship is **many-to-many**: one
  customer may hold several `ref_code`s on one item, and one `ref_code` may map to
  several items. `icd.name IS NULL` ⇒ the triple is not yet recorded ("New").

> **Field gotchas** (confirmed on the live instance):
> - POS Upload date field is **`date`** (not `posting_date`).
> - POS Upload Item quantity field is **`quantity`** (not `qty`); code field is **`ref_code`**.
> - Upload `item_name` (customer's loose description) legitimately differs from the DN's
>   matched `item_name` — that naming gap is *why* the mapping is needed, not a join error.

---

## 3. Status classification

One row per `(upload line, mapped item_code)`. Status is computed in Python:

| Status | Condition | Row colour |
|---|---|---|
| **New** | has `ref_code`, DN line found (`item_code` present), triple **not** in `Item Customer Detail` | green |
| **Already mapped** | the exact triple already exists (hidden unless *Show already-mapped*) | — |
| **No delivery line** | has `ref_code` but the serial join produced no `item_code` | amber |
| **No code** | upload line has no `ref_code` (only shown when *Only coded* is off) | — |

---

## 4. Filters

| Filter | Type | Effect |
|---|---|---|
| POS Upload | MultiSelectList | `pu.name IN (...)` |
| From Date / To Date | Date | `pu.date` range |
| Customer | MultiSelectList → Customer | `dn.customer IN (...)` |
| Customer Group | MultiSelectList → Customer Group | `cust.customer_group IN (...)` |
| Item Group | MultiSelectList → Item Group | `it.item_group IN (...)` |
| Show already-mapped | Check (default off) | when off, hides "Already mapped" rows |
| Only lines with a customer code | Check (default off) | when on, restricts to non-empty `ref_code` (drops "No code") |

> The Customer / Customer Group / Item Group filters match **LEFT-JOINed** columns, so
> selecting any of them implicitly drops rows that have no delivery/item to match against
> ("No code" / "No delivery line" disappear). This is intended when narrowing to a group.
>
> Item Group and Customer Group are **tree (nested-set) doctypes**; these filters match
> the **exact** group only, not descendant groups. Switch to an `lft`/`rgt` range match if
> descendant roll-up is ever required.

---

## 5. Implementation steps (Desk UI, no custom app)

### 5a. Create the Report

1. **New → Report.**
2. **Report Name:** `POS and Delivery Note Item Rate`
3. **Ref DocType:** `POS Upload` · **Report Type:** `Script Report` · **Is Standard:** `No` · **Module:** `Stock`.
4. Leave the **Filters** child table empty — filters are declared in the Client Script's
   `filters` array (which overrides the child table).
5. Paste the script from [§6](#6-report-script-python) into **Query / Script** and **Save**.
6. Add roles under **Roles** as needed.

### 5b. Create the Client Script

1. **New → Client Script.**
2. **Script Type:** `Report` · **Reference Report:** `POS and Delivery Note Item Rate`.
3. Paste the script from [§7](#7-client-script-javascript) and **Save**.

### 5c. Renaming (if ever needed)

The **Report** doctype has `allow_rename` off — there is **no Rename** in its menu. To
rename: **Duplicate** → set the new title on the copy → **Delete** the old report. Then
**you must update two things or the report loses its filters/colouring/banner**:

- the Client Script key `frappe.query_reports["<new title>"]`, and
- the Client Script's **Reference Report** link.

---

## 6. Report Script (Python)

> Paste into **Report → Query / Script**. RestrictedPython sandbox: **no `import`, no
> `.format`** — use f-strings and `frappe.db.sql(query, params, as_dict=True)`; set
> `data = (columns, rows)`.

The deployed source is [`reports/pos-and-delivery-note-item-rate/report_script.py`](https://github.com/asifmohtesham/erp-scripts/tree/main/reports/pos-and-delivery-note-item-rate/report_script.py) in the private `erp-scripts` repository.

---

## 7. Client Script (JavaScript)

> Paste into a **Client Script** with **Script Type = Report** and **Reference Report**
> set to this report. The `frappe.query_reports["..."]` key **must equal the report title
> exactly** or filters, colouring, and the banner will not load.

The deployed source is [`reports/pos-and-delivery-note-item-rate/client_script.js`](https://github.com/asifmohtesham/erp-scripts/tree/main/reports/pos-and-delivery-note-item-rate/client_script.js) in the private `erp-scripts` repository.

---

## 8. Column-freeze colouring — why the MutationObserver

frappe-datatable virtual-scrolls, and **column freeze, sort, resize, and filter all
rebuild cell DOM nodes**, dropping any injected colour classes. An earlier scroll-only
listener repainted on scroll but not on freeze, so colours vanished until the next scroll.
The fix is a single **`MutationObserver` on `.datatable`** observing **`childList`/`subtree`
only** (not `attributes`, so `paint()`'s own `classList` writes cannot retrigger it → no
loop), rAF-debounced, bound once via a `dataset` guard. It repaints on every cell recreation.

---

## 9. Operational gotchas

- **`MAX_JOIN_SIZE`.** Running unfiltered (no POS Upload / date filter and *Only coded* off)
  scans all POS Upload Items across the unindexed `po_no`/serial joins, which can trip
  MariaDB's `MAX_JOIN_SIZE` in a raw `mariadb` CLI session (`SET SQL_BIG_SELECTS = 1` clears
  it). Frappe's own DB session has big-selects on, so the report itself is fine — but keep a
  filter applied for speed.
- **Read-only.** The report never writes. Customer codes are transcribed manually into
  `Item` → **Customer Items** after review. (A System-Manager Apply button was designed and
  then dropped by request.)
- **Sandbox.** No `import`, no `.format()`; parameterise every value (`%(name)s`) — never
  f-string user input into SQL.

---

## 10. Related backend context

- The initial `POS Upload Item.ref_code` values were themselves backfilled from a customer-code
  CSV via a one-off `bench console` script, matching strictly by **voucher + line `idx`**
  (not by item — the same `item_name` can carry different codes per line). 419 values written,
  0 mismatches.
- Reference data model: `Item Customer Detail` (child of Item) — link field is `customer_name`,
  code field is `ref_code`; **multiple rows per (Item, Customer)** are allowed.

---

## Mobile: Group-by

The Flutter report screen supports client-side two-level grouping (primary +
optional secondary) over the fetched rows — by Item Group, Customer, Customer
Group, POS Item Name, or Rate. Headers show value + row count + summed POS/DN
qty (qty only, never rate). Logic lives in
`lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart` (pure,
unit-tested); the server report and status are unchanged.
