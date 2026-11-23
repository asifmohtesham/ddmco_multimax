# Suppliers by Item — Report Implementation Guide

> **Scope.** This read-only ERPNext Desk Script Report is live on
> `erp-testing.multimax.cloud`. Production deployment is pending. The Report
> record stores both scripts. The source below can recreate it in Desk.

The report finds suppliers linked to an enabled item. It combines Item Supplier,
Item Default and buying Item Price records with submitted Purchase Orders,
Purchase Receipts, Purchase Invoices, Supplier Quotations and Requests for
Quotation. Each real supplier row represents one item and supplier pair, with
its evidence sources, receipt history and latest qualifying rate.

## 1. Prerequisites and access

| Requirement | Detail |
|---|---|
| Server-side scripts | The site must already have `server_script_enabled` for custom Script Reports. |
| Report roles | **Purchase User** and **Stock User**. Either role can qualify. Frappe also checks report access through the reference DocType, Purchase Receipt. |
| Desk setup | A System Manager can create or edit the Report record. |
| App access | The drawer entry and Item Overview card use the signed-in session's roles. When the User document omits roles on v16, the shared session code can recover them from the signed-in user's Desk boot data. |

## 2. Filters

| Filter | Field | Type | Effect |
|---|---|---|---|
| Items | `items` | MultiSelectList → Item | Matches the selected item codes. |
| Variant Of | `variant_of` | MultiSelectList → Item | Offers template items and matches their variants. Selecting both Items and Variant Of returns the union. |
| Suppliers | `suppliers` | MultiSelectList → Supplier | Limits supplier evidence to selected suppliers. Can be used on its own to find a supplier's items. |
| Warehouses | `warehouses` | MultiSelectList → Warehouse | Limits sources to Purchase Order, Purchase Receipt and Purchase Invoice lines in the selected warehouses. |
| From Date / To Date | `from_date` / `to_date` | Date | Inclusive bounds on transaction or posting dates. Either date excludes Item Supplier, Item Default and Item Price. Leaving both blank uses all history. |

When Items or Variant Of is set, every matching enabled item is retained,
including items with zero suppliers under the active filters. With both item
filters empty, the report returns only items with matching supplier evidence.

## 3. Columns

| Column | Field | Value |
|---|---|---|
| Item / Supplier | `tree_label` | Item or Supplier link, or the placeholder label. |
| Item Name | `item_name` | Item or template name. |
| Supplier Name | `supplier_name` | Display name for the supplier. |
| Supplier Part Number | `supplier_part_number` | First populated value by source priority, then recency within that source. The priority is Item Supplier, Purchase Order, Supplier Quotation, Purchase Receipt. |
| Sources | `sources` | Distinct matching source names. |
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
| Last PO Date | `last_po_date` | Latest submitted Purchase Order date under the active filters, independent of the rate source. |
| Supplier Count | `supplier_count` | Supplier count for an item or distinct supplier count across a template's variants. |

Receipt events include submitted Purchase Receipts and stock-updating Purchase
Invoices that qualify as independent receipts. The script excludes invoice
lines that reference a receipt or are already covered by a submitted receipt
line. It selects the rate independently of net received quantity, so an item
with zero net quantity after returns can still have a receipt rate.

## 4. Tree and placeholder contract

Desk uses `node_id` as the tree key and `parent_id` as the parent. Rows arrive
parent-first. Template groups and standalone items start at `indent: 0`.
Variants under an enabled template use `indent: 1`. Supplier and placeholder
children are one level deeper than their item.

| `row_type` | `node_id` | Parent | Additional fields |
|---|---|---|---|
| `template` | `template:<template_code>` | None | `template`, `link_doctype: Item` |
| `item` | `item:<item_code>` | Template if grouped | `item_code`, `link_doctype: Item` |
| `supplier` | `supplier:<len>:<item_code>:<supplier>` | Item | `item_code`, `supplier`, `link_doctype: Supplier`, `is_placeholder: 0` |
| `placeholder` | `none:<len>:<item_code>` | Item | `item_code`, `is_placeholder: 1`, `tree_label: No supplier recorded` |

