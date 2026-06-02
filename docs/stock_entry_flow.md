# Stock Entry — Flow of Control

> Generated: 2026-03-17 | Branch: `release/play-store-beta-1`

This document traces every data flow, user action, navigation event, reactive
dependency, and API call that exists across the Stock Entry module.

---

## Table of Contents

1. [Module Structure](#module-structure)
2. [Dependency Injection (Bindings)](#dependency-injection)
3. [List Screen — `StockEntryScreen`](#list-screen)
4. [List Controller — `StockEntryController`](#list-controller)
5. [Creation Flow (bottom-sheets)](#creation-flow)
6. [Form Binding](#form-binding)
7. [Form Screen — `StockEntryFormScreen`](#form-screen)
8. [Form Controller — `StockEntryFormController`](#form-controller)
   - [Initialisation](#initialisation)
   - [Scan Pipeline](#scan-pipeline)
   - [Item Sheet Flow](#item-sheet-flow)
   - [Validation Chain](#validation-chain)
   - [Batch Validation & Balance](#batch-validation--balance)
   - [Rack Validation & Balance](#rack-validation--balance)
   - [Warehouse Resolution Cascade](#warehouse-resolution-cascade)
   - [Save Flow](#save-flow)
9. [Widgets](#widgets)
   - [`StockEntryItemCard`](#stockentryitemcard)
   - [`StockEntryItemFormSheet`](#stockentryitemformsheet)
   - [`StockEntryFilterBottomSheet`](#stockentryfiltersbottomsheet)
   - [`MrItemFilterBar`](#mritemfilterbar)
10. [Reactive Dependency Graph](#reactive-dependency-graph)
11. [API Surface](#api-surface)
12. [Entry Source Decision Tree](#entry-source-decision-tree)
13. [Scan Sequence Matrix](#scan-sequence-matrix)

---

## Module Structure

```
lib/app/modules/stock_entry/
├── stock_entry_binding.dart          # List-screen DI
├── stock_entry_controller.dart       # List CRUD + filter + creation dialogs
├── stock_entry_screen.dart           # List UI (paginated cards + FAB)
├── widgets/
│   └── stock_entry_filter_bottom_sheet.dart
└── form/
    ├── stock_entry_form_binding.dart # Form-screen DI
    ├── stock_entry_form_controller.dart  # ALL form business logic
    ├── stock_entry_form_screen.dart  # Two-tab form UI
    └── widgets/
        ├── stock_entry_item_card.dart
        ├── stock_entry_item_form_sheet.dart  # Bottom-sheet for add/edit item
        └── mr_item_filter_bar.dart
```

---

## Dependency Injection

### `StockEntryBinding` (list route)

| Dependency | Scope |
|---|---|
| `StockEntryProvider` | `lazyPut` |
| `PosUploadProvider` | `lazyPut` |
| `MaterialRequestProvider` | `lazyPut` |
| `UserProvider` | `lazyPut` |
| `WarehouseProvider` | `lazyPut` |
| `StockEntryController` | `lazyPut` |

> `ApiProvider` is resolved from the global scope (registered at app start).

### `StockEntryFormBinding` (form route)

| Dependency | Scope |
|---|---|
| `StockEntryProvider` | `lazyPut` |
| `PosUploadProvider` | `lazyPut` |
| `StorageService` | `lazyPut` |
| `StockEntryFormController` | `lazyPut` |

> `ApiProvider`, `ScanService`, `DataWedgeService` are resolved from the global scope.

---

## List Screen

**File:** `stock_entry_screen.dart`

`StockEntryScreen` is a `StatefulWidget` that owns a `ScrollController` for
infinite scroll pagination.

### Build Hierarchy

```
Scaffold
└── RefreshIndicator  (onRefresh → controller.fetchStockEntries(clear:true))
    └── CustomScrollView
        ├── DocTypeListHeader         (search, filter chips, clear-all)
        ├── SliverToBoxAdapter        (result count pill)
        └── Obx → SliverList
            └── GenericDocumentCard  (per StockEntry)
                └── _buildDetailedContent  (expanded section)
FloatingActionButton                 (RoleGuard-wrapped → openCreateDialog)
```

### Key Actions

| User Action | Method Called | Effect |
|---|---|---|
| Scroll to 90 % of list | `_onScroll` → `fetchStockEntries(isLoadMore:true)` | Appends next 20 entries |
| Pull-to-refresh | `fetchStockEntries(clear:true)` | Resets page, reloads |
| Type in search | `onSearchChanged` (500 ms debounce) | Triggers filtered fetch |
| Tap filter icon | `_showFilterSheet` | Opens `StockEntryFilterBottomSheet` |
| Tap dismiss chip | `removeFilter(key)` | Removes one filter, reloads |
| Tap entry card | `toggleExpand(name)` | Expands card, fetches & caches details |
| Tap Edit/View | `Get.toNamed(STOCK_ENTRY_FORM, args)` | Navigates to form screen |
| Tap FAB | `openCreateDialog` | Opens creation selector sheet |

---

## List Controller

**File:** `stock_entry_controller.dart`

### Observable State

| Field | Type | Purpose |
|---|---|---|
| `isLoading` | `RxBool` | Full-page loading indicator |
| `isFetchingMore` | `RxBool` | Append-pagination spinner |
| `hasMore` | `RxBool` | Whether more pages exist |
| `stockEntries` | `RxList<StockEntry>` | Displayed list |
| `expandedEntryName` | `RxString` | Currently expanded card |
| `isLoadingDetails` | `RxBool` | Detail-fetch spinner |
| `activeFilters` | `RxMap` | Frappe filter map |
| `searchQuery` | `RxString` | Live search text |
| `sortField` / `sortOrder` | `RxString` | Current sort |
| `posUploadsForSelection` | `RxList<PosUpload>` | POS selection sheet list |
| `materialRequestsForSelection` | `RxList<MaterialRequest>` | MR selection sheet list |
| `stockEntryTypes` | `RxList<String>` | Populated from API |
| `users` / `warehouses` | `RxList` | Filter pickers |
| `writeRoles` | `RxList<String>` | Roles allowed to create/edit |

### `onInit` sequence

```
onInit
├── fetchStockEntries()
├── fetchStockEntryTypes()
├── fetchUsers()
├── fetchWarehouses()
└── fetchDocTypePermissions()   → populates writeRoles
```

### `onReady` sequence

```
onReady
└── if Get.arguments['openCreate'] == true → openCreateDialog()
```

---

## Creation Flow

`openCreateDialog()` presents three choices:

```
┌─────────────────────────────────────────┐
│  Create Stock Entry                      │
├─────────────────────────────────────────┤
│  From POS Upload      → _showPosSelectionBottomSheet()
│  From Material Request→ _showMaterialRequestSelectionBottomSheet()
│  Material Transfer    → Get.toNamed(STOCK_ENTRY_FORM, {
│                           mode: 'new',
│                           stockEntryType: 'Material Transfer'
│                         })
└─────────────────────────────────────────┘
```

### POS Upload Selection

1. `fetchPendingPosUploads()` — parallel API calls for KX/MX prefix, merged & deduped.
2. User can search by name or customer (`filterPosUploads`).
3. On select → `Get.toNamed(STOCK_ENTRY_FORM, { mode:'new', stockEntryType:'Material Issue', customReferenceNo: pos.name })`.

### Material Request Selection

1. `fetchPendingMaterialRequests()` — docstatus=1, status≠Stopped, type≠Purchase.
2. `_mapMrTypeToSeType(mrType)` converts MR type → SE type:
   - `Material Transfer` → `Material Transfer`
   - `Material Issue` → `Material Issue`
   - `Manufacture` → `Material Transfer for Manufacture`
3. On select → `Get.toNamed(STOCK_ENTRY_FORM, { mode:'new', stockEntryType, customReferenceNo: mr.name, items:[...] })`.

---

## Form Binding

See [Dependency Injection](#dependency-injection) above.

---

## Form Screen

**File:** `form/stock_entry_form_screen.dart`

`StockEntryFormScreen` is a `GetView<StockEntryFormController>`. It is wrapped
in `Obx` so the entire scaffold re-renders whenever `stockEntry` changes.

### Screen Anatomy

```
PopScope (blocks pop if isDirty)
└── DefaultTabController (2 tabs)
    └── Scaffold
        ├── MainAppBar
        │   ├── Title (doc name or 'New ...')
        │   ├── Status chip
        │   ├── Dirty indicator
        │   ├── Save button  (only when docstatus == 0)
        │   ├── Reload button (only when mode != 'new')
        │   └── TabBar  ['Details', 'Items & Scan']
        └── TabBarView
            ├── Tab 0: _buildDetailsView
            └── Tab 1: _buildItemsView
```

### Tab 0 — Details

- **Entry Type card** — tappable when editable → `_showStockEntryTypePicker`.
- **FROM / TO warehouse row** — visibility/editability driven by entry type:
  - `Material Issue`: FROM editable, TO greyed-out.
  - `Material Receipt`: TO editable, FROM greyed-out.
  - `Material Transfer` / `Material Transfer for Manufacture`: both editable.
- **Posting Date / Time** — tap → `pickPostingDate` / `pickPostingTime`.
- **Reference No** — always `readOnly` (lock icon shown); value set by system.
- **Summary box** — total qty + total amount.

### Tab 1 — Items & Scan

```
Stack
├── Column
│   └── Expanded
│       ├── _buildEmptyState()           if no items and manual source
│       ├── _buildPosUploadItemsView()   if entrySource == posUpload
│       ├── _buildMaterialRequestItemsView() if entrySource == materialRequest
│       └── _buildStandardItemsView()   otherwise
└── Positioned (bottom)
    └── _buildBottomScanField()          BarcodeInputWidget (only if docstatus == 0)
```

#### POS Upload Items View

Grouped by `customInvoiceSerialNumber`. Each group is an expandable
`ItemGroupCard` showing invoice serial, item name, rate, total qty, and
scanned-so-far qty.

#### Material Request Items View

Driven by `controller.mrFilteredItems` (a computed list of `MrItemRow`). Every
MR line is always shown, even if not yet scanned ("ghost" `StockEntryItem`
with `qty=0`). Filter bar (`MrItemFilterBar`) switches between All / Pending /
Completed.

#### Standard Items View

Plain `ListView` of `StockEntryItemCard`.

---

## Form Controller

**File:** `form/stock_entry_form_controller.dart`

### Initialisation

```
onInit
├── _initDependencies()
│   ├── fetchWarehouses()
│   ├── fetchStockEntryTypes()
│   ├── ever(DataWedgeService.scannedCode) → scanBarcode()
│   ├── ever(selectedFromWarehouse)        → _markDirty()
│   ├── ever(selectedToWarehouse)          → _markDirty()
│   ├── ever(selectedStockEntryType)       → _markDirty()
│   ├── ever(bsItemSourceWarehouse)        → _updateAvailableStock()
│   ├── ever(bsItemSourceWarehouse)        → _updateBatchBalance()  ← batch-warehouse re-scope
│   ├── customReferenceNoController.addListener → _markDirty() + _fetchPosUploadDetails()
│   ├── bsQtyController.addListener        → validateSheet()
│   ├── bsBatchController.addListener      → validateSheet()
│   ├── bsSourceRackController.addListener → validateSheet()
│   ├── bsTargetRackController.addListener → validateSheet()
│   ├── ever(selectedSerial)               → validateSheet()
│   ├── ever(bsItemSourceWarehouse)        → validateSheet()
│   ├── ever(bsItemTargetWarehouse)        → validateSheet()
│   └── _setupAutoSubmit()
│       └── ever(isSheetValid) → if valid & open & docstatus==0 → Timer(delay, addItem)
└── if mode == 'new' → _initNewStockEntry()
    else → fetchStockEntry()
```

#### `_initNewStockEntry()`

```
_initNewStockEntry()
├── Set selectedStockEntryType, customReferenceNo, _initialReferenceNo
├── _determineSource(type, ref)
│   ├── items in args              → materialRequest
│   ├── Material Issue + KX/MX ref → posUpload
│   ├── non-empty ref              → materialRequest
│   └── else                       → manual
├── if materialRequest → _initMaterialRequestFlow(ref)
│   └── if items in args → parse directly
│       else → GET /api/resource/Material Request/{ref}
├── if posUpload → _initPosUploadFlow(ref)
│   └── _fetchPosUploadDetails(ref)
└── Construct blank StockEntry with today's date/time
```

#### `fetchStockEntry()` (edit / view mode)

```
fetchStockEntry()
├── GET /api/resource/Stock Entry/{name}
├── Populate stockEntry, selectedStockEntryType, selectedFromWarehouse,
│   selectedToWarehouse, customReferenceNoController
└── Determine entrySource:
    ├── Material Issue + KX/MX ref → posUpload  → _fetchPosUploadDetails()
    ├── Material Issue + MAT-STE linked items  → materialRequest → _initMaterialRequestFlow()
    └── else → manual
```

---

### Scan Pipeline

```
User scans barcode  (physical scanner or BarcodeInputWidget)
        │
        ▼
scanBarcode(barcode)
        │
        ├── if isClosed / isStale / empty / isScanning → abort
        │
        ├── if sheet is open ─────────────────────────────────────────────┐
        │   └── _handleSheetScan(barcode)                                  │
        │       ├── _scanService.processScan(barcode, contextItemCode)     │
        │       ├── if rack   → _handleSheetRackScan(rackId)               │
        │       │   ├── Material Transfer/Manufacture:                     │
        │       │   │   └── source empty → fill source, else fill target   │
        │       │   ├── Material Issue  → fill source rack                 │
        │       │   └── Material Receipt → fill target rack                │
        │       ├── if batch/item → bsBatchController.text = batch         │
        │       │                   validateBatch(batch)                   │
        │       └── else → _tryApplyAsRackFallback(barcode)                │
        │                                                           ◄──────┘
        ├── if warehouse not set → show warning snackbar, abort
        │
        └── _scanService.processScan(barcode)
            ├── if success & itemData not null
            │   ├── _validateScanContext()  (check item in MR if materialRequest source)
            │   ├── set currentItemCode/Name/Uom/Ean
            │   └── _openQtySheet(scannedBatch: result.batchNo)
            └── else → show error snackbar
```

---

### Item Sheet Flow

```
_openQtySheet(scannedBatch?)
├── Guard: abort if sheet already open
├── _resetSheetState()                 ← clears all bsXxx fields
├── if MR source → pre-populate bsValidationMaxQty from mrReferenceItems
├── if scannedBatch → bsBatchController.text = batch; validateBatch(batch)
├── if MR source → selectedSerial = '0'
└── _openSheet()
    └── Get.bottomSheet(DraggableScrollableSheet)
        └── StockEntryItemFormSheet(controller: this)

editItem(StockEntryItem)
├── Guard: abort if sheet already open
├── Populate currentItemCode, Name, NameKey, VariantOf, UOM
├── Populate bsQtyController, bsBatchController,
│   bsSourceRackController, bsTargetRackController, selectedSerial
├── Snapshot _initialQty/Batch/SourceRack/TargetRack for change detection
├── Pre-populate bsIsBatchValid, isSourceRackValid, isTargetRackValid
├── Set isLoadingBatchBalance = true (if batchNo present)
│   isLoadingRackBalance = true
├── bsItemSourceWarehouse = item.sWarehouse
│   bsItemTargetWarehouse = item.tWarehouse
├── validateSheet()
├── _openSheet()
└── unawaited Future.wait([ _updateBatchBalance(), _updateAvailableStock() ])
```

---

### Validation Chain

`validateSheet()` is called on every text-controller change and reactive update.

```
validateSheet()
└── isSheetValid = _isValidQty()
                && _isValidBatch()
                && _isValidContext()
                && _isValidRacks()
                && _hasChanges()
```

| Guard | Condition |
|---|---|
| `_isValidQty` | qty > 0; qty ≤ bsMaxQty (if set); qty ≤ bsBatchBalance (if set) |
| `_isValidBatch` | bsBatchController non-empty **and** bsIsBatchValid == true |
| `_isValidContext` | MR: serial set + item in MR + qty within MR limit; POS: serial set if serials available |
| `_isValidRacks` | Source rack valid if entry type requires source; target rack valid if requires target; source ≠ target |
| `_hasChanges` | At least one of qty/batch/source-rack/target-rack differs from initial snapshot |

---

### Batch Validation & Balance

```
validateBatch(batch)
├── Guard: reject batch where prefix == barcode prefix (e.g. "1234-1234")
├── isValidatingBatch = true
├── GET /api/resource/Batch?item=currentItemCode&name=batch
│   ├── Found:
│   │   ├── bsIsBatchValid = true
│   │   ├── if custom_packaging_qty > 0 → pre-fill qty
│   │   ├── await _updateAvailableStock()
│   │   ├── await _updateBatchBalance()
│   │   └── if enteredQty > bsBatchBalance → set batchError
│   └── Not found: bsIsBatchValid = false; snackbar error
└── validateSheet()

_updateBatchBalance()
├── Resolve effectiveWarehouse = bsItemSourceWarehouse ?? derivedSourceWarehouse ?? selectedFromWarehouse
├── GET getBatchWiseBalance(itemCode, batch, warehouse?)
└── Sum all result rows → bsBatchBalance.value
```

**Re-scope trigger:** `ever(bsItemSourceWarehouse, (_) => _updateBatchBalance())`
ensures the balance is re-fetched with the correct warehouse whenever a rack
scan resolves the warehouse *after* the batch was already validated.

---

### Rack Validation & Balance

```
validateRack(rack, isSource)
├── if empty → clear valid flag + derived warehouse; validateSheet(); return
├── Attempt inline warehouse parse:
│   rack format "WH-A1" → parts[0]=branch, parts[1]=aisle, parts[2]=slot
│   derived warehouse = '{parts[1]}-{parts[2]} - {parts[0]}'
│   bsItemSourceWarehouse (or Target) = derived warehouse  ← triggers reactives
├── isValidatingSourceRack / isValidatingTargetRack = true
├── GET /api/resource/Rack/{rack}
│   ├── Found:
│   │   ├── isSourceRackValid / isTargetRackValid = true
│   │   └── if isSource:
│   │       ├── await _updateAvailableStock()
│   │       ├── await _updateBatchBalance()
│   │       └── if enteredQty > bsBatchBalance → set batchError
│   │           else → clear stale batchError
│   └── Not found: clear valid flag; snackbar
└── validateSheet()

_updateAvailableStock()
├── Resolve effectiveWarehouse (same cascade)
├── GET getStockBalance(itemCode, warehouse, batchNo?)
└── Sum result rows → bsMaxQty; if rack text present → bsRackBalance
```

---

### Warehouse Resolution Cascade

Used identically across `_updateAvailableStock`, `_updateBatchBalance`,
`addItem`, `saveStockEntry`, and the form-screen warehouse label display:

```
effective_warehouse =
  bsItemSourceWarehouse    (set from rack scan → item-level)
  ?? derivedSourceWarehouse  (inline parse from rack string)
  ?? selectedFromWarehouse   (document-level header field)
```

| Source | Set by |
|---|---|
| `bsItemSourceWarehouse` | `validateRack()` after successful Rack API call |
| `derivedSourceWarehouse` | Inline parse in `validateRack()` (pre-API call) |
| `selectedFromWarehouse` | User picks in Details tab warehouse picker |

---

### `addItem()` — Commit to Entry

```
addItem()
├── Cancel pending auto-submit timer
├── Build StockEntryItem from:
│   qty, bsBatchController, bsSourceRackController, bsTargetRackController,
│   sWh (warehouse cascade), tWh (warehouse cascade)
├── If editing existing (by uniqueId) → replace in list
│   else → append
├── _enrichItemWithSourceData()  ← attaches materialRequest/materialRequestItem/serial
├── stockEntry.update() → reactive rebuild
├── barcodeController.clear()
├── triggerHighlight(uniqueId)  ← scroll-to + 2s highlight
├── Close sheet via Navigator (avoids GetX snackbar race)
├── if mode == 'new' → saveStockEntry()
│   else → isDirty = true; saveStockEntry() (background, with success snackbar)
└── (auto-submit path identical, triggered by isSheetValid ever-worker)
```

---

### Save Flow

```
saveStockEntry()
├── Guard: isSaving / isStale
├── Auto-fill selectedFromWarehouse/ToWarehouse from first item if null
├── Validate Material Transfer requires both warehouses
├── Build data map: stock_entry_type, posting_date/time,
│   from_warehouse, to_warehouse, custom_reference_no, modified
├── Build items JSON:
│   ├── Remove 'local_xxx' name prefix
│   ├── Remove zero basic_rate
│   └── Attach material_request / material_request_item if MR source
├── if mode == 'new'
│   └── POST /api/resource/Stock Entry
│       ├── On 200 → capture name; mode = 'edit'; fetchStockEntry()
│       └── On error → snackbar
└── else
    └── PUT /api/resource/Stock Entry/{name}  (with modified for optimistic locking)
        ├── On 200 → update stockEntry from response; fetchStockEntry()
        ├── On 409/version conflict → OptimisticLockingMixin.handleVersionConflict()
        └── On error → snackbar with parsed Frappe exception
```

---

## Widgets

### `StockEntryItemCard`

Stateless card showing:
- Item code + name
- Qty (with UOM)
- Batch No (if present)
- Source/Target rack (if present)
- Warehouse (derived from sWarehouse/tWarehouse)
- Progress bar if `maxQty` is provided (MR view)
- Edit icon (onTap) and delete icon (onDelete) — both null when non-editable

### `StockEntryItemFormSheet`

Bottom-sheet rendered inside `DraggableScrollableSheet`.

Wraps `GlobalItemFormSheet` with custom fields:

| Custom Field | Visibility | Validation |
|---|---|---|
| **Batch No** | Always | Server-side via `validateBatch()`; edit icon resets |
| **Batch Balance chip** | When balance > 0 or loading | Driven by `bsBatchBalance` + `isLoadingBatchBalance` |
| **Invoice Serial No** | Only if `posUploadSerialOptions` non-empty | Dropdown |
| **Source Rack** | If entry type requires source | Server-side via `validateRack(rack, true)` |
| **Rack Balance chip** | When rack balance > 0 or loading | Driven by `bsRackBalance` + `isLoadingRackBalance` |
| **Source Warehouse label** | Always for source types | Derived via cascade; shows resolution source |
| **Target Rack** | If entry type requires target | Server-side via `validateRack(rack, false)` |
| **Target Warehouse label** | Always for target types | Derived via cascade |
| **Rack error** | When `rackError` non-null | Text in red |

**Save button** is enabled only when `isSheetValid.value == true`.

### `StockEntryFilterBottomSheet`

Provides filter controls that write back to `StockEntryController.activeFilters`:

| Filter | Type |
|---|---|
| Status (Draft/Submitted/Cancelled) | `docstatus` int |
| Stock Entry Type | `stock_entry_type` string |
| From Warehouse | `from_warehouse` string |
| Reference No | `custom_reference_no` like |
| Created By | `owner` string |
| Modified By | `modified_by` string |
| Posting Date Range | `posting_date` between |

Apply → `controller.applyFilters(filters)` → triggers `fetchStockEntries(clear:true)`.

### `MrItemFilterBar`

Three chips: **All / Pending / Completed**. Tapping updates
`controller.mrItemFilter.value`, which drives `mrFilteredItems` getter.

Counts are derived from `mrAllItems` (unfiltered) so chips always show
current totals regardless of active filter.

---

## Reactive Dependency Graph

```
DataWedgeService.scannedCode
        │ ever
        ▼
  scanBarcode(barcode)
        │
        ▼
bsItemSourceWarehouse  ──ever──▶  _updateAvailableStock()
                       ──ever──▶  _updateBatchBalance()
                       ──ever──▶  validateSheet()

bsItemTargetWarehouse  ──ever──▶  validateSheet()

selectedFromWarehouse  ──ever──▶  _markDirty()
selectedToWarehouse    ──ever──▶  _markDirty()
selectedStockEntryType ──ever──▶  _markDirty()

bsQtyController        ──listen─▶ validateSheet()
bsBatchController      ──listen─▶ validateSheet()
bsSourceRackController ──listen─▶ validateSheet()
bsTargetRackController ──listen─▶ validateSheet()
selectedSerial         ──ever──▶  validateSheet()

isSheetValid           ──ever──▶  _setupAutoSubmit timer
                                  (fires addItem after delay)
```

---

## API Surface

| Operation | Provider / Method | Frappe Endpoint |
|---|---|---|
| List stock entries | `StockEntryProvider.getStockEntries` | `GET /api/resource/Stock Entry` |
| Get single entry | `StockEntryProvider.getStockEntry` | `GET /api/resource/Stock Entry/{name}` |
| Create entry | `StockEntryProvider.createStockEntry` | `POST /api/resource/Stock Entry` |
| Update entry | `StockEntryProvider.updateStockEntry` | `PUT /api/resource/Stock Entry/{name}` |
| Stock entry types | `StockEntryProvider.getStockEntryTypes` | `GET /api/resource/Stock Entry Type` |
| POS Upload list | `PosUploadProvider.getPosUploads` | `GET /api/resource/POS Upload` |
| POS Upload detail | `PosUploadProvider.getPosUpload` | `GET /api/resource/POS Upload/{id}` |
| Material Request list | `MaterialRequestProvider.getMaterialRequests` | `GET /api/resource/Material Request` |
| Material Request detail | `ApiProvider.getDocument` | `GET /api/resource/Material Request/{name}` |
| Batch validation | `ApiProvider.getDocumentList` | `GET /api/resource/Batch?item=...&name=...` |
| Rack validation | `ApiProvider.getDocument` | `GET /api/resource/Rack/{rack}` |
| Stock balance | `ApiProvider.getStockBalance` | `GET /api/method/...getStockBalance` |
| Batch-wise balance | `ApiProvider.getBatchWiseBalance` | `GET /api/method/...getBatchWiseBalance` |
| DocType permissions | `ApiProvider.getDocument` | `GET /api/resource/DocType/Stock Entry` |
| Warehouse list | `ApiProvider.getDocumentList` | `GET /api/resource/Warehouse?is_group=0` |
| User list | `UserProvider.getUsers` | `GET /api/resource/User` |

---

## Entry Source Decision Tree

```
Get.arguments received by StockEntryFormController
│
├── 'items' key present?  YES ──────────────────── entrySource = materialRequest
│
├── stockEntryType == 'Material Issue'
│   AND customReferenceNo starts with 'KX' or 'MX'?
│               YES ──────────────────────────────── entrySource = posUpload
│
├── customReferenceNo non-empty?
│               YES ──────────────────────────────── entrySource = materialRequest
│
└── else ────────────────────────────────────────── entrySource = manual
```

For **edit/view** mode the source is re-derived from the loaded entry:
```
stockEntryType == 'Material Issue' AND customReferenceNo present?
│
├── starts with KX/MX  → posUpload
├── items have materialRequest links → materialRequest
└── else → manual
```

---

## Scan Sequence Matrix

| Scan Order | Warehouse Scope for Batch Balance | Batch Error Shown? | Sheet Valid? |
|---|---|---|---|
| Item → Batch (no rack) | `selectedFromWarehouse` (header) | Only if qty > header-scoped balance | Only if qty ≤ balance |
| Item → Batch → Rack | Re-scoped to `bsItemSourceWarehouse` on rack confirm | Cleared if qty now OK; set if qty exceeds | Depends on scoped balance |
| Item → Rack → Batch | `bsItemSourceWarehouse` already set | Only if qty > rack-scoped balance | Only if qty ≤ balance |
| Batch first (sheet open) → Rack | Re-scoped via `ever(bsItemSourceWarehouse)` worker | Updated automatically | Updated automatically |
| Edit item (all fields pre-populated) | `item.sWarehouse` (direct) | Cleared if within limits | Controlled by `_hasChanges` |

---

*End of document.*
