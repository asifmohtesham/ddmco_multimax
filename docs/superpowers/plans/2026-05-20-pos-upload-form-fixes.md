# POS Upload Form Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six issues in the POS Upload form: exclude Cancelled PSes from all counts, rename "matched" to "packed", make Status/Amount/Qty unconditionally read-only, fix the Cases chip quantity, add a chip-row divider, and strip the DN/PS aggregate summary from the Items Tab.

**Architecture:** All business-logic changes live in `pos_upload_form_controller.dart`; all UI changes live in `pos_upload_form_screen.dart`. No new files, no new abstractions.

**Tech Stack:** Flutter, GetX, Dart

---

## Files Modified

| File | What changes |
|------|-------------|
| `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` | Filter cancelled PSes; fix case qty; remove entire permission infrastructure |
| `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart` | Always read-only fields; remove Update button; rename banner text; chip divider; remove DN/PS summary chips |

---

## Task 1 (hotfix): Controller — Filter Cancelled PSes + Fix Case Qty

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

Both changes are in `_fetchPackingSlips`, close together.

- [ ] **Step 1: Filter out Cancelled Packing Slips**

In `_fetchPackingSlips`, find the block that builds `slips` (around line 252–258):

```dart
final slips = <PackingSlip>[];
for (final resp in responses) {
  if (resp.statusCode == 200 && resp.data['data'] != null) {
    slips.add(PackingSlip.fromJson(resp.data['data']));
  }
}
packingSlips.assignAll(slips);
```

Add one line immediately after the `for` loop, before `packingSlips.assignAll`:

```dart
final slips = <PackingSlip>[];
for (final resp in responses) {
  if (resp.statusCode == 200 && resp.data['data'] != null) {
    slips.add(PackingSlip.fromJson(resp.data['data']));
  }
}
slips.removeWhere((ps) => ps.docstatus == 2);   // exclude Cancelled
packingSlips.assignAll(slips);
```

`PackingSlip.docstatus == 2` is the ERPNext convention for Cancelled. The model already parses this field.

- [ ] **Step 2: Fix CaseOption totalQty calculation**

Still in `_fetchPackingSlips`, find the `caseOptions.assignAll(...)` block (around line 295–310). The `posQty` variable sums POS Upload item quantities — replace it with a sum of the PS's own item quantities:

```dart
// BEFORE
caseOptions.assignAll(
  slips
      .where((ps) => matchedPsNames.contains(ps.name))
      .map((ps) {
        final posQty = upload.items
            .where((item) => psMap[item.idx]?.psName == ps.name)
            .fold<double>(0, (s, item) => s + item.quantity);
        return CaseOption(
          psName: ps.name,
          fromCaseNo: ps.fromCaseNo,
          toCaseNo: ps.toCaseNo,
          totalQty: posQty,
        );
      })
      .toList(),
);

// AFTER
caseOptions.assignAll(
  slips
      .where((ps) => matchedPsNames.contains(ps.name))
      .map((ps) {
        final psQty = ps.items
            .fold<double>(0, (s, psItem) => s + psItem.qty);
        return CaseOption(
          psName: ps.name,
          fromCaseNo: ps.fromCaseNo,
          toCaseNo: ps.toCaseNo,
          totalQty: psQty,
        );
      })
      .toList(),
);
```

- [ ] **Step 3: Verify**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
```

Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "fix: exclude cancelled PSes and correct case chip qty in POS Upload"
```

---

## Task 2: Controller — Remove Permission Infrastructure

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

The permission system existed solely to gate Status/Amount/Qty editing, which is now always disabled. Remove all of it.

- [ ] **Step 1: Remove imports no longer needed**

At the top of the file, remove these two import lines:

```dart
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
```

- [ ] **Step 2: Remove provider fields**

Find and delete these two field declarations (around lines 64–66):

```dart
final AuthenticationController _authController =
    Get.find<AuthenticationController>();
final ApiProvider _apiProvider = Get.find<ApiProvider>();
```

- [ ] **Step 3: Remove cached permission fields and observable**

Find and delete these lines (around lines 103–110):

```dart
// ── Permissions (cached after first load) ──────────────────────────────────
final Map<String, int> _fieldLevels = {};
final Map<int, Set<String>> _levelWriteRoles = {};
var permissionsLoaded = false.obs;

// Cached per-field edit flags set once permissions are loaded.
bool _canEditStatus = false;
bool _canEditAmount = false;
bool _canEditQty = false;
```

- [ ] **Step 4: Remove `fetchDocTypePermissions` call from `_loadData`**

Find `_loadData` (around line 129):

```dart
// BEFORE
Future<void> _loadData() async {
  isLoading.value = true;
  await Future.wait([fetchPosUpload(), fetchDocTypePermissions()]);
  isLoading.value = false;
  fetchLinkedDocument();
}

// AFTER
Future<void> _loadData() async {
  isLoading.value = true;
  await fetchPosUpload();
  isLoading.value = false;
  fetchLinkedDocument();
}
```