`<len>` is the length of the item code. The placeholder has blank cells in
the other report columns. Desk styles its label as muted text so the item
still has an expandable child. The app skips the child and shows **No supplier
recorded** on the item itself.

For `variant_of=["ACP-25"]`, the template `template:ACP-25` contains
`item:2002492` with placeholder `none:7:2002492` and `item:2002506` with supplier
`supplier:7:2002506:KANG KAI`.

## 5. App screens

- **Buying → Reports → Suppliers by Item** opens the full report. The footer
  sums received quantities from supplier rows and groups them by stock UOM.
  [Report screen](../lib/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_screen.dart)
- **Item → Overview → Suppliers** runs with `items=[itemCode]` for an item or
  `variant_of=[itemCode]` for a template. **View full report** opens the report
  with the same selection.
  [Item Overview](../lib/app/modules/item/form/item_form_screen.dart)
  [Suppliers card](../lib/app/modules/item/form/widgets/item_suppliers_card.dart)

The full report shows an available rate with its currency, source and date. Both screens
use `ApiProvider.runSuppliersByItem`, which sends a form-encoded POST to
`/api/method/frappe.desk.query_report.run` with `report_name=Suppliers by Item`,
a JSON `filters` field, `ignore_prepared_report=true` and
`are_default_filters=false`. The parser reads the keyed rows in
`message.result`.
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
    from_date = filters.get("from_date")
    to_date = filters.get("to_date")
    from_date = frappe.utils.getdate(from_date) if from_date else None
    to_date = frappe.utils.getdate(to_date) if to_date else None
    if from_date and to_date and from_date > to_date:
        frappe.throw(_("From Date must be on or before To Date."))

    parameters = {
        "selected_items": int(bool(items or templates)),
        "items": items or (None,),
        "templates": templates or (None,),
        "by_supplier": int(bool(suppliers)),
        "suppliers": suppliers or (None,),
        "by_warehouse": int(bool(warehouses)),
        "warehouses": warehouses or (None,),
        "by_date": int(bool(from_date or to_date)),
        "from_date": from_date,
        "to_date": to_date,
    }

    rows = frappe.db.sql(
        """
        WITH target AS (
            SELECT i.name AS item_code, i.item_name, i.stock_uom,
                   CASE WHEN t.disabled = 0 THEN t.name END AS template_code,
                   t.item_name AS template_name
            FROM `tabItem` i
            LEFT JOIN `tabItem` t ON t.name = i.variant_of AND t.has_variants = 1
            WHERE i.disabled = 0
              AND (%(selected_items)s = 0 OR i.name IN %(items)s OR t.name IN %(templates)s)
        ),
        item_suppliers AS (
            SELECT s.parent AS item_code, s.supplier, s.supplier_part_no,
                   s.creation, s.name, s.idx
            FROM `tabItem Supplier` s
            JOIN target t ON t.item_code = s.parent
            WHERE %(by_warehouse)s = 0 AND %(by_date)s = 0 AND s.parenttype = 'Item'
              AND s.parentfield = 'supplier_items' AND s.supplier <> ''
              AND (%(by_supplier)s = 0 OR s.supplier IN %(suppliers)s)
        ),
        orders AS (
            SELECT d.item_code, h.supplier, h.transaction_date, h.creation,
                   h.name AS voucher, d.supplier_part_no, d.idx, d.name AS line_id,
                   h.currency, d.rate, d.uom
            FROM `tabPurchase Order Item` d
            JOIN `tabPurchase Order` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND h.supplier <> ''
              AND (%(by_supplier)s = 0 OR h.supplier IN %(suppliers)s)
              AND (%(by_warehouse)s = 0 OR d.warehouse IN %(warehouses)s)
              AND (%(from_date)s IS NULL OR h.transaction_date >= %(from_date)s)
              AND (%(to_date)s IS NULL OR h.transaction_date <= %(to_date)s)
        ),
        receipts AS (
            SELECT d.item_code, h.supplier, h.name AS voucher, d.name AS line_id, d.idx,
                   h.posting_date, h.posting_time, h.currency, d.rate, d.uom, d.stock_qty,
                   h.creation, d.supplier_part_no
            FROM `tabPurchase Receipt Item` d
            JOIN `tabPurchase Receipt` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND h.supplier <> ''
              AND (%(by_supplier)s = 0 OR h.supplier IN %(suppliers)s)
              AND (%(by_warehouse)s = 0 OR d.warehouse IN %(warehouses)s)
              AND (%(from_date)s IS NULL OR h.posting_date >= %(from_date)s)
              AND (%(to_date)s IS NULL OR h.posting_date <= %(to_date)s)
        ),
        invoices AS (
            SELECT d.item_code, h.supplier, h.name AS voucher, d.name AS line_id, d.idx,
                   h.posting_date, h.posting_time, h.currency, d.rate, d.uom, d.stock_qty,
                   h.update_stock, d.purchase_receipt, d.pr_detail
            FROM `tabPurchase Invoice Item` d
            JOIN `tabPurchase Invoice` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE h.docstatus = 1 AND h.supplier <> ''
              AND (%(by_supplier)s = 0 OR h.supplier IN %(suppliers)s)
              AND (%(by_warehouse)s = 0 OR d.warehouse IN %(warehouses)s)
              AND (%(from_date)s IS NULL OR h.posting_date >= %(from_date)s)
              AND (%(to_date)s IS NULL OR h.posting_date <= %(to_date)s)
        ),
        quotations AS (
            SELECT d.item_code, h.supplier, h.transaction_date, h.creation,
                   h.name AS voucher, d.supplier_part_no, d.idx, d.name AS line_id
            FROM `tabSupplier Quotation Item` d
            JOIN `tabSupplier Quotation` h ON h.name = d.parent
            JOIN target t ON t.item_code = d.item_code
            WHERE %(by_warehouse)s = 0 AND h.docstatus = 1 AND h.supplier <> ''
              AND (%(by_supplier)s = 0 OR h.supplier IN %(suppliers)s)
              AND (%(from_date)s IS NULL OR h.transaction_date >= %(from_date)s)
              AND (%(to_date)s IS NULL OR h.transaction_date <= %(to_date)s)
        ),
        links AS (
            SELECT item_code, supplier, 'Item Supplier' AS source FROM item_suppliers
            UNION ALL
            SELECT d.parent, d.default_supplier, 'Item Default'
            FROM `tabItem Default` d
            JOIN target t ON t.item_code = d.parent
            WHERE %(by_warehouse)s = 0 AND %(by_date)s = 0 AND d.parenttype = 'Item'
              AND d.parentfield = 'item_defaults' AND d.default_supplier <> ''
              AND (%(by_supplier)s = 0 OR d.default_supplier IN %(suppliers)s)
            UNION ALL
            SELECT p.item_code, p.supplier, 'Item Price'
            FROM `tabItem Price` p
            JOIN target t ON t.item_code = p.item_code
            WHERE %(by_warehouse)s = 0 AND %(by_date)s = 0 AND p.buying = 1 AND p.supplier <> ''
              AND (%(by_supplier)s = 0 OR p.supplier IN %(suppliers)s)
            UNION ALL SELECT item_code, supplier, 'Purchase Order' FROM orders
            UNION ALL SELECT item_code, supplier, 'Purchase Receipt' FROM receipts
            UNION ALL SELECT item_code, supplier, 'Purchase Invoice' FROM invoices
            UNION ALL SELECT item_code, supplier, 'Supplier Quotation' FROM quotations
            UNION ALL
            SELECT d.item_code, s.supplier, 'Request for Quotation'
            FROM `tabRequest for Quotation Item` d
            JOIN `tabRequest for Quotation` h ON h.name = d.parent
            JOIN `tabRequest for Quotation Supplier` s ON s.parent = h.name
            JOIN target t ON t.item_code = d.item_code
            WHERE %(by_warehouse)s = 0 AND h.docstatus = 1 AND s.supplier <> ''
              AND (%(by_supplier)s = 0 OR s.supplier IN %(suppliers)s)
              AND (%(from_date)s IS NULL OR h.transaction_date >= %(from_date)s)
              AND (%(to_date)s IS NULL OR h.transaction_date <= %(to_date)s)
        ),
        part_numbers AS (
            SELECT item_code, supplier, supplier_part_no, 1 AS source_priority,
                   NULL AS transaction_date, NULL AS transaction_time,
                   creation, name AS voucher, idx, name AS line_id
            FROM item_suppliers
            UNION ALL
            SELECT item_code, supplier, supplier_part_no, 2, transaction_date, NULL,
                   creation, voucher, idx, line_id FROM orders
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
            FROM orders WHERE rate > 0
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
        last_orders AS (
            SELECT item_code, supplier, MAX(transaction_date) AS last_po_date
            FROM orders GROUP BY item_code, supplier
        )
        SELECT t.item_code, t.item_name, t.stock_uom, t.template_code, t.template_name,
               s.supplier, supplier.supplier_name,
               COALESCE(p.supplier_part_no, '') AS supplier_part_number, s.sources,
               CASE WHEN r.stock_qty > 0 THEN r.posting_date END AS last_purchase_date,
               CASE WHEN r.stock_qty > 0 THEN r.receipt END AS last_purchase_receipt,
               rate.rate AS last_rate, rate.rate_source, rate.rate_date, rate.voucher AS rate_document,
               rate.currency, rate.uom AS rate_uom,
               COALESCE(r.net_qty, 0) AS total_qty_received, o.last_po_date
        FROM target t
        LEFT JOIN by_supplier s ON s.item_code = t.item_code
        LEFT JOIN `tabSupplier` supplier ON supplier.name = s.supplier
        LEFT JOIN ranked_part_numbers p
            ON p.item_code = t.item_code AND p.supplier = s.supplier AND p.rn = 1
        LEFT JOIN ranked_events r
            ON r.item_code = t.item_code AND r.supplier = s.supplier AND r.rn = 1
        LEFT JOIN ranked_rates rate
            ON rate.item_code = t.item_code AND rate.supplier = s.supplier AND rate.rn = 1
        LEFT JOIN last_orders o ON o.item_code = t.item_code AND o.supplier = s.supplier
        WHERE %(selected_items)s = 1 OR s.supplier IS NOT NULL
        ORDER BY COALESCE(t.template_code, t.item_code), t.template_code IS NOT NULL,
                 t.item_code, last_purchase_date DESC, s.supplier
        """,
        parameters,
        as_dict=True,
    )

    fields = [
        ("tree_label", "Item / Supplier", "Dynamic Link", "link_doctype", 240),
        ("item_name", "Item Name", "Data", None, 220),
        ("supplier_name", "Supplier Name", "Data", None, 190),
        ("supplier_part_number", "Supplier Part Number", "Data", None, 165),
        ("sources", "Sources", "Data", None, 260),
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
    columns = []
    for fieldname, label, fieldtype, options, width in fields:
        column = {
            "fieldname": fieldname,
            "label": _(label),
            "fieldtype": fieldtype,
            "options": options,
            "width": width,
        }
        if fieldname == "sources":
            column["description"] = _(
                "With Warehouses selected, sources include only Purchase Order, Purchase Receipt, "
                "and Purchase Invoice lines in those warehouses. With either date selected, "
                "sources exclude Item Supplier, Item Default, and Item Price."
            )
        columns.append(column)

    result_rows = []
    template_rows = {}
    template_suppliers = {}
    item_rows = {}
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
                template_suppliers[template_id] = set()
                result_rows.append(template_rows[template_id])
            template_row = template_rows[template_id]
            if template_row["stock_uom"] != row.stock_uom:
                template_row["stock_uom"] = None
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
                "supplier_count": 0,
                "total_qty_received": 0,
            }
            item_row = item_rows[item_id]
            result_rows.append(item_row)
            if not row.supplier:
                placeholder = {column["fieldname"]: None for column in columns}
                placeholder.update({
                    "node_id": "none:" + str(len(item_code)) + ":" + item_code,
                    "parent_id": item_id,
                    "row_type": "placeholder",
                    "indent": item_row["indent"] + 1,
                    "tree_label": _("No supplier recorded"),
                    "item_code": item_code,
                    "is_placeholder": 1,
                })
                result_rows.append(placeholder)
        if row.supplier:
            item_row = item_rows[item_id]
            qty = row.total_qty_received
            item_row["supplier_count"] = item_row["supplier_count"] + 1
            item_row["total_qty_received"] = item_row["total_qty_received"] + qty
            if template_row is not None:
                suppliers = template_suppliers[template_id]
                suppliers.add(row.supplier)
                template_row["supplier_count"] = len(suppliers)
                template_row["total_qty_received"] = template_row["total_qty_received"] + qty
            result_rows.append({
                "node_id": "supplier:" + str(len(item_code)) + ":" + item_code + ":" + row.supplier,
                "parent_id": item_id,
                "row_type": "supplier",
                "indent": item_row["indent"] + 1,
                "is_placeholder": 0,
                "tree_label": row.supplier,
                "link_doctype": "Supplier",
                "item_code": item_code,
                "supplier": row.supplier,
                "supplier_name": row.supplier_name,
                "supplier_part_number": row.supplier_part_number,
                "sources": row.sources,
                "last_purchase_date": row.last_purchase_date,
                "last_purchase_receipt": row.last_purchase_receipt,
                "last_rate": row.last_rate,
                "rate_source": row.rate_source,
                "rate_date": row.rate_date,
                "rate_document": row.rate_document,
                "currency": row.currency,
                "rate_uom": row.rate_uom,
                "total_qty_received": qty,
                "stock_uom": row.stock_uom,
                "last_po_date": row.last_po_date,
            })
    return columns, result_rows


