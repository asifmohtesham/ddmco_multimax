## [Unreleased] — SharedRackField Universal Refactor

> Architectural refactor of `SharedRackField` so any DocType controller can
> host the widget by implementing a narrow interface — no inheritance of
> `ItemSheetControllerBase` required.

---

### ♻️ Refactors

#### `SharedRackField` — Universal DocType Support (Commits 1–7)

**Commit 1 — `RackFieldDelegate` interface extracted**

- Created `lib/app/shared/item_sheet/rack_field_delegate.dart`.
- Defines the minimum contract a controller must satisfy to drive
  `SharedRackField`: reactive state (`isRackValid`, `isValidatingRack`,
  `rackError`, `rackStockTooltip`), text/focus controllers, `rackBalanceFor`,
  `resetRack`, and `validateRack`.
- Pure Dart — no GetX or Flutter import; implementable by any class.

**Commit 2 — `RackBrowseDelegate` interface extracted**

- Created `lib/app/shared/item_sheet/rack_browse_delegate.dart`.
- Declares `canBrowseRacks`, `browseRacks`, and `RackPickerResult` contract
  so picker-capable controllers advertise the capability on the type system
  without coupling the widget to a concrete controller.

**Commit 3 — `RackFieldWithBrowseDelegate` composite interface**

- Created `lib/app/shared/item_sheet/rack_field_with_browse_delegate.dart`.
- Combines `RackFieldDelegate` + `RackBrowseDelegate` into a single interface
  that `SharedRackField` (post Commit 6) depends on.
- Documents the phased adoption path (Commits 3 → 9).

**Commit 4 — `RackPickerResult` value type**

- Created `lib/app/shared/item_sheet/rack_picker_result.dart`.
- Immutable data class carrying `rackId` (and optional metadata) returned
  by `browseRacks()`.

**Commit 5 — `ItemSheetControllerBase` adopts `RackFieldWithBrowseDelegate`**

- Added `implements RackFieldWithBrowseDelegate` to the `abstract class`
  declaration.
- Provided default implementations of `rackBalanceFor` (map lookup via
  `rackStockMap`), `canBrowseRacks` (`false`), `browseRacks` (`null`), and
  `handleRackPicked` (write `rackId` + call `validateRack`).
- Zero changes required in any concrete controller (SE, DN, PR, PS, PO).

**Commit 6 — `SharedRackField.c` type widened to `RackFieldWithBrowseDelegate`**

- Changed `final ItemSheetControllerBase c` → `final RackFieldWithBrowseDelegate c`
  in `lib/app/shared/item_sheet/widgets/shared_rack_field.dart`.
- `_rackBalance` helper updated to call `c.rackBalanceFor(rack)` via the
  interface (was already correct post Commit 1 adoption).
- `balanceOverride` callback pattern preserved — existing DN call site
  unchanged.
- `onPickerTap` callback wired through to `_EditModeRack` → `ValidatedRackField`
  for future picker integration (Commits 7–9).
- All existing call sites compile without any changes; the concrete controllers
  satisfy the interface via the base-class adoption in Commit 5.

**Commit 7 — Delivery Note wires concrete `browseRacks()` override**

- `DeliveryNoteItemFormController` now overrides `canBrowseRacks` and
  `browseRacks()` in `delivery_note_item_form_controller.dart`.
- `canBrowseRacks` returns `true` when `itemCode` is non-empty. The
  warehouse filter toggle in `RackPickerSheet` handles warehouse scoping at
  the UI level — no controller-side warehouse gate needed.
- `browseRacks()` implements the full `RackPickerController` lifecycle:
  1. `Get.put(RackPickerController(), tag: 'dn_rack_picker')`
  2. `ctrl.load(itemCode, batchNo, warehouse, requestedQty, currentRack,
     fallbackMap: rackStockMapRx)` — non-blocking, sheet opens immediately
     with spinner while data loads.
  3. `showModalBottomSheet(…, builder: (_) => RackPickerSheet(…))`
  4. Map `onSelected` String → `RackPickerResult` (reads `availableQty`
     from the controller entry list so the snapshot matches what the user saw).
  5. `Get.delete<RackPickerController>(tag: 'dn_rack_picker')` in a
     `finally` block — no leak on dismiss or error.
- Re-entrant call guard: `browseRacks()` returns `null` immediately if
  `isValidatingRack.value` is already `true`.
- `handleRackPicked()` is **inherited** from `ItemSheetControllerBase`
  (write `rackId` → `rackController`, call `validateRack`) — no override
  needed for DN's single rack field.
- New imports added: `rack_picker_controller.dart`, `rack_picker_result.dart`,
  `rack_picker_sheet.dart`.

#### Next steps (planned)

