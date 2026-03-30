# Work Order — Generic DocType Picker Implementation Plan

**Branch:** `release/play-store-beta-1`  
**Scope:** Item field, BOM No field, WIP Warehouse, FG Warehouse  
**Goal:** Replace all ad-hoc bottom sheet selectors with a reusable, multi-column-capable generic DocType picker that respects Frappe-style filters, supports barcode-prefill, and is cache-first with manual refresh.

---

## Architecture

| Layer | Responsibility |
|---|---|
| `DocTypePickerBottomSheet` | Generic UI shell — search, list, columns, subtitle metadata, states |
| `DocTypePickerConfig` | Per-DocType config object: doctype, filters, columns, subtitle, cache key |
| `DocTypePickerColumn` | Column definition: key, label, flex, minWidth, isPrimary, visibleOnMobile |
| Picker datasource/repository | Cache-first loading, live refresh, generic Frappe API query |
| `WorkOrderFormController` | All Work Order side effects — UOM, BOM fetch, operations refresh |

**Rule:** All Work Order business logic stays in the controller. The generic picker has no knowledge of Item, BOM, or Warehouse specifics.

---

## Item Row Layout

| Slot | Field | Style |
|---|---|---|
| Primary | `item_code` | Bold, dominant |
| Secondary | `item_name` | Muted, one line |
| Subtitle | `item_group` · `Variant of {variant_of}` · `country_of_origin` | Faint, truncated, empty parts hidden |
| Extra column (wide) | `stock_uom` | Right-aligned label |

---

## Commit 1 — Generic DocType Picker UI Shell

**Commit message:**

### Checklist
- [ ] Create `DocTypePickerConfig` with fields: `doctype`, `title`, `displayField`, `searchFields`, `filters`, `columns`, `subtitleFields`, `subtitleFormatter`, `allowRefresh`, `cacheKey`, `enableBarcodeScan`
- [ ] Create `DocTypePickerColumn` with fields: `key`, `label`, `flex`, `minWidth`, `isPrimary`, `align`, `visibleOnMobile`, `valueBuilder`
- [ ] Create `DocTypePickerBottomSheet` widget with:
  - Title bar + dismiss
  - Search input field
  - Optional refresh icon/action
  - List area with `ListView` or `ScrollView`
  - Row rendering: multi-column/table-like on wider layouts; stacked compact on mobile
  - Primary field bold and dominant
  - Secondary field muted
  - Subtitle row: joined metadata, hide empty parts, truncate to one line
  - Loading state (shimmer or spinner)
  - Empty state with friendly message
  - Error state with retry option
  - `onSelected(Map<String, dynamic> row)` callback
- [ ] No ERPNext data fetch in this commit — use mocked rows

### Acceptance
- [ ] Bottom sheet opens with mocked data
- [ ] Multi-column row renders correctly on normal phone width
- [ ] Stacked layout works on narrow widths
- [ ] Primary field is visually dominant
- [ ] Subtitle hides when all subtitle fields are empty
- [ ] Dismiss works

---

## Commit 2 — Cache-First Datasource with Live Refresh

**Commit message:**

### Checklist
- [ ] Add picker repository/service method accepting: `doctype`, `fields`, `filters`, `searchText`, optional `limit`
- [ ] Implement cache-first read on open
- [ ] Implement explicit `refresh()` method that bypasses cache and hits live ERPNext API
- [ ] Return generic `List<Map<String, dynamic>>` rows containing all requested fields
- [ ] Wire datasource into `DocTypePickerBottomSheet` — replace mocked rows
- [ ] Ensure `item_code`, `item_name`, `item_group`, `variant_of`, `country_of_origin`, `stock_uom` are all fetchable via field list param

### Acceptance
- [ ] Picker loads data from cache on open
- [ ] Manual refresh triggers live API fetch
- [ ] Refresh does not block UI before results arrive
- [ ] Generic — no Item/BOM/Warehouse hardcoding in datasource layer

---

## Commit 3 — Reusable Barcode Prefill via scanWorker/eventSink

