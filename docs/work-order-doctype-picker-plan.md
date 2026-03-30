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
