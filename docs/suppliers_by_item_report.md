# Suppliers by Item — Report Implementation Guide

> **Scope.** This guide describes the v7 contract of the read-only ERPNext Desk
> Script Report `Suppliers by Item`. The Python and JavaScript below match the
> sources deployed on `erp.multimax.cloud` and `erp-testing.multimax.cloud`,
> including the v7.1 fix for nested draft BOMs in Frappe's script sandbox.

The report finds suppliers linked to an enabled item. Evidence sources include
Item Supplier, Item Default, buying Item Price, Batch and submitted Purchase
Orders, Purchase Receipts, Purchase Invoices, Supplier Quotations and Requests
for Quotation. Draft Purchase Orders also supply evidence by default. Each
supplier row represents one item and supplier pair, with its evidence sources,
status, order quantities, receipt history and latest qualifying rate.

## 1. Prerequisites and access

| Requirement | Detail |
|---|---|
| Server-side scripts | The site must already have `server_script_enabled` for custom Script Reports. |
| Report roles | **Purchase User** and **Stock User**. Either role can qualify. Frappe also checks report access through the reference DocType, Purchase Receipt. |
| Desk setup | A System Manager can create or edit the Report record. |
| App access | The drawer entry uses the signed-in session's roles. When the User document omits roles on v16, the shared session code can recover them from the signed-in user's Desk boot data. |

## 2. Filters

| Filter | Field | Type | Effect |
|---|---|---|---|
| Items | `items` | MultiSelectList → Item | Matches the selected item codes. |
| Variant Of | `variant_of` | MultiSelectList → Item | Offers template items and matches their variants. Selecting both Items and Variant Of returns the union. |
| Suppliers | `suppliers` | MultiSelectList → Supplier | Matches items with evidence for these suppliers. BOM expansion also matches through components at every shown depth. A match retains the full tree and marks each occurrence of a selected supplier with `matched_supplier: 1`. |
| Warehouses | `warehouses` | MultiSelectList → Warehouse | Scopes Balance Qty, Projected Qty, Reorder Level and Reorder Qty to the selected warehouses and descendants of selected groups. An empty selection uses all warehouses. Supplier evidence and procurement history keep their full warehouse scope. |
| Include Draft Purchase Orders | `include_drafts` | Check | Defaults to `1` (on). Includes draft Purchase Orders and batches linked to them as supplier evidence, Draft Order Qty, and active draft BOMs when BOM expansion is enabled. Set to `0` to exclude those drafts. |
| Expand BOM components | `expand_bom` | Check | Defaults to `0` (off) for the v6 result. Set to `1` to add active BOMs and their components. |

With Suppliers empty and Items or Variant Of set, every matching enabled item
is retained, including items without suppliers. With all three selection
filters empty, an enabled item qualifies if it has supplier evidence or, while
BOM expansion is on, an active BOM covered by the drafts setting. Disabled and
on-hold suppliers remain eligible. Warehouse selection scopes the stock columns
without changing the items, BOMs, components, or suppliers shown.

Batches linked to submitted Purchase Orders use `Batch`. With drafts enabled,
draft Purchase Orders use `Purchase Order (Draft)` and batches linked to one
use `Batch (draft PO)`. Batches linked to a cancelled Purchase Order use
`Batch (cancelled PO)`. Batches with an empty or missing Purchase Order link use
`Batch (no PO)`. Both of these batch sources are included with either drafts setting.

## 3. Columns

| Column | Field | Value |
|---|---|---|
| Item / Supplier | `tree_label` | Item, component, or Supplier link, BOM group label, or placeholder label. |
| Item Name | `item_name` | Item, component, or template name. |
| BOM Qty per Unit | `bom_qty_per_unit` | Shown with BOM expansion. Component stock quantity divided by the parent BOM's output quantity. |
| Balance Qty | `balance_qty` | Current quantity in Stock UOM, scoped by Warehouses. |
| Projected Qty | `projected_qty` | Current projected stock from Bin in stock UOM, scoped by Warehouses. |
| Reorder Level | `reorder_level` | Sum of warehouse reorder levels from Item Reorder, scoped by Warehouses. |
| Reorder Qty | `reorder_qty` | Sum of configured reorder quantities from Item Reorder when supplied, scoped by Warehouses. |
| Supplier Name | `supplier_name` | Display name for the supplier. |
| Supplier Status | `supplier_status` | `Active`, `Disabled` or `On Hold`. The on-hold label includes the hold type in parentheses and an `until <release_date>` suffix when available. |
| Supplier Part Number | `supplier_part_number` | First populated value by source priority, then recency within that source. The priority is Item Supplier, Purchase Order, Supplier Quotation, Purchase Receipt. |
| Sources | `sources` | Distinct supplier evidence labels, including the draft and batch labels described above. |
| Open Order Qty | `open_order_qty` | Remaining quantity in stock UOM on submitted Purchase Orders with a status other than Closed or Completed. Each line contributes `max(qty - received_qty, 0) * conversion_factor`. |
| Draft Order Qty | `draft_order_qty` | Same remaining quantity calculation for draft Purchase Orders when drafts are included. |
| Lead Time (Days) | `lead_time_days` | Average days from Purchase Order transaction date to Purchase Receipt posting date, reported to one decimal place. Uses submitted receipt lines linked to a submitted order for the same item and supplier. Blank when no lines qualify. |
| Lead Time Receipts | `lead_time_receipts` | Number of receipt lines used for the lead time average. |
| PO Count | `po_count` | Distinct submitted Purchase Orders for the item and supplier. |
| Receipt Count | `receipt_count` | Distinct submitted Purchase Receipts for the item and supplier. |
| Last Purchase Date | `last_purchase_date` | Latest positive-quantity receipt event date. |
| Last Purchase Receipt | `last_purchase_receipt` | Link to the receipt when it supplied the latest positive-quantity event. |
| Last Rate | `last_rate` | Latest positive rate from a receipt event, with the latest positive rate from a submitted Purchase Order as fallback. Blank when both are absent. |
| Rate Source | `rate_source` | DocType of the selected rate, Purchase Receipt, Purchase Invoice or Purchase Order. |
| Rate Date | `rate_date` | Posting or transaction date of the selected rate. |
| Rate Document | `rate_document` | Dynamic Link keyed by Rate Source. |
| Currency | `currency` | Currency of the selected rate. |
| Rate UOM | `rate_uom` | Transaction UOM of the selected rate. |
| Total Qty Received | `total_qty_received` | Net quantity from receipt events in stock UOM, including returns. |
| Stock UOM | `stock_uom` | Item stock UOM, blank on template rows with mixed units. |
| Last PO Date | `last_po_date` | Latest submitted Purchase Order date for the item and supplier pair, independent of the rate source. |
| Supplier Count | `supplier_count` | Number of suppliers linked to an item or component, or the number of distinct suppliers linked to a template's variants. |

