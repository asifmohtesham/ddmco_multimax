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