- **Commit 8** — QC pass on DN rack picker end-to-end (call `handleRackPicked`
  from the DN item sheet orchestrator; verify picker button enabled/disabled
  state; test dismiss-without-selection path).
- **Commit 9** — Stock Entry follows with SE-specific source/target rack
  picker wiring (`sourceRackController` override).

---

## [1.4.2+11-beta] — 2026-03-25

> Beta release targeting internal QA on the `release/play-store-beta-1` branch.  
> Complete rewrite of the rack auto-fill system across Stock Entry and Delivery Note.
> Rack selection is now warehouse-constrained and quantity-triggered; the previous
> implementation was warehouse-blind and fired at batch-validation time.

---

### 🐛 Bug Fixes

#### Item Sheet — Rack Auto-Fill (Stock Entry + Delivery Note)

- **Warehouse-blind autofill fixed** — the previous `autoFillBestRack()` picked the
  highest-qty rack from `rackStockMap` with no regard for the parent document's Source
  Warehouse. This could produce an autofilled rack whose ERPNext `warehouse` field
  differed from the header, failing server-side validation silently.  
  The new `autoFillRackForQty(double qty)` method filters candidates by derived
  warehouse before selecting the best rack.

- **Qty-blind autofill fixed** — rack autofill previously fired at batch-validation
  time, before the operator had entered a quantity. The selected rack could hold less
  stock than the operator intended to issue, but no warning was raised and the sheet
  appeared valid.  
  Autofill now fires on the **first qty-field transition from blank/zero → positive**,
  so the requested quantity is always known at selection time.

- **Insufficient-stock fallback** — if no matching-warehouse rack holds `qty >= requested`,
  the highest-qty matching rack is still autofilled but a `GlobalSnackbar.warning` is
  raised immediately. `baseValidate()` will independently block Save until the operator
  resolves the shortfall.

- **SE source-rack wiring gap fixed** — `StockEntryItemFormController` uses
  `sourceRackController` (a separate TEC) for its source-rack field, not the base
  `rackController`. The mixin now exposes two protected override hooks so SE can redirect
  the write to the correct TEC and trigger the correct validator:
  - `autoFillRackController` → `sourceRackController` (SE override)
  - `onAutoFillRackSelected` → `validateDualRack(rack, true)` (SE override)

- **Off-by-one loop bound removed** — the old SE `_autoFillBestSourceRack()` used
  `i < result.length - 1` as its loop bound to skip a presumed "totals row", which
  silently dropped the last real rack row when the API returned an even number of racks.
  The Stock Balance report appends a totals row with `rack == null`; the base
  `fetchAllRackStocks()` guard `if (r != null && r.isNotEmpty && qty > 0)` skips it
  correctly without any loop-bound manipulation.

---

### ♻️ Refactors

#### `AutoFillRackMixin` (`item_sheet_mixin_autofill_rack.dart`)

- `autoFillBestRack()` (sync, warehouse-blind, qty-blind) replaced by:
  - `autoFillRackForQty(double qty)` — warehouse-constrained core logic
  - `initAutoFillListener()` — attaches a one-shot qty TEC listener (call from `initialise()`)
  - `disposeAutoFillListener()` — removes the listener cleanly (call from `onClose()`)
  - `autoFillRackController` getter — override hook; default `rackController`
  - `onAutoFillRackSelected(String rack)` method — override hook; default `validateRack(rack)`

#### Rack Naming Convention

Rack asset codes follow a 4-part dash-delimited pattern:

```
KA  - WH   - DXB1 - 101A
[0]   [1]    [2]    [3]
│      │      │      └─ Shelf ID: 3-digit rack number + shelf letter
│      │      └──────── Country / location counter  (DXB1, DXB2, …)
│      └─────────────── Location type  (WH = Warehouse, POS = Point-of-Sale)
└────────────────────── Company prefix  (KA)
```

The corresponding ERPNext Warehouse name is derived locally as:
```
parts[1]-parts[2] + ' - ' + parts[0]
  e.g.  KA-WH-DXB1-101A  →  "WH-DXB1 - KA"
```
No extra API call is required. Names with fewer than 4 parts are treated as
non-matching and autofill skips them safely.

#### Autofill Selection Order (per `autoFillRackForQty`)

| Priority | Condition | Action |
|----------|-----------|--------|
| 1 | Rack in `resolvedWarehouse` AND `qty ≥ requested` | Fill highest-qty match — silent |
| 2 | Rack in `resolvedWarehouse` but `qty < requested` | Fill highest-qty match + ⚠ snackbar |
| 3 | No rack belongs to `resolvedWarehouse` | Skip autofill + ⚠ snackbar |
| 4 | `resolvedWarehouse` is null / empty | Skip autofill silently |

#### Delivery Note — `DeliveryNoteItemFormController`

