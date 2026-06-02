# Work Order — Generic DocType Picker Refactor

**Branch:** `release/play-store-beta-1`  
**Scope:** Work Order form — Item, BOM, and Warehouse field pickers  
**Goal:** Replace all field-specific bottom sheets with a single reusable `DocTypePickerBottomSheet` utility that is flexible, multi-column capable, cache-first, barcode-aware, and consistent with Frappe Link field filter behaviour.

---

## Background

The Work Order form currently uses separate, purpose-built bottom sheets for Item, BOM, and Warehouse selection. These share no infrastructure, cannot be easily extended with extra columns or filters, and do not support barcode-prefill. This refactor replaces them with a generic, globally reusable picker that can accommodate any ERPNext DocType.

### Design decisions

- **Multi-column rows from day one** — rows support `primaryField`, `secondaryField`, `subtitleFields`, and `columns` so they can render rich metadata without custom widgets per DocType.
- **Item picker row layout** — Item Code (primary), Item Name (secondary), `item_group` / `variant_of` / `country_of_origin` as subtitle metadata.
- **Frappe-style filtered Link field** — filters are passed in config and respected server-side, consistent with how `frappe/frappe` handles Link field filters.
- **Cached-first, explicit refresh** — picker reads local cache first; a refresh action fetches live ERPNext data.
- **Barcode opt-in per picker** — reuses `scanWorker` + `eventSink` from the Stock Entry / Delivery Note barcode flow; each picker opts in independently.
- **Business logic stays in the controller** — the generic picker fires a selection callback; all Work Order side effects (auto-fetch BOMs, auto-set UOM, refresh operations, etc.) live in the Work Order form controller only.

---

## Commit Plan

### Commit 1 — `feat(ui): add generic DocType picker models and bottom sheet shell`

#### Checklist

- [ ] Create `DocTypePickerConfig` with fields:
  - `doctype`
  - `title`
  - `primaryField`
  - `secondaryField`
  - `subtitleFields`
  - `columns: List<DocTypePickerColumn>`
  - `searchFields`
  - `filters`
  - `cacheKey`
  - `allowRefresh`
  - `enableBarcodeScan`
  - optional `subtitleFormatter(Map row)`
  - optional `selectabilityResolver(Map row) → bool`
- [ ] Create `DocTypePickerColumn` with fields:
  - `key`
  - `label`
  - `flex`
  - `minWidth`
  - `valueBuilder(Map row)`
  - optional `align`
  - optional `isPrimary`
  - optional `visibleOnMobile`
- [ ] Add `DocTypePickerBottomSheet` widget with:
  - title bar
  - search text field
  - optional refresh action button
  - scrollable list area
  - loading / empty / error states
  - selection callback
- [ ] Implement responsive row layout:
  - multi-column/table-like header + aligned cells on wider widths
  - stacked compact card on mobile
- [ ] Render primary field dominant, secondary field muted, subtitle metadata faint and joined with `•` separator
- [ ] Hide empty subtitle parts — do not show placeholder dashes

#### Acceptance

- [ ] Bottom sheet opens and displays mocked rows correctly
- [ ] Rows show primary, secondary, and subtitle metadata in correct visual hierarchy
- [ ] No ERPNext API calls made yet
- [ ] No Work Order integration yet

---

### Commit 2 — `feat(data): add generic DocType picker datasource with cache-first loading and refresh`

#### Checklist

- [ ] Add a picker repository/service method for generic DocType queries
- [ ] Support query parameters: `doctype`, `fields`, `filters`, `searchText`, optional `limit`
- [ ] Return generic `List<Map<String, dynamic>>` rows containing all requested fields
- [ ] Read from local cache first when a `cacheKey` is provided
- [ ] Add explicit `refresh()` method that bypasses cache and fetches live from ERPNext API
- [ ] Expose loading, error, and empty states to the bottom sheet

#### Acceptance

- [ ] Picker can load real rows from API or local cache
- [ ] Manual refresh replaces cache with live data
- [ ] Query is generic enough for Item, BOM, and Warehouse without modification