- [ ] **Step 5: Remove `fetchDocTypePermissions`, `_canEdit`, public getters, and alias**

Delete these methods/getters in their entirety (around lines 386–431):

```dart
Future<void> fetchDocTypePermissions() async {
  try {
    final response =
        await _apiProvider.getDocument('DocType', 'POS Upload');
    if (response.statusCode == 200 && response.data['data'] != null) {
      final data = response.data['data'];
      _fieldLevels['status'] = 0;
      if (data['fields'] != null) {
        for (var field in data['fields']) {
          _fieldLevels[field['fieldname'].toString()] =
              field['permlevel'] as int? ?? 0;
        }
      }
      if (data['permissions'] != null) {
        for (var perm in data['permissions']) {
          final role = perm['role'].toString();
          final level = perm['permlevel'] as int? ?? 0;
          if (perm['write'] == 1) {
            _levelWriteRoles.putIfAbsent(level, () => {}).add(role);
          }
        }
      }
      _canEditStatus = _canEdit('status');
      _canEditAmount = _canEdit('total_amount');
      _canEditQty = _canEdit('total_qty');
      permissionsLoaded.value = true;
    }
  } catch (_) {}
}

bool _canEdit(String fieldName) {
  if (_authController.hasRole('System Manager')) return true;
  final level = _fieldLevels[fieldName] ?? 0;
  final allowed = _levelWriteRoles[level] ?? {};
  return _authController.hasAnyRole(allowed.toList());
}

// Public getters so the UI reads the cached values.
bool get canEditStatus => _canEditStatus;
bool get canEditAmount => _canEditAmount;
bool get canEditQty => _canEditQty;

// Keep old method name for any other callers.
bool canEdit(String fieldName) => _canEdit(fieldName);
```

- [ ] **Step 6: Verify — no analyzer errors**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
```

Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "refactor: remove permission infrastructure from POS Upload form controller"
```

---

## Task 3: Screen — Details Tab: Always Read-Only + Rename Banner Text

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

- [ ] **Step 1: Remove `_canEdit*` state fields**

In `_DetailsTabState`, find and delete these three field declarations (around lines 80–83):

```dart
// Cached permission flags (fix #6)
late final bool _canEditStatus;
late final bool _canEditAmount;
late final bool _canEditQty;
```

- [ ] **Step 2: Remove permission flag assignments in `initState`**

In `initState`, find and delete these three lines (around lines 109–111):

```dart
// Cache permission flags once (fix #6)
_canEditStatus = ctrl.canEditStatus;
_canEditAmount = ctrl.canEditAmount;
_canEditQty = ctrl.canEditQty;
```

- [ ] **Step 3: Make Status DropdownButtonFormField always read-only**

Find the Status dropdown (around lines 245–262). Replace it entirely:

```dart
// BEFORE
DropdownButtonFormField<String>(
  value: upload.status,
  isExpanded: true,
  decoration: InputDecoration(
    labelText: 'Status',
    border: const OutlineInputBorder(),
    filled: !_canEditStatus,
    fillColor: !_canEditStatus ? cs.surfaceContainerHighest : null,
  ),
  items: statusItems
      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
      .toList(),
  onChanged: _canEditStatus
      ? (v) {
          if (v != null) ctrl.updateStatus(v);
        }
      : null,
),

// AFTER
DropdownButtonFormField<String>(
  value: upload.status,
  isExpanded: true,
  decoration: InputDecoration(
    labelText: 'Status',
    border: const OutlineInputBorder(),
    filled: true,
    fillColor: cs.surfaceContainerHighest,
  ),
  items: statusItems
      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
      .toList(),
  onChanged: null,
),
```

- [ ] **Step 4: Make Total Amount TextFormField always read-only**

Find the Total Amount field (around lines 266–282). Replace it entirely:

```dart
// BEFORE
TextFormField(
  controller: _amountCtrl,
  readOnly: !_canEditAmount,
  keyboardType:
      const TextInputType.numberWithOptions(decimal: true),
  decoration: InputDecoration(
    labelText: 'Total Amount',
    border: const OutlineInputBorder(),
    filled: !_canEditAmount,
    fillColor:
        !_canEditAmount ? cs.surfaceContainerHighest : null,
    suffixIcon: !_canEditAmount
        ? const Icon(Icons.lock, size: 16, color: Colors.grey)
        : null,
  ),
),

// AFTER
TextFormField(
  controller: _amountCtrl,
  readOnly: true,
  decoration: InputDecoration(
    labelText: 'Total Amount',
    border: const OutlineInputBorder(),
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
  ),
),
```

- [ ] **Step 5: Make Total Quantity TextFormField always read-only**

Find the Total Quantity field (around lines 284–299). Replace it entirely:

