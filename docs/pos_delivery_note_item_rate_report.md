# POS and Delivery Note Item Rate — Report Implementation Guide

> **Scope:** This is a **backend (ERPNext Desk) artifact**, not Flutter code. It
> lives on the Frappe instance (`erp.multimax.cloud`) as a no-app **Script Report**
> plus a **Client Script**. Because Desk artifacts are not under source control,
> this document is the canonical, reproducible source — recreate the report from
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

```python
# Report Script for "POS and Delivery Note Item Rate"
# (formerly "Customer Code Backfill (POS Upload to Delivery Note)")
# Paste into Report -> Script. Sandbox: no import, no .format; use f-strings;
# set data = (columns, rows). POS Upload date field is `date`.
#
# Grain: one row per (upload line, mapped item_code).
# Status:
#   "No code"          -> upload line has no ref_code (nothing to backfill)
#   "No delivery line" -> serial join found no item_code (cannot map)
#   "Already mapped"   -> exact triple (item_code, customer, ref_code) already in Item Customer Detail
#   "New"              -> a triple to write

pos_uploads = filters.get("pos_upload") or []
from_date = filters.get("from_date")
to_date = filters.get("to_date")
show_mapped = filters.get("show_mapped")
only_coded = filters.get("only_coded")
item_groups = filters.get("item_group") or []
customers = filters.get("customer") or []
customer_groups = filters.get("customer_group") or []

# Default: include every upload line (ref_code NULL or not). Toggle on to keep
# only lines that carry a customer code.
conds = ["1 = 1"]
params = {}

if only_coded:
    conds.append("pui.ref_code IS NOT NULL")
    conds.append("pui.ref_code != ''")

if pos_uploads:
    keys = []
    for i, up in enumerate(pos_uploads):
        k = f"pu{i}"
        keys.append(f"%({k})s")
        params[k] = up
    conds.append(f"pu.name IN ({', '.join(keys)})")

if from_date:
    conds.append("pu.`date` >= %(from_date)s")
    params["from_date"] = from_date
if to_date:
    conds.append("pu.`date` <= %(to_date)s")
    params["to_date"] = to_date

# These filter on LEFT-JOINed columns, so selecting one implicitly hides
# rows with no matching delivery/item (nothing to filter against).
if customers:
    keys = []
    for i, c in enumerate(customers):
        k = f"cust{i}"
        keys.append(f"%({k})s")
        params[k] = c
    conds.append(f"dn.customer IN ({', '.join(keys)})")
if customer_groups:
    keys = []
    for i, cg in enumerate(customer_groups):
        k = f"cg{i}"
        keys.append(f"%({k})s")
        params[k] = cg
    conds.append(f"cust.customer_group IN ({', '.join(keys)})")
if item_groups:
    keys = []
    for i, ig in enumerate(item_groups):
        k = f"ig{i}"
        keys.append(f"%({k})s")
        params[k] = ig
    conds.append(f"it.item_group IN ({', '.join(keys)})")

where = " AND ".join(conds)

rows = frappe.db.sql(f"""
    SELECT
        pu.name        AS pos_upload,
        pui.idx        AS idx,
        pui.ref_code   AS ref_code,
        pui.item_name  AS upload_item,
        pui.quantity   AS upload_qty,
        pui.rate       AS upload_rate,
        dn.name          AS dn_name,
        dn.customer      AS customer,
        cust.customer_group AS customer_group,
        dni.item_code    AS item_code,
        it.item_group    AS item_group,
        dni.item_name    AS dn_item,
        dni.qty          AS dn_qty,
        icd.name         AS icd_row
    FROM `tabPOS Upload Item` pui
    JOIN `tabPOS Upload` pu ON pui.parent = pu.name
    LEFT JOIN `tabDelivery Note` dn
           ON dn.po_no = pu.name AND dn.docstatus = 1
    LEFT JOIN `tabCustomer` cust
           ON cust.name = dn.customer
    LEFT JOIN `tabDelivery Note Item` dni
           ON dni.parent = dn.name
          AND dni.custom_invoice_serial_number = pui.idx
    LEFT JOIN `tabItem` it
           ON it.name = dni.item_code
    LEFT JOIN `tabItem Customer Detail` icd
           ON icd.parent = dni.item_code
          AND icd.customer_name = dn.customer
          AND icd.ref_code = pui.ref_code
    WHERE {where}
    ORDER BY pu.name, pui.idx, dni.item_code
""", params, as_dict=True)

out = []
for r in rows:
    if not r.get("ref_code"):
        r["status"] = "No code"
    elif not r.get("item_code"):
        r["status"] = "No delivery line"
    elif r.get("icd_row"):
        r["status"] = "Already mapped"
    else:
        r["status"] = "New"
    if r["status"] == "Already mapped" and not show_mapped:
        continue
    out.append(r)
rows = out

columns = [
    {"label": "Status", "fieldname": "status", "fieldtype": "Data", "width": 130},
    {"label": "Customer Code", "fieldname": "ref_code", "fieldtype": "Data", "width": 130},
    {"label": "Item Code", "fieldname": "item_code", "fieldtype": "Link", "options": "Item", "width": 130},
    {"label": "Item Group", "fieldname": "item_group", "fieldtype": "Link", "options": "Item Group", "width": 140},
    {"label": "DN Item Name", "fieldname": "dn_item", "fieldtype": "Data", "width": 200},
    {"label": "POS Item Name", "fieldname": "upload_item", "fieldtype": "Data", "width": 200},
    {"label": "Customer", "fieldname": "customer", "fieldtype": "Link", "options": "Customer", "width": 170},
    {"label": "Customer Group", "fieldname": "customer_group", "fieldtype": "Link", "options": "Customer Group", "width": 150},
    {"label": "POS Qty", "fieldname": "upload_qty", "fieldtype": "Float", "width": 90},
    {"label": "POS Rate", "fieldname": "upload_rate", "fieldtype": "Currency", "width": 100},
    {"label": "DN Qty", "fieldname": "dn_qty", "fieldtype": "Float", "width": 80},
    {"label": "DN #", "fieldname": "dn_name", "fieldtype": "Link", "options": "Delivery Note", "width": 140},
    {"label": "POS #", "fieldname": "pos_upload", "fieldtype": "Link", "options": "POS Upload", "width": 140},
    {"label": "Invoice Serial Number", "fieldname": "idx", "fieldtype": "Int", "width": 100},
]

data = (columns, rows)
```

