# Item Image (virtual field) on Stock Entry, Purchase Order and Delivery Note items

> **Scope:** This is a **backend (ERPNext Desk) artifact**, not Flutter code. It
> lives on the Frappe instance (`erp.multimax.cloud`) as one **Custom Field** and
> one **Client Script** per document type. Desk artifacts are not under source
> control, so this document is the source to rebuild them from.

Adds an **Item Image** column to the **Items** grid of these documents:

| Parent | Child table | Custom Field | Client Script | Insert after |
|---|---|---|---|---|
| Stock Entry | `Stock Entry Detail` | `Stock Entry Detail-custom_item_image` | `Stock Entry - Item Image` | `custom_invoice_serial_number` |
| Purchase Order | `Purchase Order Item` | `Purchase Order Item-custom_item_image` | `Purchase Order - Item Image` | `item_name` |
| Delivery Note | `Delivery Note Item` | `Delivery Note Item-custom_item_image` | `Delivery Note - Item Image` | `item_name` |

It is there so users can see the item and so the grid's **Download** (bulk-edit
CSV export) includes an image link for each row. It is **never stored**:

- No database column is created, and nothing is written on save.
- Opening a document does not mark it dirty ("Not Saved"), because the value
  comes from the server with the document and is never set through `set_value`.
- The value is always the item's **current** `Item.image`. It is not a snapshot
  taken when the document was made.

Sections 2 and 3 show the **Stock Entry** version, which is the template. The
Purchase Order and Delivery Note versions are identical except for these substitutions:

| In the template | Purchase Order | Delivery Note |
|---|---|---|
| `"Stock Entry Detail"` (Custom Field `dt`, `get_docfield`, child `form.on`) | `"Purchase Order Item"` | `"Delivery Note Item"` |
| `"Stock Entry"` (Client Script `dt`, parent `form.on`) | `"Purchase Order"` | `"Delivery Note"` |
| `se_item_image…` / `SE_ITEM_IMAGE` | `po_item_image…` / `PO_ITEM_IMAGE` | `dn_item_image…` / `DN_ITEM_IMAGE` |
| `insert_after` | `item_name` | `item_name` |

> **Standard `image` field:** Purchase Order Item and Delivery Note Item already have
> ERPNext's own `image` field: Attach, **stored**, hidden, `fetch_from: item_code.image`.
> It holds the image as it was when the row was made, as a relative path.
> `custom_item_image` leaves it untouched. The new field is the visible, always-current,
> never-stored one, with an absolute URL.

**Applied to `erp.multimax.cloud`** (Frappe 16.56 / ERPNext 16.55) through the REST API,
as `asif@multimax.cloud`: Stock Entry on 16 November 2026, Purchase Order and
Delivery Note on 17 November 2026. Not applied on `erp-testing.multimax.cloud`.

Works on Frappe **v15 and v16** (checked against the `version-15` and
`version-16` source of `frappe/model/document.py`, `grid.js`, `formatters.js`
and `safe_exec.py`).

---

## 1. How it works

| Concern | Mechanism |
|---|---|
| Not stored | `is_virtual = 1`. Frappe creates no column, and every DB write calls `get_valid_dict(ignore_virtual=True)`. |
| Value on load | When a virtual field has no Python property, Frappe evaluates its **Options** as a `safe_eval` expression with `doc` = the row. The result is sent to the browser with the document (and to API reads). |
| Not dirty | The form never `set_value`s it on load. On a new or changed row, the Client Script writes the row object directly (`row[field] = ...`), which does not trigger the dirty flag. Changing the Item Code already marks the form dirty. |
| Export | The grid **Download** button (shown because `items.allow_bulk_edit = 1`) exports every value-type field. `Attach Image` is a value type, so the column is exported with the row's own value. |
| Shown as an image | `Attach Image` renders as a plain link in grid cells. The Client Script sets a `formatter` that draws a small thumbnail (it still opens the full image). |
| Bulk-edit upload | If an uploaded CSV includes the column, the value is ignored on save (virtual). |