data = build_report(filters)

```

## 8. Report JavaScript

```javascript
frappe.query_reports["Suppliers by Item"] = {
	tree: true,
	name_field: "node_id",
	parent_field: "parent_id",
	initial_depth: 0,
	formatter(value, row, column, data, default_formatter) {
		if (data?.is_placeholder && column.fieldname === "tree_label") {
			return `<em class="text-muted">${frappe.utils.escape_html(value)}</em>`;
		}
		return default_formatter(value, row, column, data);
	},
	after_datatable_render(datatable) {
		const sources = datatable.datamanager.getColumns().find((column) => column.id === "sources");
		if (sources?.description) {
			datatable.columnmanager.getHeaderCell$(sources.colIndex)?.setAttribute("title", sources.description);
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
				"Limits supplier links to Purchase Order, Purchase Receipt, and Purchase Invoice lines in the selected warehouses."
			),
			get_data(txt) {
				return frappe.db.get_link_options("Warehouse", txt);
			},
		},
		{
			fieldname: "from_date",
			label: __("From Date"),
			fieldtype: "Date",
			description: __(
				"Either date excludes Item Supplier, Item Default, and Item Price. Leave both dates blank for all history."
			),
		},
		{
			fieldname: "to_date",
			label: __("To Date"),
			fieldtype: "Date",
			description: __(
				"Either date excludes Item Supplier, Item Default, and Item Price. Leave both dates blank for all history."
			),
		},
	],
};
```