Item rows carry Balance Qty, Projected Qty, Reorder Level and Reorder Qty.
Component rows carry Balance Qty and Projected Qty under the same warehouse scope.
A template sums stock quantities across shown variants that share one Stock UOM.
Mixed-UOM templates, supplier rows and placeholder rows leave the stock quantities
blank. Item rows sum Total Qty Received, Open Order Qty and Draft Order Qty across
their own suppliers. Template counts and quantities also exclude BOM components.

Receipt events include submitted Purchase Receipts and stock-updating Purchase
Invoices that qualify as independent receipts. The script excludes invoice
lines that reference a receipt or are already covered by a submitted receipt
line. It selects the rate independently of net received quantity, so an item
with zero net quantity after returns can still have a receipt rate.

## 4. Tree and row contract

Rows arrive parent-first. `node_id` and `parent_id` identify tree positions.
Template groups and standalone items start at `indent: 0`. Variants under an
enabled template use `indent: 1`. Each child increments `indent` by one.
Consumers should use `row_type` first and fall back to the `node_id` prefix for
older results that omit it. Read record identities from `item_code`, `supplier`,
`bom_no`, or `template` as applicable, treating node IDs as opaque tree keys.

| `row_type` | Parent | Fields |
|---|---|---|
| `template` | None | `template`, `link_doctype: Item` |
| `item` | Template if grouped | `item_code`, `link_doctype: Item` |
| `supplier` | Item or component | `item_code`, `supplier`, `link_doctype: Supplier`, `is_placeholder: 0`, `matched_supplier` |
| `placeholder` | Item or component | `item_code`, `is_placeholder: 1`, `tree_label: No supplier recorded` |
| `bom` | Item or component | `bom_no`, `bom_is_default` (0/1), `bom_status` (`Submitted` or `Draft`), `component_count`, `component_supplier_count`, `tree_label` |
| `component` | BOM | `item_code`, `item_name`, `bom_no` (parent BOM), `bom_item_idx`, `bom_item_id`, `bom_qty_per_unit`, `stock_uom`, `include_in_manufacturing` (0/1), `used_in_bom_count`, `balance_qty`, `projected_qty`, `last_purchase_date`, `supplier_count` |

An item or component lists its own suppliers first, or one **No supplier
recorded** placeholder, then its BOM groups. The default submitted BOM comes
first, followed by other submitted BOMs by name, then active draft BOMs by name
when drafts are included. Inactive and cancelled BOMs are excluded. A BOM row's
`component_count` counts its direct lines, including duplicate items, and
`component_supplier_count` counts distinct suppliers across the full branch.
`used_in_bom_count` counts distinct active BOMs using the component under the
current drafts setting. Expansion stops at a repeated item on the current path
(`bom_cycle: 1`) or after 10 BOM levels (`bom_depth_limit: 1` when the component
has a further qualifying BOM).

Top-level keys retain the v6 formats `template:<template_code>`,
`item:<item_code>`, `supplier:<len>:<item_code>:<supplier>`, and
`none:<len>:<item_code>`, where `<len>` is the length of the item code. BOM keys
and supplier row keys inside BOM branches include the parent node and their own
key. Component keys also include the BOM line position and ID so repeated
items each have a unique tree position. Component placeholder keys use `none:<component_node>`.
BOM groups and every descendant carry `is_component: 1`. With expansion on,
top-level rows carry `is_component: 0`. With expansion off, rows preserve the
v6 payload and omit `is_component`.

For example, the production result for `items=["3000339"]` with expansion on
includes `BOM-3000339-001` under Item `3000339`, after the item's supplier
placeholder. Its two components are `2002999` (JOAP) and `2002906` (PING HAI),
each with a quantity of 360 Nos per unit. With drafts enabled, Item `3000338`
has `BOM-3000338-001` with a component `3000281` that expands draft
`BOM-3000281-001` to show `1004879` (EDGE) and `1004722` (BOVIS).

## 5. App screens

- **Buying → Reports → Suppliers by Item** opens the full report with the
  standard report header. Use **+ Filter** or the filter icon to open the
  filter sheet. **Include Draft Purchase Orders** defaults to on and **Expand
  BOM components** defaults to off. Its helper reads “Shows what each item
  is made from and who supplies those components.” The **View** chip opens
  the grouping, sort, direction, **Expand all** and **Collapse all** controls.
  The Fields icon opens **Fields**.

  **Item** grouping follows the **Item / Supplier** tree. Each template appears
  above its variants, including a template with one returned variant. Items
  without a template appear at the root. Within each item, suppliers or the
  **No supplier recorded** placeholder precede any BOM groups.
  Item and BOM component rows align **Balance Qty** and **Supplier Count**.
  Supplier rows compare **Last Purchase Date** and can expand to show purchase
  history and evidence. **Lead Time (Days)**, **Lead Time Receipts** and
  **Receipt Count** have separate Fields switches. Positive order quantities
  can show **Open Order Qty** and **Draft Order Qty** badges. **Supplier Status**
  shows **Disabled** and **On Hold**.

  **Supplier** grouping shows an item under each supplier linked to that
  item, with their pair's **Last Purchase Date** and evidence. BOM components
  can also appear with their owning item and full BOM path. **No supplier
  recorded** groups items with no supplier of their own, including items
  whose BOM components have suppliers. Items in both kinds of groups can
  reveal their loaded BOM branches. **View** controls the **Items** and
  **BOM components** group counts. Component matches retain their BOM path.

  Both groupings offer **Balance Qty**, **Supplier Count** and **Last Purchase
  Date** in either direction. The default is **Item**, **Balance Qty** and
  **High to low**. **Balance Qty** is compared within each **Stock UOM**, with
  unavailable amounts last. For **Last Purchase Date**, **Item** grouping uses
  the latest date for the suppliers linked to the item or its variants.
  **Supplier** grouping uses the date for the displayed item or BOM component
  and supplier pair. View choices are saved per ERP site and user. Fields reset leaves the
  saved View selection in place. Failed saves keep the current choices for the
  session and offer **Retry**.

  **Search within results** matches words across a single item, template,
  supplier or BOM trail and opens the matching branches locally. The **Items** search count includes each matching
  owner once. Both groupings retain its other suppliers. Changing grouping
  keeps the query and reveals the matching branches in the new view. Clearing
  the query restores the active grouping's expansion and reading position.
  Search, expansion and position belong to the open report.

  **Fields** controls optional row details and badges. **View** controls the
  search match count. **Currency** and **Rate UOM** keep their selections
  while **Last Rate** is off. Choices apply immediately and are saved per
  ERP site and signed-in user. The first eligible site claims existing
  user-only choices. **Reset to defaults** restores the original selection.
  The report keeps session choices and offers **Retry** if saving fails.
  **Item / Supplier**, **No supplier recorded**, navigation and the
  **End of list** marker remain available with every Field off.

  **Scan barcode** is the report's floating button (the camera) and also
  listens to the hardware scanner while the report is the screen on top; a
  filter sheet, the camera or another screen above it takes the scanner. It
  is a floating button because a third header icon would move Fields and
  Refresh into the header's More menu on a phone. A scan looks the Item up
  with `ScanService.resolveItemBarcode` (EAN-8, registered barcode or Batch)
  and runs the report for it: a variant selects its template in **Variant
  Of**, any other Item selects itself in **Items**, as from a shared photo.
  The scan replaces both of those filters and keeps **Suppliers**,
  **Warehouses** and the two switches. An unmatched code shows "No Item
  matches this barcode: <code>" and a failed lookup "Could not look up this
  barcode. Try again."; both leave the results and filters as they were. A
  scan made while the report is loading is dropped. The button is hidden
  while the expanded header reaches it (a small screen with many filter
  chips), like every list screen's floating button; the hardware scanner
  still works then.
  [Report screen](../lib/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_screen.dart)