The value is an **absolute URL** (`https://erp.multimax.cloud/files/...`), so the
exported CSV has links you can click, or use with `=IMAGE()` in Google Sheets or Excel.
Images under `/private/files/` open only for a signed-in user.

---

## 2. Custom Field

**Desk:** *Customize Form → Stock Entry Detail*, or create a new *Custom Field*.

| Property | Value |
|---|---|
| Document Type (`dt`) | `Stock Entry Detail` |
| Label | `Item Image` |
| Fieldname | `custom_item_image` |
| Type | `Attach Image` |
| Insert After | `custom_invoice_serial_number` (after Item Name) |
| Is Virtual | ✔ |
| Read Only | ✔ |
| In List View | ✔ (column width 1) |
| No Copy | ✔ |
| Print Hide | ✔ |
| Report Hide | ✔ |
| Fetch From | *(empty, do not set: the Client Script fills new rows)* |
| Options | the expression below |

**Options** (one line; it is a `safe_eval` expression, so lambdas and `:=` are not allowed):

```python
([frappe.utils.get_url(img) for img in [frappe.db.get_value("Item", doc.item_code, "image")] if img] or [None])[0] if doc.item_code else None
```

This runs one primary-key lookup per row. It returns `None` when the row has no
item or the item has no image. `get_url` turns `/files/x.jpg` into an absolute URL
and leaves an `http(s)://` URL unchanged.

Equivalent `Custom Field` document (for API creation):

```json
{
  "doctype": "Custom Field",
  "dt": "Stock Entry Detail",
  "label": "Item Image",
  "fieldname": "custom_item_image",
  "fieldtype": "Attach Image",
  "insert_after": "custom_invoice_serial_number",
  "is_virtual": 1,
  "read_only": 1,
  "in_list_view": 1,
  "columns": 1,
  "no_copy": 1,
  "print_hide": 1,
  "report_hide": 1,
  "options": "([frappe.utils.get_url(img) for img in [frappe.db.get_value(\"Item\", doc.item_code, \"image\")] if img] or [None])[0] if doc.item_code else None"
}
```

> **Grid columns:** users who have set their own columns with the gear icon on
> the Items grid will not see the new column until they add **Item Image** there.
> `In List View` affects only the default layout.

---

## 3. Client Script

**Desk:** *Client Script → New*. DocType `Stock Entry`, Apply To `Form`, Enabled ✔.
Name: `Stock Entry - Item Image`.

```js
// Item Image on Stock Entry Detail is a virtual, read-only field (never saved).
// The server fills it on load. This script fills new or changed rows without
// set_value (so the form is not marked dirty by it), and shows a thumbnail in the grid.
const SE_ITEM_IMAGE = "custom_item_image";

function se_item_image_thumb(value) {
	if (!value) return "";
	const url = frappe.utils.escape_html(value);
	return `<a href="${url}" target="_blank" rel="noopener" onclick="event.stopPropagation()">
		<img src="${url}" alt="" loading="lazy"
			style="height:28px;max-width:56px;object-fit:contain;vertical-align:middle">
	</a>`;
}

function se_item_image_set_formatter(frm) {
	// v16 grid cells read the formatter from the global meta docfield.
	const df = frappe.meta.get_docfield("Stock Entry Detail", SE_ITEM_IMAGE);
	if (df) df.formatter = se_item_image_thumb;
	// v15 grid cells read it from the grid's own copy of the docfield.
	const grid = frm.fields_dict.items && frm.fields_dict.items.grid;
	if (grid && grid.get_docfield(SE_ITEM_IMAGE)) {
		grid.update_docfield_property(SE_ITEM_IMAGE, "formatter", se_item_image_thumb);
	}
}

frappe.ui.form.on("Stock Entry", {
	setup(frm) {
		se_item_image_set_formatter(frm);
	},
	onload_post_render(frm) {
		se_item_image_set_formatter(frm);
		frm.refresh_field("items");
	},
});

frappe.ui.form.on("Stock Entry Detail", {
	item_code(frm, cdt, cdn) {
		const row = locals[cdt][cdn];
		const item_code = row.item_code;
		const apply = (url) => {
			// Ignore a late answer if the row's item changed again meanwhile.
			if (row.item_code !== item_code) return;
			row[SE_ITEM_IMAGE] = url || "";
			frm.refresh_field("items");
		};
		if (!item_code) return apply("");
		frappe.db
			.get_value("Item", item_code, "image")
			.then((r) => {
				const img = r && r.message && r.message.image;
				apply(img ? frappe.urllib.get_full_url(img) : "");
			});
	},
});
```