---

### Commit 3 — `feat(scan): add reusable barcode-prefill integration to DocType picker`

#### Checklist

- [ ] Reuse existing `scanWorker` and `eventSink` pattern from Stock Entry / Delivery Note barcode flow
- [ ] Wire scan subscription into picker lifecycle: subscribe on open, dispose on close
- [ ] On barcode scan event:
  - [ ] Prefill search text field with scanned value
  - [ ] Trigger list refresh / filter with scanned text
  - [ ] Do **not** auto-select any result — user must tap to confirm
- [ ] Barcode support is opt-in via `enableBarcodeScan: true` in config
- [ ] Pickers with `enableBarcodeScan: false` are completely unaffected

#### Acceptance

- [ ] Scanner input fills search field and narrows list in a barcode-enabled picker
- [ ] User can still type manually or tap any row regardless of scan
- [ ] Scan subscription does not leak after bottom sheet is dismissed

---

### Commit 4 — `feat(item): migrate Item field to generic DocType picker`

#### Checklist

- [ ] Replace existing Item field bottom sheet / tap handler in Work Order form
- [ ] Configure Item picker:
  - `doctype`: `Item`
  - `filters`: `[["enabled", "=", 1], ["is_stock_item", "=", 1]]`
  - `primaryField`: `item_code`
  - `secondaryField`: `item_name`
  - `subtitleFields`: `["item_group", "variant_of", "country_of_origin"]`
  - extra column on wider layouts: `stock_uom`
  - `enableBarcodeScan`: `true`
- [ ] Search should match at least `item_code` and `item_name`
- [ ] Format subtitle as joined parts, e.g. `Raw Material • Variant of BASE-WIDGET • UAE`
  - Omit any subtitle field that is null or empty
  - Render `variant_of` with a prefix label: `Variant of X`
  - Render `item_group` and `country_of_origin` as plain values

#### Acceptance

- [ ] Item picker opens and shows only enabled stock items
- [ ] Item Code is visually primary
- [ ] Item Name is visually secondary
- [ ] Subtitle metadata renders joined and omits empty parts
- [ ] Barcode scan prefills search and narrows the list
- [ ] Manual tap selection works correctly
- [ ] No Work Order side effects fired yet (those are in Commit 5)

---

### Commit 5 — `feat(item): wire Item selection side effects in Work Order form controller`

#### Checklist

- [ ] In Work Order form controller, handle Item picker selection callback:
  - [ ] Set selected item value / controller
  - [ ] Update item text display
  - [ ] Auto-set UOM from selected item's `stock_uom`
  - [ ] Clear BOM value and BOM text if selected item has changed
  - [ ] Auto-fetch BOMs for the newly selected item
  - [ ] Refresh operations
  - [ ] Refresh stock summary
- [ ] Keep all of the above logic in the Work Order form controller, **not** inside the generic picker

#### Acceptance

- [ ] Selecting a new item updates UOM automatically
- [ ] Stale BOM from a previous item is cleared
- [ ] BOMs list is auto-fetched after item selection
- [ ] Operations and stock summary refresh after item selection
- [ ] Existing Work Order form validation still passes

---

### Commit 6 — `feat(bom): migrate BOM field to generic DocType picker filtered by selected Item`

#### Checklist

- [ ] Replace existing BOM field bottom sheet / tap handler in Work Order form
- [ ] Validate that an Item is selected before opening the BOM picker
  - If no item is selected, show a friendly inline validation message and do not open the picker
- [ ] Configure BOM picker:
  - `doctype`: `BOM`
  - `filters`: `[["item", "=", selectedItemCode]]` — dynamic filter based on current form state
  - `enableBarcodeScan`: `false`
- [ ] BOM selection remains **required** for form validation — do not relax this constraint
- [ ] On BOM selection:
  - [ ] Set BOM value / controller
  - [ ] Update BOM text display
  - [ ] Trigger any dependent data refresh if needed

#### Acceptance