The Item form has no Suppliers card, because the Item DocType has no supplier
field. Supplier lookups use this report.

The report screen uses `ApiProvider.runSuppliersByItem`, which sends a form-encoded POST to
`/api/method/frappe.desk.query_report.run` with `report_name=Suppliers by Item`,
a JSON `filters` field, `ignore_prepared_report=true` and
`are_default_filters=false`. The JSON carries selections from `items`,
`variant_of`, `suppliers` and `warehouses`, plus numeric `include_drafts` and
`expand_bom` (`1` on, `0` off). The parser reads the keyed rows in
`message.result` and accepts missing BOM fields on v6 and older responses.
[API provider](../lib/app/data/providers/api_provider.dart)

## 6. Recreate the Report in Desk

1. Open **Report → New** and set the fields below.
2. Leave the **Columns** and **Filters** child tables empty. The Python script
   supplies the columns and the JavaScript supplies the filters.
3. Paste the Python into **Report Script** (`report_script`) and the
   JavaScript into **JavaScript** (`javascript`) on the same Report record.
4. Add the two listed roles and save.

| Report field | Value |
|---|---|
| Report Name | `Suppliers by Item` |
| Ref DocType | `Purchase Receipt` |
| Report Type | `Script Report` |
| Is Standard | `No` |
| Module | `Buying` |
| Disabled | Off |
| Prepared Report | Off |
| Add Total Row | Off |
| Roles | `Purchase User`, `Stock User` |

## 7. Report Script (Python)

Deployed v7 source (Report field `report_script`).

