# Performance Optimisations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 8 confirmed performance and UI-smoothness issues across the Flutter supply-chain app without changing any behaviour.

**Architecture:** All fixes are surgical in-place edits — no new files, no new abstractions. Each task is independent and safe to commit individually.

**Tech Stack:** Flutter/Dart, GetX (state + DI), Dio (HTTP), NestedScrollView + SliverList layouts.

---

## Task 1: Fix uncancelled `ever()` workers in StockEntryFormController

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

**Problem:** Three `ever()` workers created in `_initDependencies()` (lines 288–290) have no stored reference, so they cannot be cancelled. Also, `TextEditingController` disposal is deferred via `addPostFrameCallback` (line 305) — unnecessary and fragile.

- [ ] **Step 1: Add three Worker fields below the existing `_scanWorker` field (line 115)**

  Current (line 115):
  ```dart
  Worker? _scanWorker;
  ```

  Replace with:
  ```dart
  Worker? _scanWorker;
  Worker? _fromWarehouseWorker;
  Worker? _toWarehouseWorker;
  Worker? _stockEntryTypeWorker;
  ```

- [ ] **Step 2: Store the three workers in `_initDependencies()`**

  Current (lines 288–290):
  ```dart
    ever(fromWarehouse,    (_) => _markDirty());
    ever(toWarehouse,      (_) => _markDirty());
    ever(stockEntryType,   (_) => _markDirty());
  ```

  Replace with:
  ```dart
    _fromWarehouseWorker  = ever(fromWarehouse,  (_) => _markDirty());
    _toWarehouseWorker    = ever(toWarehouse,     (_) => _markDirty());
    _stockEntryTypeWorker = ever(stockEntryType,  (_) => _markDirty());
  ```

- [ ] **Step 3: Dispose the three workers and fix TEC disposal in `onClose()`**

  Current (lines 299–310):
  ```dart
    @override
    void onClose() {
      disposeScanWiring();
      _autoSubmitTimer?.cancel();
      _saveResultTimer?.cancel();
      final bcc = barcodeController;
      final crc = customReferenceNoController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        bcc.dispose();
        crc.dispose();
      });
      super.onClose();
    }
  ```

  Replace with:
  ```dart
    @override
    void onClose() {
      disposeScanWiring();
      _autoSubmitTimer?.cancel();
      _saveResultTimer?.cancel();
      _fromWarehouseWorker?.dispose();
      _toWarehouseWorker?.dispose();
      _stockEntryTypeWorker?.dispose();
      barcodeController.dispose();
      customReferenceNoController.dispose();
      super.onClose();
    }
  ```

- [ ] **Step 4: Verify no analysis errors**

  Run: `flutter analyze lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`
  Expected: no issues

- [ ] **Step 5: Commit**

  ```bash
  git add lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
  git commit -m "fix(se-form): store and cancel ever() workers; dispose TECs synchronously"
  ```

---

## Task 2: Replace fake `Future.delayed` debounce with GetX `debounce()` in 6 list controllers

**Files:**
- Modify: `lib/app/modules/delivery_note/delivery_note_controller.dart`
- Modify: `lib/app/modules/stock_entry/stock_entry_controller.dart`
- Modify: `lib/app/modules/batch/batch_controller.dart`
- Modify: `lib/app/modules/pos_upload/pos_upload_controller.dart`
- Modify: `lib/app/modules/material_request/material_request_controller.dart`
- Modify: `lib/app/modules/purchase_order/purchase_order_controller.dart`

**Problem:** All six controllers use `Future.delayed(500ms)` + an equality guard instead of a proper cancellable debounce. While logically correct, it creates N pending timer objects for N keystrokes. GetX's built-in `debounce()` worker cancels and resets the timer on every change, which is both cleaner and more efficient.

**Pattern to apply to every controller below:**
1. In `onInit()`, add one `debounce()` call after any existing setup.
2. Replace the `onSearchChanged` body with a single assignment.

