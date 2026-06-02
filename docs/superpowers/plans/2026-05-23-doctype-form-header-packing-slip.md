# DocTypeFormHeader Parity: Packing Slip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `PackingSlipFormScreen`'s `DocTypeFormHeader` display the doctype label, status pill, and save-result animation — the same three features already present in `DeliveryNoteFormScreen`.

**Architecture:** Add a `saveResult` state machine (observable + auto-reset timer) to `PackingSlipFormController`, mirroring the identical pattern in `DeliveryNoteFormController`. Wire all three missing parameters (`docType`, `statusLabel`, `saveResult`) into the `DocTypeFormHeader` call in `PackingSlipFormScreen`.

**Tech Stack:** Flutter, GetX, Dart `dart:async` Timer

---

## Files

- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`

---

### Task 1: Add `saveResult` state machine to `PackingSlipFormController`

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`

- [ ] **Step 1: Add `save_icon_button.dart` import**

  In `packing_slip_form_controller.dart`, add after the last import line (currently line 26):

  ```dart
  import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
  ```

  This re-exports `SaveResult` — the same import the DN controller uses.

- [ ] **Step 2: Add `saveResult` observable and state machine helper**

  In `packing_slip_form_controller.dart`, after line 45 (`var isDirty = false.obs;`), insert:

  ```dart
  var saveResult     = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }
  ```

- [ ] **Step 3: Cancel the timer in `onClose`**

  In `onClose` (currently lines 115–119), add `_saveResultTimer?.cancel();` so it reads:

  ```dart
  @override
  void onClose() {
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    barcodeController.dispose();
    super.onClose();
  }
  ```

- [ ] **Step 4: Set result in `_createDocument`**

  `_createDocument` currently (lines 1338–1351):

  ```dart
  Future<void> _createDocument(Map<String, dynamic> data) async {
    final response =
    await _apiProvider.createDocument('Packing Slip', data);
    if (response.statusCode == 200 && response.data['data'] != null) {
      final saved = PackingSlip.fromJson(response.data['data']);
      packingSlip.value = saved;
      _updateOriginalState(saved);
      name = saved.name;
      mode = 'edit';
      GlobalSnackbar.success(message: 'Packing Slip Created: ${saved.name}');
    } else {
      GlobalSnackbar.error(message: 'Failed to save Packing Slip');
    }
  }
  ```

  Replace with:

  ```dart
  Future<void> _createDocument(Map<String, dynamic> data) async {
    final response =
    await _apiProvider.createDocument('Packing Slip', data);
    if (response.statusCode == 200 && response.data['data'] != null) {
      final saved = PackingSlip.fromJson(response.data['data']);
      packingSlip.value = saved;
      _updateOriginalState(saved);
      name = saved.name;
      mode = 'edit';
      GlobalSnackbar.success(message: 'Packing Slip Created: ${saved.name}');
      _setSaveResult(SaveResult.success);
    } else {
      GlobalSnackbar.error(message: 'Failed to save Packing Slip');
      _setSaveResult(SaveResult.error);
    }
  }
  ```

- [ ] **Step 5: Set result in `_updateDocument`**

  `_updateDocument` currently (lines 1358–1369):

  ```dart
  Future<void> _updateDocument(Map<String, dynamic> data) async {
    final response =
    await _apiProvider.updateDocument('Packing Slip', name, data);
    if (response.statusCode == 200 && response.data['data'] != null) {
      final saved = PackingSlip.fromJson(response.data['data']);
      packingSlip.value = saved;
      _updateOriginalState(saved);
      GlobalSnackbar.success(message: 'Packing Slip Saved');
    } else {
      GlobalSnackbar.error(message: 'Failed to save Packing Slip');
    }
  }
  ```

  Replace with:

  ```dart
  Future<void> _updateDocument(Map<String, dynamic> data) async {
    final response =
    await _apiProvider.updateDocument('Packing Slip', name, data);
    if (response.statusCode == 200 && response.data['data'] != null) {
      final saved = PackingSlip.fromJson(response.data['data']);
      packingSlip.value = saved;
      _updateOriginalState(saved);
      GlobalSnackbar.success(message: 'Packing Slip Saved');
      _setSaveResult(SaveResult.success);
    } else {
      GlobalSnackbar.error(message: 'Failed to save Packing Slip');
      _setSaveResult(SaveResult.error);
    }
  }
  ```

- [ ] **Step 6: Set result in `_handleSaveError`**

  `_handleSaveError` currently opens at line 1390. Add `_setSaveResult(SaveResult.error);` as the very first statement:

  ```dart
  void _handleSaveError(Object e) {
    _setSaveResult(SaveResult.error);
    if (handleVersionConflict(e)) return;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final raw = data['exception']?.toString() ?? '';
        if (raw.isNotEmpty) {
          GlobalSnackbar.error(message: _parseFrappeException(raw));
          return;
        }
      }
    }
    GlobalSnackbar.error(message: 'Save failed: $e');
  }
  ```

- [ ] **Step 7: Verify with analyzer**

  ```
  flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
  ```

  Expected: no errors or warnings related to the changed file.

- [ ] **Step 8: Commit**

  ```
  git add lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
  git commit -m "feat(packing-slip): add saveResult state machine to PackingSlipFormController"
  ```

---

### Task 2: Wire `docType`, `statusLabel`, `saveResult` into `PackingSlipFormScreen`

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`

- [ ] **Step 1: Add `saveResult` to the `Obx` locals**

  In `build` → inside the `Obx(() {` callback, the locals block currently reads (lines 19–24):

  ```dart
  final slip      = controller.packingSlip.value;
  final isDirty   = controller.isDirty.value;
  final isSaving  = controller.isSaving.value;
  final isLoading = controller.isLoading.value;
  ```

  Add `saveResult` as the fifth local:

  ```dart
  final slip       = controller.packingSlip.value;
  final isDirty    = controller.isDirty.value;
  final isSaving   = controller.isSaving.value;
  final saveResult = controller.saveResult.value;
  final isLoading  = controller.isLoading.value;
  ```

- [ ] **Step 2: Add the three missing parameters to `DocTypeFormHeader`**

  The current call (lines 35–53):

  ```dart
  DocTypeFormHeader(
    title:     slip?.name ?? 'Packing Slip',
    canSave:   isDirty,
    docStatus: slip?.docstatus ?? 0,
    isSaving:  isSaving,
    onSave: slip?.docstatus == 0
        ? controller.savePackingSlip
        : null,
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
  ```

  Replace with:

  ```dart
  DocTypeFormHeader(
    title:       slip?.name ?? 'Packing Slip',
    docType:     'Packing Slip',
    statusLabel: slip?.status,
    canSave:     isDirty,
    docStatus:   slip?.docstatus ?? 0,
    isSaving:    isSaving,
    saveResult:  saveResult,
    onSave: slip?.docstatus == 0
        ? controller.savePackingSlip
        : null,
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
  ```

- [ ] **Step 3: Verify with analyzer**

  ```
  flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
  ```

  Expected: no errors or warnings related to the changed file.

- [ ] **Step 4: Run all tests**

  ```
  flutter test
  ```

  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```
  git add lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
  git commit -m "feat(packing-slip): wire docType, statusLabel, saveResult into DocTypeFormHeader"
  ```