```python
def build_report(filters):
    def selected_values(fieldname):
        values = filters.get(fieldname)
        if isinstance(values, str):
            values = json.loads(values) if values.lstrip().startswith("[") else [values]
        return tuple(str(value) for value in (values or []) if value is not None and value != "")

    items = selected_values("items")
    templates = selected_values("variant_of")
    suppliers = selected_values("suppliers")
    warehouses = selected_values("warehouses")
    include_drafts = int(filters.get("include_drafts") not in (0, "0"))
    expand_bom = int(filters.get("expand_bom") in (1, "1"))
    selected_items = int(bool(items or templates))

    boms_by_item = {}
    bom_lines = {}
    used_in_boms = {}
    if expand_bom:
        bom_records = frappe.db.sql(
            """
            SELECT b.name AS bom_no, b.item AS output_item, b.is_default, b.docstatus,
                   d.name AS line_id, d.idx, d.item_code, d.item_name, d.stock_uom,
                   d.stock_qty / NULLIF(b.quantity, 0) AS qty_per_unit,
                   COALESCE(d.include_item_in_manufacturing, 0) AS include_in_manufacturing
            FROM `tabBOM` b
            LEFT JOIN `tabBOM Item` d ON d.parent = b.name
                AND d.parenttype = 'BOM' AND d.parentfield = 'items'
            WHERE b.is_active = 1 AND (b.docstatus = 1 OR (%(include_drafts)s = 1 AND b.docstatus = 0))
            ORDER BY b.item, b.docstatus DESC,
                     CASE WHEN b.docstatus = 1 THEN b.is_default ELSE 0 END DESC,
                     b.name, d.idx, d.name
            """,
            {"include_drafts": include_drafts},
            as_dict=True,
        )
        for record in bom_records:
            if record.bom_no not in bom_lines:
                bom_lines[record.bom_no] = []
                boms_by_item.setdefault(record.output_item, []).append(record)
            if record.line_id is not None:
                bom_lines[record.bom_no].append(record)
                used_in_boms.setdefault(record.item_code, set()).add(record.bom_no)

    parameters = {
        "selected_items": selected_items,
        "items": items or (None,),
        "templates": templates or (None,),
        "by_supplier": int(bool(suppliers)),
        "suppliers": suppliers or (None,),
        "by_warehouse": int(bool(warehouses)),
        "warehouses": warehouses or (None,),
        "include_drafts": include_drafts,
        "expand_bom": expand_bom,
        "bom_items": tuple(boms_by_item) or (None,),
        "component_items": tuple(used_in_boms) or (None,),
    }

    rows = frappe.db.sql(
        """
        WITH warehouse_scope AS (
            SELECT name FROM `tabWarehouse` WHERE name IN %(warehouses)s
            UNION
            SELECT w.name
            FROM `tabWarehouse` selected
            JOIN `tabWarehouse` w ON w.lft > selected.lft AND w.rgt < selected.rgt
            WHERE selected.name IN %(warehouses)s AND selected.is_group = 1
        ),
        target AS (
            SELECT i.name AS item_code, i.item_name, i.stock_uom,
                   CASE WHEN t.disabled = 0 THEN t.name END AS template_code,
                   t.item_name AS template_name,
                   (i.disabled = 0 AND (%(selected_items)s = 0 OR i.name IN %(items)s
                       OR i.variant_of IN %(templates)s)) AS is_top_level
            FROM `tabItem` i
            LEFT JOIN `tabItem` t ON t.name = i.variant_of AND t.has_variants = 1
            WHERE (i.disabled = 0
              AND (%(selected_items)s = 0 OR i.name IN %(items)s OR i.variant_of IN %(templates)s))
               OR i.name IN %(component_items)s
        ),
        balances AS (
            SELECT b.item_code, SUM(b.actual_qty) AS balance_qty, SUM(b.projected_qty) AS projected_qty
            FROM `tabBin` b
            JOIN target t ON t.item_code = b.item_code
            WHERE %(by_warehouse)s = 0 OR b.warehouse IN (SELECT name FROM warehouse_scope)
            GROUP BY b.item_code
        ),
        reorder_levels AS (
            SELECT r.parent AS item_code, SUM(r.warehouse_reorder_level) AS reorder_level,
                   SUM(r.warehouse_reorder_qty) AS reorder_qty
            FROM `tabItem Reorder` r
            JOIN target t ON t.item_code = r.parent
            WHERE r.parenttype = 'Item' AND r.parentfield = 'reorder_levels'
              AND (%(by_warehouse)s = 0 OR r.warehouse IN (SELECT name FROM warehouse_scope))
            GROUP BY r.parent
        ),
        item_suppliers AS (
            SELECT s.parent AS item_code, s.supplier, s.supplier_part_no,
                   s.creation, s.name, s.idx
            FROM `tabItem Supplier` s
            JOIN target t ON t.item_code = s.parent
            WHERE s.parenttype = 'Item'
              AND s.parentfield = 'supplier_items' AND s.supplier <> ''
        ),
        orders AS (
            SELECT d.item_code, h.supplier, h.transaction_date, h.creation,
                   h.name AS voucher, d.supplier_part_no, d.idx, d.name AS line_id,
                   h.currency, d.rate, d.uom, h.docstatus, h.status,
                   GREATEST(d.qty - COALESCE(d.received_qty, 0), 0) * d.conversion_factor AS remaining_qty
            FROM `tabPurchase Order Item` d
            JOIN `tabPurchase Order` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE (h.docstatus = 1 OR (%(include_drafts)s = 1 AND h.docstatus = 0))
              AND h.supplier <> ''
        ),
        receipts AS (
            SELECT d.item_code, h.supplier, h.name AS voucher, d.name AS line_id, d.idx,
                   h.posting_date, h.posting_time, h.currency, d.rate, d.uom, d.stock_qty,
                   h.creation, d.supplier_part_no, d.purchase_order, d.purchase_order_item
            FROM `tabPurchase Receipt Item` d
            JOIN `tabPurchase Receipt` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND h.supplier <> ''
        ),
        invoices AS (
            SELECT d.item_code, h.supplier, h.name AS voucher, d.name AS line_id, d.idx,
                   h.posting_date, h.posting_time, h.currency, d.rate, d.uom, d.stock_qty,
                   h.update_stock, d.purchase_receipt, d.pr_detail
            FROM `tabPurchase Invoice Item` d
            JOIN `tabPurchase Invoice` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND h.supplier <> ''
        ),
        quotations AS (
            SELECT d.item_code, h.supplier, h.transaction_date, h.creation,
                   h.name AS voucher, d.supplier_part_no, d.idx, d.name AS line_id
            FROM `tabSupplier Quotation Item` d
            JOIN `tabSupplier Quotation` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND h.supplier <> ''
        ),
        batch_suppliers AS (
            SELECT b.item AS item_code, COALESCE(supplier_id.name, supplier_label.name) AS supplier,
                   CASE h.docstatus
                       WHEN 1 THEN 'Batch'
                       WHEN 0 THEN 'Batch (draft PO)'
                       WHEN 2 THEN 'Batch (cancelled PO)'
                       ELSE 'Batch (no PO)'
                   END AS source
            FROM `tabBatch` b
            JOIN target t ON t.item_code = b.item
            LEFT JOIN `tabPurchase Order` h ON h.name = b.custom_purchase_order
            LEFT JOIN `tabSupplier` supplier_id ON supplier_id.name = TRIM(b.custom_supplier_name)
            LEFT JOIN `tabSupplier` supplier_label ON supplier_id.name IS NULL
                AND supplier_label.supplier_name = TRIM(b.custom_supplier_name)
            WHERE b.docstatus <> 2 AND TRIM(b.custom_supplier_name) <> ''
              AND (supplier_id.name IS NOT NULL OR supplier_label.name IS NOT NULL)
              AND (%(include_drafts)s = 1 OR h.docstatus IS NULL OR h.docstatus <> 0)
        ),
        links AS (
            SELECT item_code, supplier, 'Item Supplier' AS source FROM item_suppliers
            UNION ALL
            SELECT d.parent, d.default_supplier, 'Item Default'
            FROM `tabItem Default` d
            JOIN target t ON t.item_code = d.parent
            WHERE d.parenttype = 'Item'
              AND d.parentfield = 'item_defaults' AND d.default_supplier <> ''
            UNION ALL
            SELECT p.item_code, p.supplier, 'Item Price'
            FROM `tabItem Price` p
            JOIN target t ON t.item_code = p.item_code
            WHERE p.buying = 1 AND p.supplier <> ''
            UNION ALL
            SELECT item_code, supplier,
                   CASE WHEN docstatus = 0 THEN 'Purchase Order (Draft)' ELSE 'Purchase Order' END
            FROM orders
            UNION ALL SELECT item_code, supplier, 'Purchase Receipt' FROM receipts
            UNION ALL SELECT item_code, supplier, 'Purchase Invoice' FROM invoices
            UNION ALL SELECT item_code, supplier, 'Supplier Quotation' FROM quotations
            UNION ALL
            SELECT d.item_code, s.supplier, 'Request for Quotation'
            FROM `tabRequest for Quotation Item` d
            JOIN `tabRequest for Quotation` h ON h.name = d.parent
            JOIN `tabRequest for Quotation Supplier` s ON s.parent = h.name
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND s.supplier <> ''
            UNION ALL SELECT item_code, supplier, source FROM batch_suppliers
        ),
        part_numbers AS (
            SELECT item_code, supplier, supplier_part_no, 1 AS source_priority,
                   NULL AS transaction_date, NULL AS transaction_time,
                   creation, name AS voucher, idx, name AS line_id
            FROM item_suppliers
            UNION ALL
            SELECT item_code, supplier, supplier_part_no, 2, transaction_date, NULL,
                   creation, voucher, idx, line_id FROM orders WHERE docstatus = 1
            UNION ALL
            SELECT item_code, supplier, supplier_part_no, 3, transaction_date, NULL,
                   creation, voucher, idx, line_id FROM quotations
            UNION ALL
            SELECT item_code, supplier, supplier_part_no, 4, posting_date, posting_time,
                   creation, voucher, idx, line_id FROM receipts
        ),
        ranked_part_numbers AS (
            SELECT item_code, supplier, TRIM(supplier_part_no) AS supplier_part_no,
                   ROW_NUMBER() OVER (PARTITION BY item_code, supplier
                       ORDER BY source_priority, transaction_date DESC, transaction_time DESC,
                                creation DESC, voucher DESC, idx DESC, line_id DESC) AS rn
            FROM part_numbers
            WHERE TRIM(supplier_part_no) <> ''
        ),
        events AS (
            SELECT r.item_code, r.supplier, r.voucher, r.line_id, r.idx, r.posting_date,
                   r.posting_time, r.currency, r.rate, r.uom, r.stock_qty, r.voucher AS receipt,
                   'Purchase Receipt' AS rate_source
            FROM receipts r
            UNION ALL
            SELECT p.item_code, p.supplier, p.voucher, p.line_id, p.idx, p.posting_date,
                   p.posting_time, p.currency, p.rate, p.uom, p.stock_qty, NULL, 'Purchase Invoice'
            FROM invoices p
            WHERE p.update_stock = 1 AND COALESCE(p.purchase_receipt, '') = ''
              AND COALESCE(p.pr_detail, '') = ''
              AND NOT EXISTS (
                  SELECT 1 FROM `tabPurchase Receipt Item` r
                  JOIN `tabPurchase Receipt` h ON h.name = r.parent AND h.docstatus = 1
                  WHERE r.purchase_invoice_item = p.line_id
              )
        ),
        ranked_events AS (
            SELECT e.*, SUM(stock_qty) OVER (PARTITION BY item_code, supplier) AS net_qty,
                   ROW_NUMBER() OVER (PARTITION BY item_code, supplier
                       ORDER BY (stock_qty > 0) DESC, posting_date DESC, posting_time DESC,
                                voucher DESC, idx DESC, line_id DESC) AS rn
            FROM events e
        ),
        rate_candidates AS (
            SELECT item_code, supplier, rate, currency, uom, rate_source,
                   posting_date AS rate_date, posting_time AS rate_time, NULL AS creation,
                   voucher, idx, line_id, 1 AS source_priority
            FROM events WHERE rate > 0
            UNION ALL
            SELECT item_code, supplier, rate, currency, uom, 'Purchase Order',
                   transaction_date, NULL, creation, voucher, idx, line_id, 2
            FROM orders WHERE docstatus = 1 AND rate > 0
        ),
        ranked_rates AS (
            SELECT c.*, ROW_NUMBER() OVER (PARTITION BY item_code, supplier
                       ORDER BY source_priority, rate_date DESC, rate_time DESC,
                                creation DESC, voucher DESC, idx DESC, line_id DESC) AS rn
            FROM rate_candidates c
        ),
        by_supplier AS (
            SELECT item_code, supplier,
                   GROUP_CONCAT(DISTINCT source ORDER BY source SEPARATOR ', ') AS sources
            FROM links GROUP BY item_code, supplier
        ),
        order_stats AS (
            SELECT item_code, supplier,
                   MAX(CASE WHEN docstatus = 1 THEN transaction_date END) AS last_po_date,
                   COUNT(DISTINCT CASE WHEN docstatus = 1 THEN voucher END) AS po_count,
                   SUM(CASE WHEN docstatus = 1 AND COALESCE(status, '') NOT IN ('Closed', 'Completed')
                       THEN remaining_qty ELSE 0 END) AS open_order_qty,
                   SUM(CASE WHEN docstatus = 0 THEN remaining_qty ELSE 0 END) AS draft_order_qty
            FROM orders GROUP BY item_code, supplier
        ),
        receipt_stats AS (
            SELECT r.item_code, r.supplier, COUNT(DISTINCT r.voucher) AS receipt_count,
                   ROUND(AVG(DATEDIFF(r.posting_date, h.transaction_date)), 1) AS lead_time_days,
                   COUNT(DATEDIFF(r.posting_date, h.transaction_date)) AS lead_time_receipts
            FROM receipts r
            LEFT JOIN `tabPurchase Order Item` d ON d.name = r.purchase_order_item
                AND COALESCE(r.purchase_order, '') = ''
            LEFT JOIN `tabPurchase Order` h ON h.name = COALESCE(NULLIF(r.purchase_order, ''), d.parent)
                AND h.docstatus = 1 AND h.supplier = r.supplier
            GROUP BY r.item_code, r.supplier
        )
        SELECT t.item_code, t.item_name, t.stock_uom, t.template_code, t.template_name, t.is_top_level,
               COALESCE(b.balance_qty, 0) AS balance_qty,
               COALESCE(b.projected_qty, 0) AS projected_qty,
               COALESCE(reorder.reorder_level, 0) AS reorder_level,
               COALESCE(reorder.reorder_qty, 0) AS reorder_qty,
               s.supplier, supplier.supplier_name,
               CASE
                   WHEN supplier.name IS NULL THEN NULL
                   WHEN supplier.disabled = 1 THEN 'Disabled'
                   WHEN supplier.on_hold = 1 THEN CONCAT('On Hold',
                       COALESCE(CONCAT(' (', NULLIF(TRIM(supplier.hold_type), ''), ')'), ''),
                       COALESCE(CONCAT(' until ', supplier.release_date), ''))
                   ELSE 'Active'
               END AS supplier_status,
               CASE WHEN s.supplier IN %(suppliers)s THEN 1 ELSE 0 END AS matched_supplier,
               COALESCE(p.supplier_part_no, '') AS supplier_part_number, s.sources,
               COALESCE(o.open_order_qty, 0) AS open_order_qty,
               CASE WHEN %(include_drafts)s = 1 THEN COALESCE(o.draft_order_qty, 0) END AS draft_order_qty,
               stats.lead_time_days, COALESCE(stats.lead_time_receipts, 0) AS lead_time_receipts,
               COALESCE(o.po_count, 0) AS po_count, COALESCE(stats.receipt_count, 0) AS receipt_count,
               CASE WHEN r.stock_qty > 0 THEN r.posting_date END AS last_purchase_date,
               CASE WHEN r.stock_qty > 0 THEN r.receipt END AS last_purchase_receipt,
               rate.rate AS last_rate, rate.rate_source, rate.rate_date, rate.voucher AS rate_document,
               rate.currency, rate.uom AS rate_uom,
               COALESCE(r.net_qty, 0) AS total_qty_received, o.last_po_date
        FROM target t
        LEFT JOIN balances b ON b.item_code = t.item_code
        LEFT JOIN reorder_levels reorder ON reorder.item_code = t.item_code
        LEFT JOIN by_supplier s ON s.item_code = t.item_code
        LEFT JOIN `tabSupplier` supplier ON supplier.name = s.supplier
        LEFT JOIN ranked_part_numbers p
            ON p.item_code = t.item_code AND p.supplier = s.supplier AND p.rn = 1
        LEFT JOIN ranked_events r
            ON r.item_code = t.item_code AND r.supplier = s.supplier AND r.rn = 1
        LEFT JOIN ranked_rates rate
            ON rate.item_code = t.item_code AND rate.supplier = s.supplier AND rate.rn = 1
        LEFT JOIN order_stats o ON o.item_code = t.item_code AND o.supplier = s.supplier
        LEFT JOIN receipt_stats stats ON stats.item_code = t.item_code AND stats.supplier = s.supplier
        WHERE (%(selected_items)s = 1 OR s.supplier IS NOT NULL
               OR t.item_code IN %(bom_items)s OR t.item_code IN %(component_items)s)
          AND (%(expand_bom)s = 1 OR %(by_supplier)s = 0 OR t.item_code IN (
              SELECT item_code FROM links WHERE supplier IN %(suppliers)s
          ))
        ORDER BY COALESCE(t.template_code, t.item_code), t.template_code IS NOT NULL,
                 t.item_code, last_purchase_date DESC, s.supplier
        """,
        parameters,
        as_dict=True,
    )

    fields = [
        ("tree_label", "Item / Supplier", "Dynamic Link", "link_doctype", 390 if expand_bom else 240),
        ("item_name", "Item Name", "Data", None, 220),
        ("balance_qty", "Balance Qty", "Float", None, 110),
        ("projected_qty", "Projected Qty", "Float", None, 115),
        ("reorder_level", "Reorder Level", "Float", None, 115),
        ("reorder_qty", "Reorder Qty", "Float", None, 110),
        ("supplier_name", "Supplier Name", "Data", None, 190),
        ("supplier_status", "Supplier Status", "Data", None, 210),
        ("supplier_part_number", "Supplier Part Number", "Data", None, 165),
        ("sources", "Sources", "Data", None, 260),
        ("open_order_qty", "Open Order Qty", "Float", None, 135),
        ("draft_order_qty", "Draft Order Qty", "Float", None, 135),
        ("lead_time_days", "Lead Time (Days)", "Float", None, 140),
        ("lead_time_receipts", "Lead Time Receipts", "Int", None, 150),
        ("po_count", "PO Count", "Int", None, 100),
        ("receipt_count", "Receipt Count", "Int", None, 115),
        ("last_purchase_date", "Last Purchase Date", "Date", None, 130),
        ("last_purchase_receipt", "Last Purchase Receipt", "Link", "Purchase Receipt", 190),
        ("last_rate", "Last Rate", "Currency", "currency", 110),
        ("rate_source", "Rate Source", "Data", None, 145),
        ("rate_date", "Rate Date", "Date", None, 110),
        ("rate_document", "Rate Document", "Dynamic Link", "rate_source", 190),
        ("currency", "Currency", "Link", "Currency", 95),
        ("rate_uom", "Rate UOM", "Link", "UOM", 100),
        ("total_qty_received", "Total Qty Received", "Float", None, 145),
        ("stock_uom", "Stock UOM", "Link", "UOM", 105),
        ("last_po_date", "Last PO Date", "Date", None, 120),
        ("supplier_count", "Supplier Count", "Int", None, 115),
    ]
    if expand_bom:
        fields.insert(2, ("bom_qty_per_unit", "BOM Qty per Unit", "Float", None, 135))
    columns = []
    for field in fields:
        fieldname = field[0]
        column = {
            "fieldname": fieldname,
            "label": _(field[1]),
            "fieldtype": field[2],
            "options": field[3],
            "width": field[4],
        }
        if fieldname == "balance_qty":
            column["description"] = _(
                "Current stock on hand in stock UOM for the selected warehouses and their descendants, "
                "or all warehouses when none are selected."
            )
        if fieldname == "projected_qty":
            column["description"] = _(
                "Current projected stock in stock UOM for the selected warehouses and their descendants, "
                "or all warehouses when none are selected."
            )
        if fieldname == "sources":
            column["description"] = _(
                "Supplier links from item records, purchase documents, and batches. "
                "Draft purchase orders and their batches are included when the drafts filter is checked."
            )
        if fieldname == "lead_time_days":
            column["precision"] = 1
        columns.append(column)

    def make_placeholder(item_code, node_id, parent_id, indent):
        placeholder = {column["fieldname"]: None for column in columns}
        placeholder.update({
            "node_id": node_id,
            "parent_id": parent_id,
            "row_type": "placeholder",
            "indent": indent,
            "tree_label": _("No supplier recorded"),
            "item_code": item_code,
            "is_placeholder": 1,
        })
        return placeholder

    def make_supplier(row, node_id, parent_id, indent):
        return {
            "node_id": node_id,
            "parent_id": parent_id,
            "row_type": "supplier",
            "indent": indent,
            "is_placeholder": 0,
            "tree_label": row.supplier,
            "link_doctype": "Supplier",
            "item_code": row.item_code,
            "supplier": row.supplier,
            "matched_supplier": row.matched_supplier,
            "balance_qty": None,
            "projected_qty": None,
            "reorder_level": None,
            "reorder_qty": None,
            "supplier_name": row.supplier_name,
            "supplier_status": row.supplier_status,
            "supplier_part_number": row.supplier_part_number,
            "sources": row.sources,
            "open_order_qty": row.open_order_qty,
            "draft_order_qty": row.draft_order_qty,
            "lead_time_days": row.lead_time_days,
            "lead_time_receipts": row.lead_time_receipts,
            "po_count": row.po_count,
            "receipt_count": row.receipt_count,
            "last_purchase_date": row.last_purchase_date,
            "last_purchase_receipt": row.last_purchase_receipt,
            "last_rate": row.last_rate,
            "rate_source": row.rate_source,
            "rate_date": row.rate_date,
            "rate_document": row.rate_document,
            "currency": row.currency,
            "rate_uom": row.rate_uom,
            "total_qty_received": row.total_qty_received,
            "stock_uom": row.stock_uom,
            "last_po_date": row.last_po_date,
        }

    def path_node(row_type, parent_id, key):
        return row_type + ":" + str(len(parent_id)) + ":" + parent_id + "|" + key

    def append_boms(item_code, item_id, indent, path, depth, output):
        all_suppliers = set()
        matched = False
        for bom in boms_by_item.get(item_code, ()):
            bom_id = path_node("bom", item_id, bom.bom_no)
            lines = bom_lines[bom.bom_no]
            label = bom.bom_no
            if bom.docstatus == 1 and bom.is_default:
                label = label + " · " + _("default")
            label = label + " · " + str(len(lines)) + " " + _("component" if len(lines) == 1 else "components")
            if bom.docstatus == 0:
                label = label + " · " + _("draft")
            bom_row = {
                "node_id": bom_id,
                "parent_id": item_id,
                "row_type": "bom",
                "is_component": 1,
                "indent": indent + 1,
                "tree_label": label,
                "bom_no": bom.bom_no,
                "bom_is_default": int(bool(bom.is_default)),
                "bom_status": "Submitted" if bom.docstatus == 1 else "Draft",
                "component_count": len(lines),
            }
            output.append(bom_row)
            bom_suppliers = set()
            for line in lines:
                code = line.item_code or ""
                line_key = str(line.idx) + "|" + str(len(code)) + ":" + code + "|" + line.line_id
                component_id = path_node("component", bom_id, line_key)
                detail = rows_by_item.get(code, ())
                first = detail[0] if detail else None
                supplier_rows = detail if first and first.supplier else ()
                component = {
                    "node_id": component_id,
                    "parent_id": bom_id,
                    "row_type": "component",
                    "is_component": 1,
                    "indent": indent + 2,
                    "tree_label": code,
                    "link_doctype": "Item",
                    "item_code": code,
                    "item_name": first.item_name if first else line.item_name,
                    "bom_no": bom.bom_no,
                    "bom_item_idx": line.idx,
                    "bom_item_id": line.line_id,
                    "bom_qty_per_unit": line.qty_per_unit,
                    "stock_uom": line.stock_uom or (first.stock_uom if first else None),
                    "include_in_manufacturing": int(bool(line.include_in_manufacturing)),
                    "used_in_bom_count": len(used_in_boms[line.item_code]),
                    "balance_qty": first.balance_qty if first else 0,
                    "projected_qty": first.projected_qty if first else 0,
                    "last_purchase_date": first.last_purchase_date if first else None,
                    "supplier_count": len(supplier_rows),
                }
                output.append(component)
                if supplier_rows:
                    for detail_row in supplier_rows:
                        supplier_id = path_node("supplier", component_id, detail_row.supplier)
                        child = make_supplier(detail_row, supplier_id, component_id, indent + 3)
                        child["is_component"] = 1
                        output.append(child)
                        bom_suppliers.add(detail_row.supplier)
                        matched = matched or bool(detail_row.matched_supplier)
                else:
                    child = make_placeholder(code, "none:" + component_id, component_id, indent + 3)
                    child["is_component"] = 1
                    output.append(child)
                if code in path:
                    component["bom_cycle"] = 1
                elif depth >= 10:
                    if code in boms_by_item:
                        component["bom_depth_limit"] = 1
                elif code in boms_by_item:
                    nested_result = append_boms(
                        code, component_id, indent + 2, path + (code,), depth + 1, output
                    )
                    bom_suppliers.update(nested_result[0])
                    matched = matched or nested_result[1]
            bom_row["component_supplier_count"] = len(bom_suppliers)
            all_suppliers.update(bom_suppliers)
        return all_suppliers, matched

    rows_by_item = {}
    bom_rows_by_item = {}
    if expand_bom:
        for row in rows:
            rows_by_item.setdefault(row.item_code, []).append(row)
        shown_items = set()
        for code in rows_by_item:
            detail = rows_by_item[code]
            first = detail[0]
            if not first.is_top_level or not (selected_items or first.supplier or code in boms_by_item):
                continue
            matched = any(row.matched_supplier for row in detail)
            if code in boms_by_item:
                bom_rows = []
                component_match = append_boms(
                    code, "item:" + code, int(bool(first.template_code)), (code,), 1, bom_rows
                )[1]
                matched = matched or component_match
                bom_rows_by_item[code] = bom_rows
            if not suppliers or matched:
                shown_items.add(code)
        rows = [row for row in rows if row.item_code in shown_items]

    result_rows = []
    template_rows = {}
    template_suppliers = {}
    item_rows = {}
    stock_fields = ("balance_qty", "projected_qty", "reorder_level", "reorder_qty")
    order_fields = ("open_order_qty", "draft_order_qty")
    for row in rows:
        item_code = row.item_code
        template_code = row.template_code
        item_id = "item:" + item_code
        template_id = None
        template_row = None
        if template_code:
            template_id = "template:" + template_code
            if template_id not in template_rows:
                template_rows[template_id] = {
                    "node_id": template_id,
                    "parent_id": None,
                    "row_type": "template",
                    "indent": 0,
                    "tree_label": template_code,
                    "link_doctype": "Item",
                    "template": template_code,
                    "item_name": row.template_name,
                    "stock_uom": row.stock_uom,
                    "supplier_count": 0,
                    "total_qty_received": 0,
                }
                for fieldname in stock_fields + order_fields:
                    template_rows[template_id][fieldname] = 0 if row.stock_uom else None
                if not include_drafts:
                    template_rows[template_id]["draft_order_qty"] = None
                template_suppliers[template_id] = set()
                result_rows.append(template_rows[template_id])
            template_row = template_rows[template_id]
            if template_row["stock_uom"] != row.stock_uom:
                template_row["stock_uom"] = None
                for fieldname in stock_fields + order_fields:
                    template_row[fieldname] = None
        if item_id not in item_rows:
            item_rows[item_id] = {
                "node_id": item_id,
                "parent_id": template_id,
                "row_type": "item",
                "indent": 1 if template_id else 0,
                "tree_label": item_code,
                "link_doctype": "Item",
                "item_code": item_code,
                "item_name": row.item_name,
                "stock_uom": row.stock_uom,
                "open_order_qty": 0,
                "draft_order_qty": 0 if include_drafts else None,
                "supplier_count": 0,
                "total_qty_received": 0,
            }
            item_row = item_rows[item_id]
            for fieldname in stock_fields:
                item_row[fieldname] = row[fieldname]
                if template_row is not None and template_row[fieldname] is not None:
                    template_row[fieldname] = template_row[fieldname] + row[fieldname]
            result_rows.append(item_row)
            if not row.supplier:
                placeholder_id = "none:" + str(len(item_code)) + ":" + item_code
                result_rows.append(make_placeholder(item_code, placeholder_id, item_id, item_row["indent"] + 1))
        if row.supplier:
            item_row = item_rows[item_id]
            qty = row.total_qty_received
            item_row["supplier_count"] = item_row["supplier_count"] + 1
            item_row["total_qty_received"] = item_row["total_qty_received"] + qty
            for fieldname in order_fields:
                if row[fieldname] is not None:
                    item_row[fieldname] = item_row[fieldname] + row[fieldname]
                    if template_row is not None and template_row[fieldname] is not None:
                        template_row[fieldname] = template_row[fieldname] + row[fieldname]
            if template_row is not None:
                supplier_set = template_suppliers[template_id]
                supplier_set.add(row.supplier)
                template_row["supplier_count"] = len(supplier_set)
                template_row["total_qty_received"] = template_row["total_qty_received"] + qty
            supplier_id = "supplier:" + str(len(item_code)) + ":" + item_code + ":" + row.supplier
            result_rows.append(make_supplier(row, supplier_id, item_id, item_row["indent"] + 1))
    if expand_bom:
        expanded_rows = []
        pending_boms = ()
        for row in result_rows:
            if row["row_type"] in ("template", "item"):
                expanded_rows.extend(pending_boms)
                pending_boms = bom_rows_by_item.get(row.get("item_code"), ())
            row["is_component"] = 0
            expanded_rows.append(row)
        expanded_rows.extend(pending_boms)
        result_rows = expanded_rows
    return columns, result_rows


data = build_report(filters)

```