- [ ] BOM picker only opens if an item is already selected
- [ ] BOM list contains only BOMs for the currently selected item
- [ ] Selecting a BOM updates form state correctly
- [ ] Form validation still requires a BOM before submission

---

### Commit 7 — `feat(warehouse): migrate WIP and FG Warehouse fields to generic picker with leaf-only filter`

#### Checklist

- [ ] Replace WIP Warehouse bottom sheet with generic picker
- [ ] Replace FG Warehouse bottom sheet with generic picker
- [ ] Both pickers share the same base Warehouse config:
  - `doctype`: `Warehouse`
  - `filters` or `selectabilityResolver`: restrict to warehouses of type `Warehouse` only — group nodes cannot be selected
- [ ] Give each picker a distinct title:
  - WIP Warehouse picker: `Select WIP Warehouse`
  - FG Warehouse picker: `Select Target Warehouse`
- [ ] On selection: set respective warehouse value / controller and trigger any downstream validation

#### Acceptance

- [ ] Both warehouse fields use the same generic picker infrastructure
- [ ] Group warehouse nodes are not selectable (either filtered out server-side or shown disabled)
- [ ] Selecting a warehouse updates the correct form field
- [ ] Existing form flow remains intact

---

### Commit 8 — `chore(ui): polish generic DocType picker for app-wide reuse`

#### Checklist

- [ ] Tighten row spacing and overflow/truncation behaviour
- [ ] Add subtle column header labels for multi-column layout
- [ ] Ensure subtitle truncates cleanly to one line on mobile, up to two lines on larger layouts
- [ ] Improve empty state — friendly message + icon, never just blank
- [ ] Improve error state — retry action, not a raw error string
- [ ] Add refresh UX polish — loading indicator during refresh
- [ ] Add inline dartdoc comments on `DocTypePickerConfig`, `DocTypePickerColumn`, and `DocTypePickerBottomSheet` for future reuse
- [ ] Confirm no field-specific hacks remain inside the generic widget

#### Acceptance

- [ ] Picker is ready to be the standard reusable selector for any DocType in the app
- [ ] All states (loading, empty, error, populated) look intentional and polished
- [ ] No Work Order-specific logic exists inside the generic picker

---

## PR Slicing

| PR | Commits | Description |
|----|---------|-------------|
| PR 1 | 1, 2, 3 | Generic picker infrastructure — UI shell, data layer, barcode integration |
| PR 2 | 4, 5 | Item picker migration + Work Order item selection side effects |
| PR 3 | 6 | BOM picker migration with item-filtered results |
| PR 4 | 7, 8 | Warehouse picker migration + picker polish |

---

## Done Checklist

The work is complete when all of the following are true:

- [ ] Item, BOM, and Warehouse fields all use the new generic `DocTypePickerBottomSheet`
- [ ] Item picker supports barcode-prefill with manual override
- [ ] Item list respects `enabled = 1` and `is_stock_item = 1` filters
- [ ] BOM picker is filtered by the currently selected Item
- [ ] BOM selection is required for Work Order form validation
- [ ] Warehouse picker blocks group nodes — only selectable leaf warehouses can be picked
- [ ] Picker supports cache-first loading with explicit live refresh
- [ ] No Work Order business logic lives inside the generic picker widget
- [ ] All picker states (loading, empty, error) are designed and polished
- [ ] Inline dartdoc comments exist on all public picker classes and config models

---

## Suggested File Locations

| File | Purpose |
|------|---------|
| `lib/app/modules/global_widgets/doctype_picker_bottom_sheet.dart` | Generic picker widget |
| `lib/app/modules/global_widgets/doctype_picker_config.dart` | Config and column models |
| `lib/app/data/repositories/doctype_picker_repository.dart` | Cache-first query + refresh |
| `lib/app/modules/work_order/form/work_order_form_controller.dart` | Item/BOM/Warehouse side effects |
| `lib/app/modules/work_order/form/work_order_form_screen.dart` | Picker triggers and form wiring |

---

*Document created: 2026-03-30*  
*Branch: `release/play-store-beta-1`*