GetX `debounce()` called from within `onInit()` is automatically managed by the controller's lifecycle — no field storage or manual dispose needed.

- [ ] **Step 1: Fix `DeliveryNoteController`**

  In `onInit()` (around line 68), add the debounce call after `fetchDocTypePermissions()`:

  Current `onInit()`:
  ```dart
    @override
    void onInit() {
      super.onInit();
      fetchDeliveryNotes();
      fetchUsers();
      fetchWarehouses();
      fetchCustomers();
      fetchDocTypePermissions();
    }
  ```

  Replace with:
  ```dart
    @override
    void onInit() {
      super.onInit();
      fetchDeliveryNotes();
      fetchUsers();
      fetchWarehouses();
      fetchCustomers();
      fetchDocTypePermissions();
      debounce(searchQuery, (_) => fetchDeliveryNotes(clear: true),
          time: const Duration(milliseconds: 500));
    }
  ```

  Replace `onSearchChanged` (lines 128–135):
  ```dart
    void onSearchChanged(String val) {
      searchQuery.value = val;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == val) {
          fetchDeliveryNotes(clear: true);
        }
      });
    }
  ```
  with:
  ```dart
    void onSearchChanged(String val) => searchQuery.value = val;
  ```

- [ ] **Step 2: Fix `StockEntryController`**

  Add debounce in `onInit()` after `fetchDocTypePermissions()`:
  ```dart
      debounce(searchQuery, (_) => fetchStockEntries(clear: true),
          time: const Duration(milliseconds: 500));
  ```

  Replace `onSearchChanged` (lines 128–135):
  ```dart
    void onSearchChanged(String val) {
      searchQuery.value = val;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == val) {
          fetchStockEntries(clear: true);
        }
      });
    }
  ```
  with:
  ```dart
    void onSearchChanged(String val) => searchQuery.value = val;
  ```

- [ ] **Step 3: Fix `BatchController`**

  Find the `onInit()` method in `batch_controller.dart`. Add at the end:
  ```dart
      debounce(searchQuery, (_) => fetchBatches(clear: true),
          time: const Duration(milliseconds: 500));
  ```

  Replace `onSearchChanged` (lines 206–211):
  ```dart
    void onSearchChanged(String val) {
      searchQuery.value = val;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == val) fetchBatches(clear: true);
      });
    }
  ```
  with:
  ```dart
    void onSearchChanged(String val) => searchQuery.value = val;
  ```

- [ ] **Step 4: Fix `PosUploadController`**

  Add debounce in `onInit()`:
  ```dart
      debounce(searchQuery, (_) => fetchPosUploads(clear: true),
          time: const Duration(milliseconds: 500));
  ```

  Replace `onSearchChanged` (lines 64–69):
  ```dart
    void onSearchChanged(String val) {
      searchQuery.value = val;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == val) fetchPosUploads(clear: true);
      });
    }
  ```
  with:
  ```dart
    void onSearchChanged(String val) => searchQuery.value = val;
  ```

- [ ] **Step 5: Fix `MaterialRequestController`**

  Add debounce in `onInit()`:
  ```dart
      debounce(searchQuery, (_) => fetchMaterialRequests(clear: true),
          time: const Duration(milliseconds: 500));
  ```

  Replace `onSearchChanged` (lines 63–68):
  ```dart
    void onSearchChanged(String val) {
      searchQuery.value = val;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == val) {
          fetchMaterialRequests(clear: true);
        }
      });
    }
  ```
  with:
  ```dart
    void onSearchChanged(String val) => searchQuery.value = val;
  ```

- [ ] **Step 6: Fix `PurchaseOrderController`**

  Add debounce in `onInit()`:
  ```dart
      debounce(searchQuery, (_) => fetchPurchaseOrders(clear: true),
          time: const Duration(milliseconds: 500));
  ```

  Replace `onSearchChanged` (lines 168–173):
  ```dart
    void onSearchChanged(String val) {
      searchQuery.value = val;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == val) {
          fetchPurchaseOrders(clear: true);
        }
      });
    }
  ```
  with:
  ```dart
    void onSearchChanged(String val) => searchQuery.value = val;
  ```

