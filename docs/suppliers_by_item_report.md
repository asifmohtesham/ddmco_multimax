# Suppliers by Item — Report Implementation Guide

> **Scope.** This guide describes the v7 contract of the read-only ERPNext Desk
> Script Report `Suppliers by Item`. The Python and JavaScript (kept in the private `erp-scripts` repository,
> `reports/suppliers-by-item/`) match the
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

The deployed source is [`reports/suppliers-by-item/report_script.py`](https://github.com/asifmohtesham/erp-scripts/tree/main/reports/suppliers-by-item/report_script.py) in the private `erp-scripts` repository.

## 8. Report JavaScript

Deployed v7 source (Report field `javascript`).

The deployed source is [`reports/suppliers-by-item/report.js`](https://github.com/asifmohtesham/erp-scripts/tree/main/reports/suppliers-by-item/report.js) in the private `erp-scripts` repository.