```dart
// BEFORE
TextFormField(
  controller: _qtyCtrl,
  readOnly: !_canEditQty,
  keyboardType: TextInputType.number,
  decoration: InputDecoration(
    labelText: 'Total Quantity',
    border: const OutlineInputBorder(),
    filled: !_canEditQty,
    fillColor:
        !_canEditQty ? cs.surfaceContainerHighest : null,
    suffixIcon: !_canEditQty
        ? const Icon(Icons.lock, size: 16, color: Colors.grey)
        : null,
  ),
),

// AFTER
TextFormField(
  controller: _qtyCtrl,
  readOnly: true,
  decoration: InputDecoration(
    labelText: 'Total Quantity',
    border: const OutlineInputBorder(),
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
  ),
),
```

- [ ] **Step 6: Remove the `canSave` variable and the Update button block**

In `build`, find and delete:

```dart
final canSave = _canEditStatus || _canEditAmount || _canEditQty;
```

Then find and delete the entire Update button block (around lines 301–338):

```dart
if (canSave)
  Obx(() => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: ctrl.isSaving.value
              ? null
              : () {
                  final data = <String, dynamic>{};
                  if (_canEditAmount) {
                    // Strip formatting before parsing (fix #14)
                    final raw = _amountCtrl.text
                        .replaceAll(',', '');
                    data['total_amount'] =
                        double.tryParse(raw) ?? 0.0;
                  }
                  if (_canEditQty) {
                    final raw =
                        _qtyCtrl.text.replaceAll(',', '');
                    data['total_qty'] =
                        double.tryParse(raw) ?? 0.0;
                  }
                  if (data.isNotEmpty) {
                    ctrl.updatePosUpload(data);
                  }
                },
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16)),
          child: ctrl.isSaving.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white))
              : const Text('Update',
                  style: TextStyle(fontSize: 16)),
        ),
      )),
```

- [ ] **Step 7: Rename "items matched" → "items packed" in psBanner**

Find line ~199 in `_DetailsTabState.build`, inside the `psBanner` construction:

```dart
// BEFORE
'$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched / ${ctrl.resolvedSerials.length} items matched',

// AFTER
'$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched / ${ctrl.resolvedSerials.length} items packed',
```

- [ ] **Step 8: Verify**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
```

Expected: no issues.

- [ ] **Step 9: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "fix: make Status/Amount/Qty read-only, remove Update button, rename items banner text"
```

---

## Task 4: Screen — Items Tab: Chip Divider + Remove DN/PS Summary Chips

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

- [ ] **Step 1: Add vertical divider between "All Cases" and individual case chips**

In `_ItemsTabState.build`, find the `ListView.separated` that renders the case filter chips (around line 407). The current `separatorBuilder` uses a uniform `SizedBox`:

```dart
separatorBuilder: (_, __) => const SizedBox(width: 8),
```

Replace with a conditional that inserts a thin vertical line after index 0:

```dart
separatorBuilder: (context, i) => i == 0
    ? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 26,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(width: 8),
        ],
      )
    : const SizedBox(width: 8),
```

- [ ] **Step 2: Rewrite the progress summary strip**

Find the `Obx` block that renders the summary strip (around lines 461–539). Replace it entirely with:

```dart
// ── Progress summary strip ─────────────────────────────────────────────
Obx(() {
  final isLoadingLinked = ctrl.isLoadingLinked.value;
  final isLoadingPS = ctrl.isLoadingPackingSlips.value;
  final linkedType = ctrl.linkedDocType.value;

  if (isLoadingLinked || isLoadingPS) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLoadingLinked
                ? 'Fetching ${linkedType == LinkedDocType.deliveryNote ? 'Delivery Note' : 'Stock Entry'}…'
                : 'Fetching Packing Slips…',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
              borderRadius: BorderRadius.circular(4)),
        ],
      ),
    );
  }

  final activeCase = ctrl.activeCaseFilter.value;
  if (activeCase == null) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: _SummaryChip(
        icon: Icons.inventory_outlined,
        label: activeCase.label,
        color: cs.tertiary,
      ),
    ),
  );
}),
```

Note: `cs` is the `ColorScheme` already in scope in `_ItemsTabState.build` — it's declared as `final cs = Theme.of(context).colorScheme;` at the top of the build method.

- [ ] **Step 3: Verify**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "fix: add case chip divider, remove DN/PS aggregate summary from Items tab"
```

---

## Verification Checklist

After all four tasks:

- [ ] `flutter analyze` — zero issues across both modified files
- [ ] On a POS Upload with a linked DN: PS banner on Details tab shows correct count (no Cancelled PSes included) and says "items packed"
- [ ] Case chips show PS's own packed quantity, not POS Upload item quantities
- [ ] A thin vertical line separates "All Cases" from individual case chips
- [ ] Details tab: Status, Total Amount, Total Quantity are filled/locked; no Update button visible
- [ ] Items Tab: loading spinner still appears while fetching DN/PSes; strip disappears when no case filter is active; strip shows case name when a filter is active