- Removed `fetchAllRackStocks()` override that called `autoFillBestRack()`.
- `isAddMode` now set before `initBaseListeners()` / `initAutoFillListener()`.
- `initAutoFillListener()` wired in `initialise()`; `disposeAutoFillListener()` wired in `onClose()`.
- `fetchAllRackStocks()` still called from `initialise()` to pre-populate
  `rackStockMap` for the rack tooltip/dropdown chip — only the autofill side-effect is removed.

#### Stock Entry — `StockEntryItemFormController`

- Deleted `_autoFillBestSourceRack()`, `_autoFillBestTargetRack()`, `triggerAutoFill()`.
- Removed `unawaited(_autoFillBestSourceRack())` call from `validateBatch()`.
- Added `AutoFillRackMixin` to `with` clause.
- Overrides `autoFillRackController → sourceRackController`.
- Overrides `onAutoFillRackSelected → validateDualRack(rack, true)`.

#### Base — `ItemSheetControllerBase.fetchAllRackStocks()`

- Added block comment documenting the Stock Balance report total-row behaviour
  and explaining why the `r != null && r.isNotEmpty` guard is the correct
  mechanism (no off-by-one bound needed).

---

## [1.4.1+10-beta] — 2026-03-13

> Beta release targeting internal QA on the `release/play-store-ui-stock-entry` branch.  
> Builds on `1.4.1+9-beta` with three targeted UX/reliability fixes for the Stock Entry form.

---

### 🐛 Bug Fixes

#### Stock Entry — Form Screen
- **Back button now respects `PopScope`** — replaced `Get.back()` with `Navigator.maybePop(context)` in `MainAppBar`. The unsaved-changes confirmation dialog is correctly triggered when the user presses back on a dirty document (`isDirty == true`). Previously `Get.back()` bypassed Flutter's `PopScope` guard entirely, so the dialog never appeared.
- **Reference No false-dirty on load** — `customReferenceNoController` listener now only calls `_markDirty()` when the field value actually differs from the server-loaded snapshot (`_initialReferenceNo`). A focus tap or programmatic text population no longer flips `isDirty`. The field is also rendered `readOnly: true` with a lock icon, matching its system-assigned semantics (value set by POS upload ID or Material Request ref, not by the user).

---

### ✨ New Features

#### Stock Entry — Form Screen
- **Reload button in app bar** — a `Icons.refresh` action button now appears in the `MainAppBar` for any existing document (edit or view mode). Tapping it calls `controller.reloadDocument()` to re-fetch the latest server state; the button is disabled while a save is in progress. Hidden for brand-new unsaved entries.

#### Global
- **`MainAppBar.onReload`** — new optional `VoidCallback? onReload` parameter added to `MainAppBar`. When non-null, a reload `IconButton` is inserted between custom actions and the save button, grayed out while `isSaving` is true.

---

## [1.4.1+9-beta] — 2026-03-13

> Beta release targeting internal QA on the `release/play-store-ui-stock-entry` branch.
> Builds on `1.4.1+8` with a full overhaul of the Stock Entry module UX, critical scanning fixes, and platform-wide reliability improvements.

---

### ✨ New Features

#### Stock Entry — Item Form Sheet
- **Auto-validate fields** as the user types; field borders switch to check icons on success.
- **Derived warehouse display** shown inline next to the rack field so users can confirm the resolved location at a glance.
- **Press-and-hold quantity controls** — long-press `+`/`−` buttons for rapid incrementing/decrementing with haptic contextual info.
- **Item-level warehouse override** — `Source Warehouse` and `Target Warehouse` dropdowns now appear per-item inside the sheet, following priority: item-level → rack-derived → document-level.
- **Balance chips** — batch balance and rack available-stock chips are now shown in edit mode (not just add mode), populated immediately when the sheet opens.

#### Stock Entry — Form Screen
- **Interactive schedule fields** — `Date` and `Time` in the *Details* tab now open native pickers on tap via `pickPostingDate` / `pickPostingTime`.
- **Tappable FROM / TO labels** — tapping the `FROM` or `TO` label (not just the warehouse value) now opens the warehouse selection sheet; ripple feedback added via `InkWell`.
- **Tab renamed** — first tab is now **Details** (was *Logistics*) for clarity.

#### Stock Entry — List Screen
- **Filter chips** — active filters and search query are surfaced as dismissible chips beneath the app bar.
- **End-of-results footer** — replaces the infinite spinner with a "No more entries" footer when `hasMore` is false.

