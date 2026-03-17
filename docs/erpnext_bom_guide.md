# ERPNext Bill of Materials (BOM) — Complete Guide

> **Source analysed:** [`frappe/erpnext` → `erpnext/manufacturing/doctype/bom/`](https://github.com/frappe/erpnext/tree/develop/erpnext/manufacturing/doctype/bom)
> **Framework:** Frappe v15 / ERPNext v15+

---

## Table of Contents

1. [What is a BOM?](#1-what-is-a-bom)
2. [BOM DocType — Field Reference](#2-bom-doctype--field-reference)
3. [Creating a BOM — Step-by-Step](#3-creating-a-bom--step-by-step)
4. [The Operations Tab — In Depth](#4-the-operations-tab--in-depth)
5. [Cost Calculation Logic](#5-cost-calculation-logic)
6. [Multi-Level BOM & Explosion](#6-multi-level-bom--explosion)
7. [Semi-Finished Goods Tracking](#7-semi-finished-goods-tracking)
8. [Submitting, Amending & Cancelling](#8-submitting-amending--cancelling)
9. [API & Programmatic Usage](#9-api--programmatic-usage)
10. [Common Errors & Fixes](#10-common-errors--fixes)

---

## 1. What is a BOM?

A **Bill of Materials (BOM)** is the master recipe for manufacturing a Finished Good (FG).
It defines:

- Which **raw materials** (and sub-assemblies) are required, and in what quantities
- Which **manufacturing operations** are performed (cutting, welding, painting, etc.)
- The **cost structure** — raw material cost + operating cost = total BOM cost

ERPNext auto-names BOMs as `BOM-{Item Code}-{sequence}` (e.g., `BOM-CHAIR-001`).

---

## 2. BOM DocType — Field Reference

### Header Fields

| Field | Type | Description |
|---|---|---|
| `item` | Link → Item | The Finished Good this BOM produces |
| `quantity` | Float | How many units of the FG this BOM produces per run |
| `uom` | Link → UOM | Auto-fetched from the item's stock UOM |
| `company` | Link → Company | Mandatory; drives currency and warehouse defaults |
| `currency` | Link → Currency | Defaults to company currency |
| `rm_cost_as_per` | Select | Cost method: `Valuation Rate` / `Last Purchase Rate` / `Price List` |
| `is_default` | Check | Mark as the default BOM for the item (only one allowed) |
| `is_active` | Check | Inactive BOMs cannot be used in Work Orders |
| `routing` | Link → Routing | Auto-populate the Operations tab from a saved Routing template |
| `with_operations` | Check | **Enables** the Operations tab |
| `transfer_material_against` | Select | `Work Order` or `Job Card` — controls when materials are issued |
| `process_loss_percentage` | Percent | Expected % of finished goods lost during production |
| `allow_alternative_item` | Check | Allows substituting raw materials in a Work Order |

### Items Tab (Raw Materials)

| Field | Description |
|---|---|
| `item_code` | Raw material / sub-assembly item |
| `qty` | Required quantity in the item's own UOM |
| `uom` | Purchase/use UOM |
| `stock_qty` | Computed: `qty × conversion_factor` |
| `bom_no` | Link to child BOM if this is a sub-assembly |
| `source_warehouse` | Override default warehouse for this item |
| `operation` | Tie raw material consumption to a specific operation |
| `include_item_in_manufacturing` | Whether to transfer this item via a Stock Entry |
| `sourced_by_supplier` | Supplier provides it — zero cost in BOM |
| `do_not_explode` | Treat this sub-assembly item as a leaf (don't recurse into its BOM) |

### Secondary Items Tab

Tracks **scrap** and **by-products** produced alongside the finished good.

| Field | Description |
|---|---|
| `type` | `Scrap` or `By-Product` |
| `item_code` | The secondary item produced |
| `qty` | Quantity expected |
| `cost_allocation_per` | % of raw material cost allocated to this item (reduces FG cost) |
| `process_loss_per` | Expected process loss % for this secondary item |

> **Cost Rule:** The sum of `cost_allocation_per` for the FG and all secondary items must equal **100%**.

---

## 3. Creating a BOM — Step-by-Step

### Prerequisites

- [ ] Finished Good item exists in the Item master (`is_stock_item = 1` or non-stock is fine)
- [ ] All raw material items exist in the Item master
- [ ] Workstations exist (if using Operations)
- [ ] Company is set up with a base currency

### Step 1 — Open New BOM

```
Manufacturing → Bill of Materials → New
```

### Step 2 — Fill Header

```
Item          : <your FG item>
Quantity      : 1          ← always start with 1 unit
Company       : <your company>
Is Default    : ✓          ← if this is the primary BOM for the item
```

### Step 3 — Add Raw Materials (Items Tab)

For each ingredient:

1. Click **Add Row**
2. Set `Item Code` → ERPNext auto-fetches name, UOM, default BOM of sub-assemblies
3. Set `Qty`
4. Optionally set `Source Warehouse` and `Operation` (if linked to a specific operation)

> **Tip:** If a sub-assembly item has its own BOM and you want costs to roll up, leave `bom_no` as auto-fetched. To prevent explosion, check `Do Not Explode`.

### Step 4 — (Optional) Enable Operations

Check **With Operations** → the **Operations tab** appears.
See [Section 4](#4-the-operations-tab--in-depth) for full details.

### Step 5 — Save → Review Costs

On save, ERPNext automatically:

1. Fetches raw material rates per the selected `rm_cost_as_per` method
2. Calculates operating costs from workstation hour rates × time
3. Populates the **Exploded Items** tab (full flat BOM with all nested materials)
4. Updates `raw_material_cost`, `operating_cost`, `total_cost`

### Step 6 — Submit

```
Submit → BOM is now usable in Work Orders
```

Submitting also:
- Sets this BOM as default on the Item master (if `Is Default` is checked)
- Updates `BOM Creator` status if linked

---

## 4. The Operations Tab — In Depth

### Enabling the Tab

The Operations tab is **hidden by default**. It appears only when you check:

```
With Operations = ✓
```

> If you uncheck `With Operations`, ERPNext **wipes all rows** from the operations table on save (see `clear_operations()` in `bom.py`).

---

### What the Operations Tab Does

The Operations tab defines the **manufacturing process steps** required to convert raw materials into the finished good. Each row in the table is a single operation (e.g., *Cut Fabric*, *Weld Frame*, *Final Assembly*).

**Effect on the BOM Process:**

1. **Cost Addition** — Each operation adds an `operating_cost` to the BOM.
   `operating_cost = hour_rate × time_in_mins ÷ 60`
   This becomes part of `total_cost = raw_material_cost + operating_cost`.

2. **Work Order Job Cards** — When a Work Order is created from this BOM, ERPNext generates a **Job Card** for each operation row. Workers report time and quantity against Job Cards.

3. **Material Transfer Trigger** — `transfer_material_against` (set at header level) controls whether raw materials are issued when the **Work Order** starts or when each individual **Job Card** is completed.

4. **Operation-wise Material Linking** — Each raw material row in the Items tab has an `operation` field. This ties that material's consumption to a specific operation step, enabling Job Card-level material tracking.

5. **Semi-Finished Goods** — When `Track Semi Finished Goods` is enabled, operations can produce intermediate items (see [Section 7](#7-semi-finished-goods-tracking)).

---

### Operations Tab — Field Reference

| Field | Type | Description |
|---|---|---|
| `operation` | Link → Operation | The operation name (e.g., "Welding", "Assembly") |
| `workstation` | Link → Workstation | Physical machine/station that performs this operation |
| `workstation_type` | Link → Workstation Type | Alternative to a specific workstation; uses type's hour rate |
| `description` | Text | Auto-fetched from the Operation master; editable |
| `time_in_mins` | Float | Estimated time to complete this operation per BOM quantity |
| `batch_size` | Int | How many units of FG are produced in one batch at this operation (default: 1) |
| `hour_rate` | Currency | Cost per hour at this workstation (auto-fetched; overridable) |
| `operating_cost` | Currency | **Computed:** `hour_rate × time_in_mins ÷ 60` |
| `cost_per_unit` | Currency | `operating_cost ÷ batch_size` |
| `set_cost_based_on_bom_qty` | Check | When checked, total op cost = `cost_per_unit × BOM quantity` instead of a flat amount |
| `fixed_time` | Check | Time does not scale with quantity (useful for setup time) |
| `sequence_id` | Int | Order of operations; used when pulling from a Routing |
| `bom_no` | Link → BOM | (Semi-FG mode only) BOM of the intermediate item this operation produces |
| `finished_good` | Link → Item | (Semi-FG mode only) The semi-finished item produced at this step |
| `finished_good_qty` | Float | (Semi-FG mode only) Qty of the semi-FG produced |
| `is_final_finished_good` | Check | (Semi-FG mode only) Marks this as the step producing the ultimate FG |

---

### Using a Routing Template

Instead of manually adding operation rows, you can use a **Routing**:

1. Create a `Routing` record under `Manufacturing → Routing`
2. Add all operations with their workstations and times
3. On the BOM, set `Routing = <your routing name>`
4. Click **Get Routing** (or save — it auto-fetches via `set_routing_operations()`)

This copies all operation rows from the Routing into the BOM's Operations table.

> **Note:** Hour rates are divided by the BOM's `conversion_rate` when copied, so multi-currency BOMs remain accurate.

---

### Operating Cost Calculation Detail

```
For each operation row:
  base_hour_rate   = hour_rate × conversion_rate
  operating_cost   = hour_rate × time_in_mins / 60
  cost_per_unit    = operating_cost / batch_size
  base_op_cost     = operating_cost × conversion_rate

If set_cost_based_on_bom_qty:
  total_op_cost    = cost_per_unit × BOM.quantity
Else:
  total_op_cost    = operating_cost

BOM.operating_cost = SUM(total_op_cost for all operations)
```

Alternatively, if `fg_based_operating_cost` is checked (no Operations tab):

```
BOM.operating_cost = quantity × operating_cost_per_bom_quantity
```

---

### Validation Rules for Operations

ERPNext enforces the following on **Submit**:

- `With Operations = True` → at least one operation row must exist
- Each operation row must have either a `Workstation` **or** a `Workstation Type`
- `transfer_material_against` must be set when operations exist
- `Track Semi Finished Goods` requires at least one operation with `Is Final Finished Good = True`
- If `Track Semi Finished Goods` is enabled and submitted, every operation must have raw materials OR a `bom_no`

---

## 5. Cost Calculation Logic

```
total_cost = raw_material_cost + operating_cost − secondary_items_cost
```

| Component | Source |
|---|---|
| `raw_material_cost` | Sum of `qty × rate` for all Items rows |
| `operating_cost` | Sum of `hour_rate × time_in_mins / 60` for all Operations rows |
| `secondary_items_cost` | Allocated % of raw material cost for scrap/by-products |

**Rate methods for raw materials (`rm_cost_as_per`):**

| Method | Source |
|---|---|
| Valuation Rate | Weighted average from Bin + SLE → Item master fallback |
| Last Purchase Rate | `Item.last_purchase_rate` |
| Price List | Rate from a specified Buying Price List |

---

## 6. Multi-Level BOM & Explosion

When a raw material row has a `bom_no`, ERPNext **explodes** it recursively:

- The **Exploded Items tab** shows the complete flat list of leaf-level raw materials
- This is used by Work Orders when `Use Multi-Level BOM = True`
- Explosion is computed in `update_exploded_items()` → `get_exploded_items()` → `get_child_exploded_items()`

**Recursion protection:** `check_recursion()` walks the entire BOM tree and throws `BOMRecursionError` if a circular reference is detected.

---

## 7. Semi-Finished Goods Tracking

Enable `Track Semi Finished Goods` to model multi-stage production where intermediate items are stocked between operations.

**Setup:**

1. Enable `With Operations`
2. Enable `Track Semi Finished Goods`
3. For each intermediate operation:
   - Set `finished_good` = the semi-FG item
   - Set `bom_no` = the BOM of that semi-FG item
   - Set `finished_good_qty`
4. For the final operation: check `Is Final Finished Good = True` and set `finished_good = <FG item>`

**Effect:**
- ERPNext auto-populates the Items tab with raw materials from each semi-FG BOM
- Each operation gets its own Job Card with input and output items
- Stock entries are created per operation, moving semi-FGs between warehouses

---

## 8. Submitting, Amending & Cancelling

| Action | Effect |
|---|---|
| **Save** | Validates, calculates costs, updates exploded items (no stock impact) |
| **Submit** | BOM becomes usable in Work Orders; sets as default on Item if flagged |
| **Amend** | Creates a new version (`BOM-ITEM-002`); original remains submitted |
| **Cancel** | Sets `is_active = 0`, `is_default = 0`; cannot cancel if used in active parent BOMs |

> Auto-naming: `BOM-{Item}-{sequence}` where sequence is zero-padded (`001`, `002`, …). The system finds the max existing index and increments by 1.

---

## 9. API & Programmatic Usage

### Create BOM via Python (Frappe console / script)

```python
import frappe

bom = frappe.new_doc("BOM")
bom.item = "FINISHED-CHAIR"
bom.quantity = 1
bom.company = "My Company"
bom.rm_cost_as_per = "Valuation Rate"
bom.is_default = 1
bom.with_operations = 1

# Add raw material
bom.append("items", {
    "item_code": "STEEL-PIPE",
    "qty": 4,
    "uom": "Nos",
    "source_warehouse": "Stores - MC",
    "operation": "Welding",
})

# Add operation
bom.append("operations", {
    "operation": "Welding",
    "workstation": "Welding Station 1",
    "time_in_mins": 30,
    "batch_size": 1,
})

bom.insert()
bom.submit()
frappe.db.commit()
```

### Get BOM Items via Whitelisted API

```python
from erpnext.manufacturing.doctype.bom.bom import get_bom_items

items = get_bom_items(
    bom="BOM-FINISHED-CHAIR-001",
    company="My Company",
    qty=10,
    fetch_exploded=1,   # 1 = exploded flat list, 0 = direct items only
)
```

### Update BOM Costs (recalculate rates)

```python
bom = frappe.get_doc("BOM", "BOM-FINISHED-CHAIR-001")
bom.update_cost(update_parent=True, update_hour_rate=True)
```

### Compare Two BOMs

```python
from erpnext.manufacturing.doctype.bom.bom import get_bom_diff

diff = get_bom_diff("BOM-FINISHED-CHAIR-001", "BOM-FINISHED-CHAIR-002")
# diff.row_changed, diff.added, diff.removed
```

---

## 10. Common Errors & Fixes

| Error | Cause | Fix |
|---|---|---|
| `Raw Materials cannot be blank` | Items tab is empty | Add at least one raw material row |
| `Quantity should be greater than 0` | BOM quantity not set | Set `quantity` to 1 or more |
| `BOM recursion: X cannot be parent or child of Y` | A sub-assembly's BOM references back to the parent item | Enable `Do Not Explode` on the recursive item row |
| `Operations cannot be left blank` | `With Operations = True` but no rows on submit | Add at least one operation, or uncheck `With Operations` |
| `Row X: Workstation or Workstation Type is mandatory` | Operation row has neither field set | Set either `workstation` or `workstation_type` |
| `Cannot deactivate or cancel BOM as it is linked with other BOMs` | BOM is used as a sub-assembly BOM in another active BOM | Cancel or update the parent BOM first |
| `Cost allocation between FG and secondary items should equal 100%` | `cost_allocation_per` values don't sum to 100 | Adjust % across FG and all secondary items |
| `BOM X must be submitted` | Referenced sub-assembly BOM is in Draft | Submit the child BOM before saving the parent |
| `Currency of BOM #X should be equal to selected currency` | Sub-assembly BOM uses a different currency | Ensure all nested BOMs share the same currency |

---

*Generated by analysis of [`frappe/erpnext`](https://github.com/frappe/erpnext) source — `erpnext/manufacturing/doctype/bom/bom.py` (61,984 lines) and `bom.json`.*