---

## 7. Client Script (JavaScript)

> Paste into a **Client Script** with **Script Type = Report** and **Reference Report**
> set to this report. The `frappe.query_reports["..."]` key **must equal the report title
> exactly** or filters, colouring, and the banner will not load.

```javascript
// Client Script for report "POS and Delivery Note Item Rate"
// Create: New Client Script -> Script Type "Report", Reference Report = this report.
// Provides: multi-select + date + show_mapped filters, row coloring, summary banner.
//
// NOTE: the key below MUST match the report's title exactly. If you rename the
// report in Desk, update this string (and the Client Script's Reference Report
// link) to the new title, or the filters/coloring/banner stop loading.

frappe.query_reports["POS and Delivery Note Item Rate"] = {
    filters: [
        {
            fieldname: "pos_upload",
            label: __("POS Upload"),
            fieldtype: "MultiSelectList",
            get_data: (txt) => frappe.db.get_link_options("POS Upload", txt),
        },
        { fieldname: "from_date", label: __("From Date"), fieldtype: "Date" },
        { fieldname: "to_date", label: __("To Date"), fieldtype: "Date" },
        {
            fieldname: "customer",
            label: __("Customer"),
            fieldtype: "MultiSelectList",
            get_data: (txt) => frappe.db.get_link_options("Customer", txt),
        },
        {
            fieldname: "customer_group",
            label: __("Customer Group"),
            fieldtype: "MultiSelectList",
            get_data: (txt) => frappe.db.get_link_options("Customer Group", txt),
        },
        {
            fieldname: "item_group",
            label: __("Item Group"),
            fieldtype: "MultiSelectList",
            get_data: (txt) => frappe.db.get_link_options("Item Group", txt),
        },
        { fieldname: "show_mapped", label: __("Show already-mapped"), fieldtype: "Check", default: 0 },
        { fieldname: "only_coded", label: __("Only lines with a customer code"), fieldtype: "Check", default: 0 },
    ],

    after_datatable_render() {
        const rr = frappe.query_report;

        // --- row coloring: New = green (actionable), No delivery line = amber (cannot map) ---
        const clsFor = (status) =>
            status === "New" ? "dt-cell--ccb-new"
            : status === "No delivery line" ? "dt-cell--ccb-nodn"
            : null;

        const paint = () => {
            document
                .querySelectorAll(".dt-cell.dt-cell--ccb-new, .dt-cell.dt-cell--ccb-nodn")
                .forEach((c) => c.classList.remove("dt-cell--ccb-new", "dt-cell--ccb-nodn"));
            (rr.data || []).forEach((r, i) => {
                if (!r || !r.status) return;
                const cls = clsFor(r.status);
                if (!cls) return;
                document
                    .querySelectorAll('.dt-cell[data-row-index="' + i + '"]')
                    .forEach((c) => c.classList.add(cls));
            });
        };
        paint();

        // Re-apply whenever the datatable recreates cells — scroll, column freeze,
        // sort, resize, or filter all rebuild DOM nodes. Observe childList/subtree
        // only (NOT attributes), so paint()'s class changes can't retrigger it.
        const dt = document.querySelector(".datatable");
        if (dt && !dt.dataset.ccbObserver) {
            dt.dataset.ccbObserver = "1";
            let raf = 0;
            const obs = new MutationObserver(() => {
                if (raf) return;
                raf = requestAnimationFrame(() => {
                    raf = 0;
                    paint();
                });
            });
            obs.observe(dt, { childList: true, subtree: true });
        }

        // --- summary banner ---
        const data = rr.data || [];
        const nNew = data.filter((r) => r.status === "New").length;
        const nNoDn = data.filter((r) => r.status === "No delivery line").length;
        const nNoCode = data.filter((r) => r.status === "No code").length;
        let el = document.getElementById("ccb-banner");
        if (!el) {
            el = document.createElement("div");
            el.id = "ccb-banner";
            el.style.cssText =
                "margin:6px 0;padding:6px 10px;border-radius:4px;background:#f4f5f6;font-size:12px;";
            const anchor = document.querySelector(".report-wrapper") || (rr.$report && rr.$report[0]);
            if (anchor) anchor.prepend(el);
        }
        el.innerHTML =
            "<b>" + nNew + "</b> new mapping(s) to apply &nbsp;|&nbsp; <b>" +
            nNoDn + "</b> line(s) with no delivery (cannot map) &nbsp;|&nbsp; <b>" +
            nNoCode + "</b> line(s) with no customer code";
    },
};

// coloring CSS (green for New, amber for No delivery line)
(function () {
    const s = document.createElement("style");
    s.textContent =
        ".datatable .dt-cell.dt-cell--ccb-new{background:#e6f4ea !important;}" +
        ".datatable .dt-cell.dt-cell--ccb-nodn{background:#fff3cd !important;}";
    document.head.appendChild(s);
})();
```

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