- [ ] **Step 7: Run analysis**

  Run: `flutter analyze lib/app/modules/delivery_note/delivery_note_controller.dart lib/app/modules/stock_entry/stock_entry_controller.dart lib/app/modules/batch/batch_controller.dart lib/app/modules/pos_upload/pos_upload_controller.dart lib/app/modules/material_request/material_request_controller.dart lib/app/modules/purchase_order/purchase_order_controller.dart`
  Expected: no issues

- [ ] **Step 8: Commit**

  ```bash
  git add lib/app/modules/delivery_note/delivery_note_controller.dart lib/app/modules/stock_entry/stock_entry_controller.dart lib/app/modules/batch/batch_controller.dart lib/app/modules/pos_upload/pos_upload_controller.dart lib/app/modules/material_request/material_request_controller.dart lib/app/modules/purchase_order/purchase_order_controller.dart
  git commit -m "perf: replace Future.delayed debounce with GetX debounce() in 6 list controllers"
  ```

---

## Task 3: Split root `Obx()` in `DeliveryNoteFormScreen` to isolate loading rebuilds

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_form_screen.dart`

**Problem:** The entire `DeliveryNoteFormScreen.build()` is wrapped in a single `Obx()` that reads 5 reactive values (`note`, `isDirty`, `isSaving`, `saveResult`, `isLoading`). Whenever `isLoading` flips (document fetch), Flutter rebuilds the `SliverPersistentHeader` (DocTypeFormHeader), `DefaultTabController`, `Scaffold`, and the entire form body. By moving `isLoading` into a nested `Obx()` on the `NestedScrollView.body`, document-load rebuilds no longer touch the header or scaffold structure.

Note: `DocTypeFormHeader` is a `SliverPersistentHeader` — sliver widgets cannot be wrapped in `Obx()`. Only the non-sliver body can receive its own `Obx()`.

- [ ] **Step 1: Replace `build()` — remove `isLoading` from outer scope and wrap the body**

  Current `build()` (lines 18–73):
  ```dart
    @override
    Widget build(BuildContext context) {
      return Obx(() {
        final note       = controller.deliveryNote.value;
        final isDirty    = controller.isDirty.value;
        final isSaving   = controller.isSaving.value;
        final saveResult = controller.saveResult.value;
        final isLoading  = controller.isLoading.value;

        return PopScope(
          canPop: !isDirty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            await controller.confirmDiscard();
          },
          child: DefaultTabController(
            length: 2,
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: NestedScrollView(
                headerSliverBuilder: (ctx, _) => [
                  DocTypeFormHeader(
                    title:       note?.name ?? 'Loading...',
                    docType:     'Delivery Note',
                    statusLabel: note?.status,
                    canSave:    isDirty,
                    docStatus:  note?.docstatus ?? 0,
                    isSaving:   isSaving,
                    saveResult: saveResult,
                    onSave:     (note?.docstatus == 0) ? controller.saveDocument : null,
                    onReload: (controller.mode != 'new' && !isDirty)
                        ? controller.reloadDocument
                        : null,
                    bottom: const TabBar(
                      tabs: [
                        Tab(text: 'Details'),
                        Tab(text: 'Items'),
                      ],
                    ),
                  ),
                ],
                body: (isLoading && note == null)
                    ? const Center(child: CircularProgressIndicator())
                    : note == null
                        ? const Center(child: Text('Delivery note not found.'))
                        : TabBarView(
                            children: [
                              _buildDetailsView(context, note),
                              _buildItemsView(context),
                            ],
                          ),
              ),
            ),
          ),
        );
      });
    }
  ```

  Replace with:
  ```dart
    @override
    Widget build(BuildContext context) {
      return Obx(() {
        final note       = controller.deliveryNote.value;
        final isDirty    = controller.isDirty.value;
        final isSaving   = controller.isSaving.value;
        final saveResult = controller.saveResult.value;

        return PopScope(
          canPop: !isDirty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            await controller.confirmDiscard();
          },
          child: DefaultTabController(
            length: 2,
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: NestedScrollView(
                headerSliverBuilder: (ctx, _) => [
                  DocTypeFormHeader(
                    title:       note?.name ?? 'Loading...',
                    docType:     'Delivery Note',
                    statusLabel: note?.status,
                    canSave:    isDirty,
                    docStatus:  note?.docstatus ?? 0,
                    isSaving:   isSaving,
                    saveResult: saveResult,
                    onSave:     (note?.docstatus == 0) ? controller.saveDocument : null,
                    onReload: (controller.mode != 'new' && !isDirty)
                        ? controller.reloadDocument
                        : null,
                    bottom: const TabBar(
                      tabs: [
                        Tab(text: 'Details'),
                        Tab(text: 'Items'),
                      ],
                    ),
                  ),
                ],
                body: Obx(() {
                  final isLoading  = controller.isLoading.value;
                  final currentNote = controller.deliveryNote.value;
                  if (isLoading && currentNote == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (currentNote == null) {
                    return const Center(child: Text('Delivery note not found.'));
                  }
                  return TabBarView(
                    children: [
                      _buildDetailsView(context, currentNote),
                      _buildItemsView(context),
                    ],
                  );
                }),
              ),
            ),
          ),
        );
      });
    }
  ```

- [ ] **Step 2: Run analysis**

  Run: `flutter analyze lib/app/modules/delivery_note/form/delivery_note_form_screen.dart`
  Expected: no issues

- [ ] **Step 3: Commit**

  ```bash
  git add lib/app/modules/delivery_note/form/delivery_note_form_screen.dart
  git commit -m "perf(dn-form): isolate isLoading rebuild to body Obx — header stays stable during fetch"
  ```

---

## Task 4: Parallelize `onInit()` API calls in `DeliveryNoteController` and `StockEntryController`

**Files:**
- Modify: `lib/app/modules/delivery_note/delivery_note_controller.dart`
- Modify: `lib/app/modules/stock_entry/stock_entry_controller.dart`

**Problem:** Both controllers fire 5 API calls sequentially in `onInit()`. On a 200 ms round-trip network, that's ~1 s of serial loading before the list renders. Wrapping the metadata calls in `Future.wait()` runs them in parallel; the main list fetch can also start in parallel since it doesn't depend on the others.

- [ ] **Step 1: Parallelize `DeliveryNoteController.onInit()`**

  Current (lines 62–69):
  ```dart
    @override
    void onInit() {
      super.onInit();
      fetchDeliveryNotes();
      fetchUsers();
      fetchWarehouses();
      fetchCustomers();
      fetchDocTypePermissions();
      debounce(searchQuery, (_) => fetchDeliveryNotes(clear: true),
          time: const Duration(milliseconds: 500));
    }
  ```

  Replace with:
  ```dart
    @override
    void onInit() {
      super.onInit();
      Future.wait([
        fetchDeliveryNotes(),
        fetchUsers(),
        fetchWarehouses(),
        fetchCustomers(),
        fetchDocTypePermissions(),
      ]);
      debounce(searchQuery, (_) => fetchDeliveryNotes(clear: true),
          time: const Duration(milliseconds: 500));
    }
  ```

  Note: each of those methods already handles its own `isLoading`/`isFetching` flags and error dialogs internally. They are safe to run concurrently.

- [ ] **Step 2: Parallelize `StockEntryController.onInit()`**

  Current (lines 67–76):
  ```dart
    @override
    void onInit() {
      super.onInit();
      fetchStockEntries();
      fetchStockEntryTypes();
      fetchUsers();
      fetchWarehouses();
      fetchDocTypePermissions();
    }
  ```

  Replace with:
  ```dart
    @override
    void onInit() {
      super.onInit();
      Future.wait([
        fetchStockEntries(),
        fetchStockEntryTypes(),
        fetchUsers(),
        fetchWarehouses(),
        fetchDocTypePermissions(),
      ]);
      debounce(searchQuery, (_) => fetchStockEntries(clear: true),
          time: const Duration(milliseconds: 500));
    }
  ```

  Note: the debounce line was already added in Task 2 Step 2. Only add it here if Task 2 hasn't been applied yet — otherwise skip adding it again.

- [ ] **Step 3: Run analysis**

  Run: `flutter analyze lib/app/modules/delivery_note/delivery_note_controller.dart lib/app/modules/stock_entry/stock_entry_controller.dart`
  Expected: no issues

- [ ] **Step 4: Commit**

  ```bash
  git add lib/app/modules/delivery_note/delivery_note_controller.dart lib/app/modules/stock_entry/stock_entry_controller.dart
  git commit -m "perf: parallelize onInit() API calls in DN and SE list controllers"
  ```

---

## Task 5: Fix `limit: 0` dashboard count queries in `HomeController`

**Files:**
- Modify: `lib/app/modules/home/home_controller.dart`

**Problem:** `fetchDashboardData()` fetches Work Orders, Job Cards, and BOMs with `limit: 0` (unlimited), downloads every matching record, then calls `_getCountFromResponse()` which just reads `(data as List).length`. On a large instance, this can download thousands of records to display three counter badges. The fix is to use `limit: 1` — the `_getCountFromResponse` helper already works correctly with any non-empty response, and Frappe's response includes a `data` list whose length is the relevant count relative to the provided filters and limit.

  Wait — `limit: 1` would only ever return 0 or 1, so the count shown would always be 0 or 1. That's wrong. The real fix is to use Frappe's `frappe.client.get_count` whitelist method, OR to keep `limit: 0` but understand the trade-off. Let's check by reading the surrounding code.

  Looking at `_getCountFromResponse` at line 553–558: it returns `(response.data['data'] as List).length`. With `limit: 0` (unlimited fetch) this gives the true count. With `limit: 1` it would give at most 1.

  **Correct fix:** Replace `limit: 0` with a dedicated count API call using `_apiProvider.getDocumentList` with `fields: ['name']` and `limit: 1000` as a reasonable cap, OR use `frappe.client.get_count`.

  Since `ApiProvider` likely has a `getDocumentList` method, the cleanest fix without adding a new provider method is to keep `limit: 0` for now but document the trade-off. Alternatively, if `ApiProvider` exposes a way to call whitelisted methods, use `frappe.client.get_count`.

  Check `ApiProvider` for a count method before applying the fix. If no count method exists, this task becomes "add `getDocumentCount` to `ApiProvider` and use it in `HomeController`".

- [ ] **Step 1: Check `ApiProvider` for an existing count method**

  Run: `grep -r "get_count\|getCount\|getDocumentCount" lib/app/data/providers/api_provider.dart`
  
  If a count method exists, use it. If not, proceed to Step 2.

- [ ] **Step 2: Add `getDocumentCount` to `ApiProvider`**

  File: `lib/app/data/providers/api_provider.dart`

  Find the end of the class and add:
  ```dart
    Future<Response> getDocumentCount(
      String doctype, {
      Map<String, dynamic>? filters,
    }) {
      return _dio.get(
        '/api/method/frappe.client.get_count',
        queryParameters: {
          'doctype': doctype,
          if (filters != null) 'filters': jsonEncode(filters),
        },
      );
    }
  ```

  Add `import 'dart:convert';` at the top of the file if not already present.

- [ ] **Step 3: Replace `limit: 0` fetches in `HomeController.fetchDashboardData()`**

  Current (lines 197–205):
  ```dart
      final results = await Future.wait([
        _woProvider.getWorkOrders(limit: 0, filters: woFilters),
        _jcProvider.getJobCards(limit: 0, filters: jcFilters),
        _bomProvider.getBOMs(limit: 0, filters: bomFilters),
      ]);

      activeWorkOrdersCount.value = _getCountFromResponse(results[0]);
      activeJobCardsCount.value   = _getCountFromResponse(results[1]);
      activeBomCount.value        = _getCountFromResponse(results[2]);
  ```

  Replace with:
  ```dart
      final results = await Future.wait([
        _apiProvider.getDocumentCount('Work Order', filters: woFilters),
        _apiProvider.getDocumentCount('Job Card',   filters: jcFilters),
        _apiProvider.getDocumentCount('BOM',        filters: bomFilters),
      ]);

      activeWorkOrdersCount.value = _extractCount(results[0]);
      activeJobCardsCount.value   = _extractCount(results[1]);
      activeBomCount.value        = _extractCount(results[2]);
  ```

  Add `_extractCount` helper below the existing `_getCountFromResponse` (or replace it):
  ```dart
    int _extractCount(dynamic response) {
      if (response is Response &&
          response.statusCode == 200 &&
          response.data?['message'] is int) {
        return response.data['message'] as int;
      }
      return 0;
    }
  ```

  Also add `final ApiProvider _apiProvider = Get.find<ApiProvider>();` to the `HomeController` field list if not already there. Search the file first — if `ApiProvider` is already injected, skip.

- [ ] **Step 4: Run analysis**

  Run: `flutter analyze lib/app/modules/home/home_controller.dart lib/app/data/providers/api_provider.dart`
  Expected: no issues

- [ ] **Step 5: Commit**

  ```bash
  git add lib/app/data/providers/api_provider.dart lib/app/modules/home/home_controller.dart
  git commit -m "perf(home): use frappe.client.get_count for dashboard badges instead of limit:0 full-fetch"
  ```

---

## Task 6: Add `cacheWidth`/`cacheHeight` to `Image.network()` calls in grid/list contexts

**Files:**
- Modify: `lib/app/modules/item/widgets/item_image.dart`
- Modify: `lib/app/modules/home/widgets/scan_bottom_sheets.dart`

**Problem:** `Image.network()` decodes images at full device resolution (e.g., 1440 × 3120 px). Without `cacheWidth`/`cacheHeight`, Flutter's image cache stores the full-resolution decoded bitmap even when the displayed size is 60 × 60 px. Adding constraints causes Flutter to resize the image during decode, dramatically reducing memory per image.

- [ ] **Step 1: Fix `ItemImage` — add `cacheWidth`/`cacheHeight` when `size` is known**

  Current (lines 32–62 in `item_image.dart`):
  ```dart
          child: Image.network(
            imageUrl!,
            width: size,
            height: size,
            fit: fit,
            loadingBuilder: ...
            errorBuilder: ...
          ),
  ```

  Replace with:
  ```dart
          child: Image.network(
            imageUrl!,
            width: size,
            height: size,
            fit: fit,
            cacheWidth:  size != null ? size!.toInt() : null,
            cacheHeight: size != null ? size!.toInt() : null,
            loadingBuilder: ...
            errorBuilder: ...
          ),
  ```

  The `cacheWidth`/`cacheHeight` parameters accept `int?`. When `size` is null (grid mode filling parent), pass null — Flutter will use the natural decode size, which is acceptable since the parent constrains layout anyway.

- [ ] **Step 2: Fix `scan_bottom_sheets.dart` list-row image (line ~42)**

  Find the `Image.network` call with `width: 60, height: 60`:
  ```dart
                    child: Image.network(
                      '$_baseUrl${item.image}',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (c, o, s) => Container(
  ```

  Replace with:
  ```dart
                    child: Image.network(
                      '$_baseUrl${item.image}',
                      width: 60,
                      height: 60,
                      cacheWidth: 120,
                      cacheHeight: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (c, o, s) => Container(
  ```

  Use 2× pixel ratio (120) to look sharp on high-DPI screens.

- [ ] **Step 3: Fix `scan_bottom_sheets.dart` grid card image (line ~513)**

  Find the grid card `Image.network` call with no width/height:
  ```dart
                                          ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                                      )
  ```

  Replace with:
  ```dart
                                          ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        cacheWidth: 600,
                                        cacheHeight: 500,
                                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                                      )
  ```

  600 × 500 at 2× is ~300 × 250 logical pixels — a reasonable upper bound for a grid card image on a phone screen.

- [ ] **Step 4: Run analysis**

  Run: `flutter analyze lib/app/modules/item/widgets/item_image.dart lib/app/modules/home/widgets/scan_bottom_sheets.dart`
  Expected: no issues

- [ ] **Step 5: Commit**

  ```bash
  git add lib/app/modules/item/widgets/item_image.dart lib/app/modules/home/widgets/scan_bottom_sheets.dart
  git commit -m "perf: add cacheWidth/cacheHeight to Image.network() calls to reduce texture memory"
  ```

---

## Task 7: Convert eager `ListView` to lazy `ListView.builder` in `AppNavDrawer`

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart`

**Problem:** The drawer uses `ListView(children: [...])` for both the user menu and the main module menu. Flutter instantiates all child widgets upfront regardless of scroll position. `ListView.builder` constructs only visible items on demand.

- [ ] **Step 1: Locate both `ListView` calls in `app_nav_drawer.dart`**

  Run: `grep -n "return ListView(" lib/app/modules/global_widgets/app_nav_drawer.dart`

  There should be two: one at the user menu branch (~line 147) and one at the main module menu branch (~line 199).

- [ ] **Step 2: Convert user-menu `ListView` to `ListView.builder`**

  Read lines ~147–195 to see all the children, then build a children list and convert.

  Current structure:
  ```dart
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    children: [
                      _DrawerItem(...),   // item 0
                      _DrawerItem(...),   // item 1
                      _DrawerItem(...),   // item 2
                      const Padding(...), // item 3
                      Builder(builder: (ctx) { return ListTile(...); }), // item 4
                    ],
                  );
  ```

  Replace with:
  ```dart
                  final _userMenuItems = <Widget>[
                    _DrawerItem(
                      icon: Icons.person_outline_rounded,
                      title: 'My Profile',
                      route: AppRoutes.PROFILE,
                      currentRoute: currentRoute,
                    ),
                    _DrawerItem(
                      icon: Icons.settings,
                      title: 'Session Defaults',
                      route: '',
                      currentRoute: currentRoute,
                      onTap: (ctx) {
                        Navigator.of(ctx).pop();
                        homeController.openSessionDefaults();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.info_outline,
                      title: 'About',
                      route: AppRoutes.ABOUT,
                      currentRoute: currentRoute,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Divider(height: 1),
                    ),
                    Builder(builder: (ctx) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        leading: Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 22),
                        title: Text('Logout',
                            style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600)),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(ctx).pop();
                          Get.find<AuthenticationController>().logoutUser();
                        },
                      );
                    }),
                  ];
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    itemCount: _userMenuItems.length,
                    itemBuilder: (_, i) => _userMenuItems[i],
                  );
  ```

  Note: read the actual file content around lines 147–195 before applying — use exact code from the file, not from this plan. This plan shows the intended shape; the file is authoritative.

- [ ] **Step 3: Convert main-module-menu `ListView` to `ListView.builder`**

  Read lines ~199 onwards to get all the drawer items. Collect them into a list variable `_moduleMenuItems` and replace `ListView(children: [...])` with:

  ```dart
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    itemCount: _moduleMenuItems.length,
                    itemBuilder: (_, i) => _moduleMenuItems[i],
                  );
  ```

  The main menu likely has DocTypeGuard-wrapped DrawerItems — include them as-is in the list; `DocTypeGuard` handles its own visibility.

- [ ] **Step 4: Run analysis**

  Run: `flutter analyze lib/app/modules/global_widgets/app_nav_drawer.dart`
  Expected: no issues

- [ ] **Step 5: Commit**

  ```bash
  git add lib/app/modules/global_widgets/app_nav_drawer.dart
  git commit -m "perf(drawer): convert ListView to ListView.builder for lazy item construction"
  ```

---

## Task 8: Add `ValueKey` to sliver list item builders in DN and Batch screens

**Files:**
- Modify: `lib/app/modules/delivery_note/delivery_note_screen.dart`
- Modify: `lib/app/modules/batch/batch_screen.dart`

**Problem:** `SliverChildBuilderDelegate` item builders return widgets with no key. When the list is sorted or filtered (items reorder), Flutter cannot match old card state to new positions, causing it to tear down and recreate widget subtrees unnecessarily. A `ValueKey` keyed on the document name fixes this.

- [ ] **Step 1: Add `ValueKey` to `DeliveryNoteScreen` list builder**

  Find the `SliverChildBuilderDelegate` item builder in `delivery_note_screen.dart` (around line 370). The item card is:
  ```dart
                    final note = controller.deliveryNotes[index];

                    return Obx(() {
                      ...
                      return GenericDocumentCard(...);
                    });
  ```

  Wrap the `Obx` with a `KeyedSubtree` or pass the key directly. Since `Obx` is a `StatelessWidget`, add a `key` parameter:

  Replace:
  ```dart
                    return Obx(() {
  ```
  with:
  ```dart
                    return Obx(key: ValueKey(note.name), () {
  ```

  Note: `Obx` in GetX accepts a `Key? key` in its constructor. Verify by checking: `grep -n "class Obx" $(flutter pub cache list 2>/dev/null | grep get:)` or simply try it — if `Obx` doesn't accept `key`, wrap it in `KeyedSubtree(key: ValueKey(note.name), child: Obx(...))` instead.

- [ ] **Step 2: Add `ValueKey` to `BatchScreen` list builder**

  Find the `SliverChildBuilderDelegate` item builder in `batch_screen.dart`. Apply the same pattern — add `key: ValueKey(batch.name)` (or the batch's unique identifier field) to the outermost widget returned by the builder.

- [ ] **Step 3: Run analysis**

  Run: `flutter analyze lib/app/modules/delivery_note/delivery_note_screen.dart lib/app/modules/batch/batch_screen.dart`
  Expected: no issues

- [ ] **Step 4: Commit**

  ```bash
  git add lib/app/modules/delivery_note/delivery_note_screen.dart lib/app/modules/batch/batch_screen.dart
  git commit -m "perf: add ValueKey to sliver list item builders for correct widget reconciliation"
  ```

---

## Self-Review Checklist

- [x] Task 1 covers: worker leak fix + synchronous TEC disposal in SE form controller
- [x] Task 2 covers: debounce fix in all 6 identified list controllers
- [x] Task 3 covers: DN form Obx scope split (isLoading isolated to body)
- [x] Task 4 covers: parallel onInit() for DN + SE controllers (NOTE: Task 2 already adds debounce — Task 4 Step 2 says to skip the debounce line if already applied)
- [x] Task 5 covers: dashboard limit:0 — includes adding `getDocumentCount` to ApiProvider
- [x] Task 6 covers: cacheWidth/cacheHeight on all three Image.network() sites
- [x] Task 7 covers: ListView → ListView.builder in drawer
- [x] Task 8 covers: ValueKey in sliver list builders

**Dependency note:** Task 2 and Task 4 both touch `delivery_note_controller.dart` and `stock_entry_controller.dart`. Apply Task 2 first; Task 4 should not re-add the debounce line that Task 2 already added.