**Commit message:**

### Checklist
- [ ] Reuse existing `scanWorker` + `eventSink` pattern from Stock Entry / Delivery Note barcode flow
- [ ] Add opt-in flag: `DocTypePickerConfig.enableBarcodeScan`
- [ ] On scan:
  - [ ] Prefill search text input with scanned value
  - [ ] Trigger list filter/refresh
  - [ ] Do NOT auto-select — user must tap a row
- [ ] Subscribe to scan events when bottom sheet opens
- [ ] Dispose subscription when bottom sheet closes
- [ ] Pickers with `enableBarcodeScan: false` are completely unaffected

### Acceptance
- [ ] Barcode scan prefills search and narrows list
- [ ] Manual override still works after scan
- [ ] Subscription is cleaned up on dismiss
- [ ] Non-barcode pickers unaffected

---

## Commit 4 — Item Field Migration to Generic Picker

**Commit message:**

### Checklist
- [ ] Replace existing Item bottom sheet / tap handler with generic picker
- [ ] Item picker config:
  - [ ] `doctype: 'Item'`
  - [ ] `filters: { disabled: 0, is_stock_item: 1 }`
  - [ ] `primaryField: 'item_code'`
  - [ ] `secondaryField: 'item_name'`
  - [ ] `subtitleFields: ['item_group', 'variant_of', 'country_of_origin']`
  - [ ] `subtitleFormatter`: join non-empty parts with ` · `, prefix `variant_of` with `"Variant of "`
  - [ ] Extra column (wide): `stock_uom`
  - [ ] `enableBarcodeScan: true`
  - [ ] `allowRefresh: true`
- [ ] Search matches `item_code` and `item_name` at minimum
- [ ] Subtitle truncates cleanly to one line on mobile

### Acceptance
- [ ] Item picker shows only enabled stock items
- [ ] Item Code is visually primary
- [ ] Item Name is secondary/muted
- [ ] Subtitle shows item_group, variant_of (with prefix), country_of_origin — hides empty parts
- [ ] Barcode scan prefills search
- [ ] Manual selection works correctly

---

## Commit 5 — Item Selection Side Effects

**Commit message:**

### Checklist
- [ ] On item selected in controller:
  - [ ] Set selected item value and text controller
  - [ ] Auto-set UOM from `stock_uom`
  - [ ] Clear stale BOM value if item changed
  - [ ] Auto-fetch BOMs for newly selected item
  - [ ] Refresh operations
  - [ ] Refresh stock summary
- [ ] All side effect logic lives in `WorkOrderFormController`, not in generic picker
- [ ] Existing Work Order validation flow is preserved

### Acceptance
- [ ] Selecting a new Item refreshes all dependent fields
- [ ] BOM is cleared when item changes
- [ ] UOM is auto-set correctly
- [ ] Operations and stock summary refresh
- [ ] No regressions in existing form validation

---

## Commit 6 — BOM No Field Migration to Generic Picker

**Commit message:**

### Checklist
- [ ] Replace existing BOM bottom sheet / tap handler with generic picker
- [ ] Prevent opening BOM picker if no Item is selected — show friendly snackbar/toast
- [ ] BOM picker config:
  - [ ] `doctype: 'BOM'`
  - [ ] `filters: { item: selectedItem, is_active: 1 }`
  - [ ] `primaryField: 'name'` (BOM name/ID)
  - [ ] `secondaryField: 'item'`
  - [ ] `enableBarcodeScan: false`
  - [ ] `allowRefresh: true`
- [ ] On BOM selected:
  - [ ] Set BOM value and text controller
  - [ ] Mark BOM as valid for form validation
  - [ ] Refresh dependent data if needed
- [ ] BOM remains required for Work Order form submission

### Acceptance
- [ ] BOM picker only shows BOMs for selected Item
- [ ] Tapping BOM field before Item shows validation message
- [ ] BOM selection satisfies required field validation
- [ ] BOM list refreshes when Item changes

---

## Commit 7 — Warehouse Fields Migration to Generic Picker

**Commit message:**