---

## 4. Verify

Use an ordinary Stock user, not Administrator.

1. Open a **draft** Stock Entry whose items have images. The Item Image column
   shows thumbnails, and the title bar shows **no** "Not Saved".
2. Add a row and scan or pick an item. The thumbnail appears. (The form is now
   "Not Saved" because of the new row, as expected.)
3. Save, then reload. Thumbnails are still there. In *Stock Entry Detail* there is
   no `custom_item_image` column in the database (`bench --site … mariadb`, then
   `DESC \`tabStock Entry Detail\`;`).
4. Items grid → **Download**. The CSV has an `Item Image` column with
   `https://erp.multimax.cloud/files/...` links.
5. Open a **submitted** entry. Thumbnails show, and nothing is editable.

## 5. Effect on the mobile app

`GET /api/resource/Stock Entry/<name>` now returns `custom_item_image` on each
row. `StockEntryItem.fromJson` ignores unknown keys, and `toJson` sends only
modelled fields. Even if the key were sent, the server ignores it (virtual).
No app change is needed. Each read costs one extra item lookup per row.

## 6. Rollback

Delete the Client Script `Stock Entry - Item Image`, then delete the Custom Field
`Stock Entry Detail-custom_item_image`. No data migration is needed, because
nothing was ever stored.

## 7. Related fix: `Stock Entry-Variant Of` no longer dirties drafts

The existing Client Script `Stock Entry-Variant Of` made every draft open as
"Not Saved", whatever Item Image did. Its `onload` checked `row.variant_of`, which
is not a field on Stock Entry Detail (the real field is `custom_variant_of`).
So it called `frappe.model.set_value` on **every** row, with one Item request per row.

**Fixed on `erp.multimax.cloud` on 16 November 2026.** `onload` now calls `backfill_variant_of(frm)`,
which:

- makes **one** `frappe.db.get_list('Item', …)` request for all of the entry's item codes;
- sets `custom_variant_of` only on rows whose value differs from the item's `variant_of`;
- writes with `skip_dirty_trigger` (`set_value(..., null, true)`), so a display-only
  backfill never marks the form dirty.

On MAT-STE-2026-08325 (46 rows), a load used to mean 46 requests and 46 writes.
It is now 1 request and 0 writes, because every row already held the right value.
Picking an item on a row, Validate Document and the rack-to-warehouse code are unchanged.

**Rollback:** in the Client Script, replace the `backfill_variant_of(frm);` call in `onload` with
the original loop, and delete the `backfill_variant_of` function:

```text
frm.doc.items.forEach(row => {
    if (!row.variant_of && row.item_code) {
        populate_variant_of(row);
    }
});
```

**`Delivery Note-Variant Of` (not changed).** Its `onload` checks the right field
(`custom_variant_of`), but for an item with no `variant_of` it `set_value`s `''` over
an empty value. Frappe treats that as a change, so the form opens "Not Saved".
On 17 November 2026 none of the 6 Delivery Note drafts had such a row, so nothing
was affected and the script was left as is. If saved drafts start opening
"Not Saved", apply the section 7 `backfill_variant_of` fix there too.
`Purchase Order` has no row-level Client Script; its only script changes the
Material Request "Get Items From" dialog.