## 8. Report JavaScript

Deployed v7 source (Report field `javascript`).

```javascript
frappe.query_reports["Suppliers by Item"] = {
	tree: true,
	name_field: "node_id",
	parent_field: "parent_id",
	initial_depth: 0,
	onload(report) {
		const drafts = report.get_filter("include_drafts");
		const getValue = drafts.get_value.bind(drafts);
		drafts.get_value = () => {
			const value = getValue();
			// Frappe omits falsy report filters, so serialize unchecked as "0".
			return value === 0 ? "0" : value;
		};
	},
	formatter(value, row, column, data, default_formatter) {
		if (data?.is_placeholder && column.fieldname === "tree_label") {
			return `<em class="text-muted">${frappe.utils.escape_html(value)}</em>`;
		}
		if (data?.row_type === "bom" && column.fieldname === "tree_label") {
			const label = frappe.utils.escape_html(value);
			const hasPrefix = label.startsWith("BOM-");
			const prefix = hasPrefix ? "BOM" : __("BOM");
			const name = hasPrefix ? label.slice(3) : ` · ${label}`;
			const emphasis = data.bom_status === "Draft" ? ' class="text-muted"' : "";
			return `<strong${emphasis}><span class="text-muted">${prefix}</span>${name}</strong>`;
		}
		if (
			[
				"balance_qty",
				"projected_qty",
				"reorder_level",
				"reorder_qty",
				"open_order_qty",
				"draft_order_qty",
				"lead_time_days",
				"lead_time_receipts",
				"po_count",
				"receipt_count",
				"bom_qty_per_unit",
			].includes(column.fieldname) && data?.[column.fieldname] == null
		) {
			return "";
		}
		if (column.fieldname === "supplier_status" && (value === "Disabled" || value?.startsWith("On Hold"))) {
			return `<span class="indicator-pill orange">${frappe.utils.escape_html(value)}</span>`;
		}
		const formatted = default_formatter(value, row, column, data);
		if (column.fieldname === "tree_label" && data?.row_type === "component") {
			const notes = [];
			if (data.include_in_manufacturing === 0) notes.push(__("not used in manufacturing"));
			if (data.bom_cycle) notes.push(__("cycle"));
			if (data.bom_depth_limit) notes.push(__("BOM depth limit reached"));
			if (notes.length) return `${formatted} <span class="text-muted">· ${notes.join(" · ")}</span>`;
		}
		if (column.fieldname === "tree_label" && data?.row_type === "supplier" && data.matched_supplier) {
			return `<strong>${formatted}</strong>`;
		}
		return formatted;
	},
	after_datatable_render(datatable) {
		const columns = datatable.datamanager.getColumns();
		for (const fieldname of ["balance_qty", "projected_qty", "sources"]) {
			const column = columns.find((column) => column.id === fieldname);
			if (column?.description) {
				datatable.columnmanager.getHeaderCell$(column.colIndex)?.setAttribute("title", column.description);
			}
		}
	},
	filters: [
		{
			fieldname: "items",
			label: __("Items"),
			fieldtype: "MultiSelectList",
			options: "Item",
			get_data(txt) {
				return frappe.db.get_link_options("Item", txt);
			},
		},
		{
			fieldname: "variant_of",
			label: __("Variant Of"),
			fieldtype: "MultiSelectList",
			options: "Item",
			get_data(txt) {
				return frappe.db.get_link_options("Item", txt, { has_variants: 1 });
			},
		},
		{
			fieldname: "suppliers",
			label: __("Suppliers"),
			fieldtype: "MultiSelectList",
			options: "Supplier",
			description: __(
				"Matches suppliers linked to the item and, when BOM expansion is enabled, its components. All suppliers are shown."
			),
			get_data(txt) {
				return frappe.db.get_link_options("Supplier", txt);
			},
		},
		{
			fieldname: "warehouses",
			label: __("Warehouses"),
			fieldtype: "MultiSelectList",
			options: "Warehouse",
			description: __(
				"Limits balance, projected quantity, and reorder settings to these warehouses. Group warehouses include their descendants."
			),
			get_data(txt) {
				return frappe.db.get_link_options("Warehouse", txt);
			},
		},
		{
			fieldname: "include_drafts",
			label: __("Include Draft Purchase Orders"),
			fieldtype: "Check",
			default: 1,
		},
		{
			fieldname: "expand_bom",
			label: __("Expand BOM components"),
			fieldtype: "Check",
			default: 0,
		},
	],
};
```