#### Global / Cross-module
- **Centralised `OptimisticLockingMixin`** — unified `isStale` flag + `TimestampMismatchError` (HTTP 409) handling across Stock Entry, Material Request, Packing Slip, Purchase Receipt, Purchase Order, Delivery Note, Batch, and POS Upload.
- **Centralised `SaveIconButton`** via `MainAppBar` — consistent save button (with spinner) shared across all form screens.
- **Global server-side search** (`GlobalSearchDelegate` + `GlobalSearchService`) — metadata-driven, field-type-aware search with session caching; enabled on Item and Purchase Order lists.
- **Batch global search** — search icon in Batch list app bar opens `GlobalSearchDelegate` for server-side batch lookup.

---

### 🐛 Bug Fixes

#### Stock Entry
- **Batch + rack validation gates** tightened per entry type: Material Receipt requires target rack; Material Issue requires source rack; Material Transfer requires both — the auto-submit timer no longer fires prematurely.
- **Balance chips invisible in edit mode** — fixed two root causes: dedicated `isLoadingBatchBalance` / `isLoadingRackBalance` flags introduced; `ever(bsItemSourceWarehouse)` race condition resolved so chips show a spinner immediately on sheet open.
- **Bottom sheet staying open** — `GlobalItemFormSheet` refactored from `StatefulWidget` → scoped `ItemFormSheetController` (GetX); `Get.back()` moved into `addItem()` and guarded against duplicate opens.
- **Duplicate sheet from rapid scans** — auto-submit timer is now cancelled and `Navigator.pop` is used in `addItem()` to prevent a second sheet opening.
- **GetX snackbar race / crash** — removed `closeCurrentSnackbar()` call (GetX queue is self-managing); replaced `Get.back()` with `Navigator.of(context).pop()` on close/delete buttons to avoid crashing an uninitialised `SnackbarController`.

#### Delivery Note
- **Dirty state** no longer incorrectly triggers for submitted/cancelled documents.
- **Header validation before scan** — `_validateHeaderBeforeScan()` prevents item scanning when customer is missing.
- **Rack partial-entry** — rack must be fully validated before saving.
- **Modified timestamp** included in `toJson` for optimistic locking.

#### Purchase Receipt
- **Duplicate scan guard** — `isScanning` flag blocks concurrent scan events.
- **PO item validation** — prevents scanning items absent from the linked Purchase Order.

#### Batch
- **Dirty-state false-positive** — `_isFetching` guard prevents the dirty checker from running during programmatic form population.
- **Batch ID stability** — random suffix preserved if the associated item is changed.
- `purchase_order` field corrected to `custom_purchase_order` in the `Batch` model.

---

### ♻️ Refactors

- `GlobalItemFormSheet` rewritten as a scoped GetX controller (`ItemFormSheetController`) — removes all `StatefulWidget` local state.
- `GlobalSearchDelegate` thinned to a pure UI layer; data/cache logic extracted into `GlobalSearchService`.
- `MainAppBar` now owns the `SaveIconButton`; redundant local save buttons removed from `StockEntryFormScreen` and `BatchFormScreen`.
- `StockEntryFormController` stale-check and manual dialog calls removed in favour of `OptimisticLockingMixin`.
- `PurchaseReceiptFilterBottomSheet` replaces the old `AlertDialog`-based filter with a full sort + multi-filter sheet (`GlobalFilterBottomSheet`).

---

## [1.1.0]

### New Features

*   **Batch Management:**
    *   Introduced `BatchFormScreen` for creating and editing batches.
    *   Added ability to generate Batch IDs automatically using Item EAN and random characters.
    *   Integrated QR code and Barcode (Code128/EAN8) generation for batches with preview.
    *   Added support for exporting batch labels as PNG images and PDF vectors.
    *   Added Item and Purchase Order selection via searchable bottom sheets.

*   **POS Upload:**
    *   Added `PosUploadFormScreen` to manage POS uploads.
    *   Features include viewing upload details, updating status and totals, and searching/listing items.

*   **ToDo Management:**
    *   Added `ToDoScreen` for tracking tasks.
    *   Features include infinite scrolling, filtering (by status/name), and expandable cards for detailed views.
    *   Added HTML content support for task descriptions.

*   **Purchase Order & Material Request:**
    *   Added `PurchaseOrderFormScreen`.
    *   Enhanced `MaterialRequestScreen` and associated forms.

### Improvements

*   **UI/UX:**
    *   Added `PopScope` to forms to prevent accidental data loss (unsaved changes dialog).
    *   Integrated `AppNavDrawer` into main screens for consistent navigation.
    *   Enhanced `DeliveryNoteItemBottomSheet` with real-time batch validation, rack validation, and custom fields (Invoice Serial No).
    *   Added "ShureTechMono" font for clear barcode text rendering.

*   **General:**
    *   Updated dependencies in `pubspec.yaml` (e.g., `share_plus`, `barcode_widget`, `qr_flutter`).
    *   Various bug fixes and performance improvements.
