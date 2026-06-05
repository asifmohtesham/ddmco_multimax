# POS Upload – Share Packing Slip Excel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Share button to the POS Upload form screen that exports loaded packing slip data as a two-format `.xlsx` workbook and shares it via the system share sheet.

**Architecture:** `PosUploadFormController` gains a public static `psCaseCell` (testable case-label helper) and an async `sharePackingSlipExcel({required bool compact})` method that reads the already-loaded `packingSlips` list. `PosUploadFormScreen` reads `controller.packingSlips.isNotEmpty` inside its outer `Obx` to conditionally show the share icon, and adds a `_showShareSheet` method that presents the format-picker bottom sheet.

**Tech Stack:** `excel ^4.0.6` (new), `share_plus ^7.0.0` (existing), `path_provider` (existing), `dart:io` (existing)

---

## File Map

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `excel: ^4.0.6` |
| `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` | Add `psCaseCell` static method + `sharePackingSlipExcel` method + required imports |
| `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart` | Read `packingSlips.isNotEmpty` in outer Obx, wire `onShare`, add `_showShareSheet` |
| `test/unit/pos_upload_ps_case_test.dart` | New unit tests for `psCaseCell` |

---

### Task 1: Add excel dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add `excel: ^4.0.6` under `dependencies:` (after `share_plus`):

```yaml
  share_plus: ^7.0.0
  excel: ^4.0.6
```

- [ ] **Step 2: Fetch packages**

```bash
flutter pub get
```

Expected: resolves without conflicts, lock file updated.

- [ ] **Step 3: Verify no new lint errors**

```bash
flutter analyze
```

Expected: same issue count as before (no new errors from adding the package).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add excel package for packing slip export"
```

---

### Task 2: Add `psCaseCell` static helper + unit tests

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`
- Create: `test/unit/pos_upload_ps_case_test.dart`

The helper determines what value goes in the "Case #" column:
- No `fromCaseNo` → `TextCellValue(ps.name)` (PS name as fallback)
- `fromCaseNo` set, `toCaseNo` null or equal to `fromCaseNo` → `IntCellValue(fromCaseNo)`
- Range (`fromCaseNo != toCaseNo`) → `TextCellValue('N-M')`

Made public static (no underscore) so tests can reach it, matching the `matchPsItems` pattern.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/pos_upload_ps_case_test.dart`:

```dart
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

PackingSlip _ps(String name, int? from, int? to) => PackingSlip(
      name: name,
      deliveryNote: 'DN-001',
      modified: '',
      creation: '',
      docstatus: 1,
      status: 'Submitted',
      items: [],
      fromCaseNo: from,
      toCaseNo: to,
    );

void main() {
  group('PosUploadFormController.psCaseCell', () {
    test('single case (from == to) → IntCellValue with fromCaseNo', () {
      final result = PosUploadFormController.psCaseCell(_ps('PS-001', 3, 3));
      expect(result, isA<IntCellValue>());
      expect((result as IntCellValue).value, 3);
    });

    test('toCaseNo null → IntCellValue with fromCaseNo', () {
      final result = PosUploadFormController.psCaseCell(_ps('PS-001', 5, null));
      expect(result, isA<IntCellValue>());
      expect((result as IntCellValue).value, 5);
    });

    test('range (from != to) → TextCellValue with "from-to" format', () {
      final result = PosUploadFormController.psCaseCell(_ps('PS-001', 1, 5));
      expect(result, isA<TextCellValue>());
      expect((result as TextCellValue).value, '1-5');
    });

    test('no case number → TextCellValue with PS name', () {
      final result =
          PosUploadFormController.psCaseCell(_ps('PS-001', null, null));
      expect(result, isA<TextCellValue>());
      expect((result as TextCellValue).value, 'PS-001');
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
flutter test test/unit/pos_upload_ps_case_test.dart
```

Expected: compile error — `psCaseCell` does not exist yet.

- [ ] **Step 3: Add the static method to the controller**

In `pos_upload_form_controller.dart`, add this static method alongside the existing `matchPsItems` static method (around line 126):

```dart
/// Returns the Excel cell value for the "Case #" column in the packing slip export.
/// Single case → IntCellValue; range → TextCellValue("N-M"); no case → TextCellValue(ps.name).
static CellValue psCaseCell(PackingSlip ps) {
  if (ps.fromCaseNo == null) return TextCellValue(ps.name);
  if (ps.toCaseNo != null && ps.toCaseNo != ps.fromCaseNo) {
    return TextCellValue('${ps.fromCaseNo}-${ps.toCaseNo}');
  }
  return IntCellValue(ps.fromCaseNo!);
}
```

Also add the `excel` import at the top of the controller file (after the existing imports):

```dart
import 'package:excel/excel.dart';
```

- [ ] **Step 4: Run tests — expect pass**

```bash
flutter test test/unit/pos_upload_ps_case_test.dart
```

Expected: 4 tests, all PASS.

- [ ] **Step 5: Verify no lint errors**

```bash
flutter analyze
```

Expected: 0 new errors.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart test/unit/pos_upload_ps_case_test.dart
git commit -m "feat: add psCaseCell static helper to PosUploadFormController"
```

---

### Task 3: Add `sharePackingSlipExcel` to the controller

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

- [ ] **Step 1: Add remaining imports**

At the top of `pos_upload_form_controller.dart`, add (after existing imports):

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
```

(`excel` was already added in Task 2.)

- [ ] **Step 2: Add the method**

Add `sharePackingSlipExcel` to the `PosUploadFormController` class, after the `reloadDocument` override at the end of the file:

```dart
Future<void> sharePackingSlipExcel({required bool compact}) async {
  final upload = posUpload.value;
  if (upload == null || packingSlips.isEmpty) {
    GlobalSnackbar.error(message: 'No packing slip data available');
    return;
  }

  Get.dialog(
    const Center(child: CircularProgressIndicator()),
    barrierDismissible: false,
  );

  try {
    final itemNameByIdx = <String, String>{
      for (final item in upload.items) item.idx.toString(): item.itemName,
    };

    final excelFile = Excel.createExcel();
    excelFile.rename('Sheet1', upload.name);
    final sheet = excelFile[upload.name];

    final headers = compact
        ? ['Case #', 'Invoice Serial #', 'Item Name', 'Qty', 'Country of Origin']
        : ['Case #', 'Invoice Serial #', 'Variant Of', 'Item Code', 'Item Name', 'Qty', 'Country of Origin'];

    for (int c = 0; c < headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = TextCellValue(headers[c]);
    }

    int row = 1;
    for (final ps in packingSlips.where((p) => p.customPoNo == upload.name)) {
      final caseCell = psCaseCell(ps);
      for (final psItem in ps.items) {
        final posItemName =
            itemNameByIdx[psItem.customInvoiceSerialNumber] ?? psItem.itemName;
        final serial =
            int.tryParse(psItem.customInvoiceSerialNumber ?? '') ?? 0;

        void setCell(int col, CellValue v) => sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
            .value = v;

        if (compact) {
          setCell(0, caseCell);
          setCell(1, IntCellValue(serial));
          setCell(2, TextCellValue(posItemName));
          setCell(3, DoubleCellValue(psItem.qty));
          setCell(4, TextCellValue(psItem.customCountryOfOrigin ?? ''));
        } else {
          setCell(0, caseCell);
          setCell(1, IntCellValue(serial));
          setCell(2, TextCellValue(psItem.customVariantOf ?? ''));
          setCell(3, TextCellValue(psItem.itemCode));
          setCell(4, TextCellValue(posItemName));
          setCell(5, DoubleCellValue(psItem.qty));
          setCell(6, TextCellValue(psItem.customCountryOfOrigin ?? ''));
        }
        row++;
      }
    }

    final fileBytes = excelFile.encode();
    if (fileBytes == null) {
      if (Get.isDialogOpen == true) Get.back();
      GlobalSnackbar.error(message: 'Failed to encode Excel file');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final safeName = upload.name.replaceAll('/', '_');
    final filePath = '${tempDir.path}/${safeName}_packing_slip.xlsx';
    await File(filePath).writeAsBytes(fileBytes);

    if (Get.isDialogOpen == true) Get.back();

    await Share.shareXFiles(
      [
        XFile(
          filePath,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      subject: '${upload.name} – Packing Slip',
    );
  } catch (e) {
    if (Get.isDialogOpen == true) Get.back();
    GlobalSnackbar.error(message: 'Share failed: $e');
  }
}
```

- [ ] **Step 3: Verify no lint errors**

```bash
flutter analyze
```

Expected: 0 new errors.

- [ ] **Step 4: Run all unit tests to confirm nothing broken**

```bash
flutter test test/unit/
```

Expected: all existing + Task 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat: add sharePackingSlipExcel to PosUploadFormController"
```

---

### Task 4: Wire share button and bottom sheet in the screen

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

- [ ] **Step 1: Add `_showShareSheet` method to `PosUploadFormScreen`**

Add this method to the `PosUploadFormScreen` class, after the `build` method:

```dart
void _showShareSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      var compact = true;
      return StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Export Packing Slip',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Compact'),
                  subtitle: Text(
                    compact
                        ? 'Case · Serial · Item · Qty · Country'
                        : 'Case · Serial · Variant · Code · Item · Qty · Country',
                  ),
                  value: compact,
                  onChanged: (v) => setState(() => compact = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Share as Excel'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    controller.sharePackingSlipExcel(compact: compact);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 2: Update the outer `Obx` to read `packingSlips` and wire `onShare`**

In `PosUploadFormScreen.build`, the outer `Obx` currently reads:

```dart
return Obx(() {
  final title = controller.posUpload.value?.name.isNotEmpty == true
      ? controller.posUpload.value!.name
      : controller.name.isNotEmpty
          ? controller.name
          : 'POS Upload';
  final isLoading  = controller.isLoading.value;
  final posUpload  = controller.posUpload.value;
```

Replace it with (adding the `hasPackingSlips` read):

```dart
return Obx(() {
  final title = controller.posUpload.value?.name.isNotEmpty == true
      ? controller.posUpload.value!.name
      : controller.name.isNotEmpty
          ? controller.name
          : 'POS Upload';
  final isLoading       = controller.isLoading.value;
  final posUpload       = controller.posUpload.value;
  final hasPackingSlips = controller.packingSlips.isNotEmpty;
```

- [ ] **Step 3: Pass `onShare` to `DocTypeFormHeader`**

The `DocTypeFormHeader` call currently is:

```dart
DocTypeFormHeader(
  title: title,
  bottom: const TabBar(
    tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
  ),
),
```

Replace with:

```dart
DocTypeFormHeader(
  title: title,
  onShare: hasPackingSlips ? () => _showShareSheet(context) : null,
  bottom: const TabBar(
    tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
  ),
),
```

- [ ] **Step 4: Verify no lint errors**

```bash
flutter analyze
```

Expected: 0 new errors.

- [ ] **Step 5: Run all tests**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "feat: add share packing slip Excel to POS Upload form screen"
```

---

### Task 5: Manual verification on device

**Files:** none — verification only

- [ ] **Step 1: Build and run on Android device**

```bash
flutter run -d <device_id>
```

- [ ] **Step 2: Navigate to POS Upload form — no packing slips**

Open a POS Upload that is **not** ML/KA prefix (or one where packing slips haven't loaded).  
Expected: **no share icon** in the app bar.

- [ ] **Step 3: Navigate to POS Upload form — with packing slips**

Open an ML/KA POS Upload that has linked packing slips.  
Expected: share icon **appears** in the app bar once packing slips finish loading.

- [ ] **Step 4: Test Compact format**

Tap share icon → bottom sheet appears with "Compact" toggle **on**.  
Subtitle shows: `Case · Serial · Item · Qty · Country`.  
Tap "Share as Excel" → loading spinner appears briefly → system share sheet opens.  
Share to Files or email. Open the file in Excel or Sheets.  
Expected: single sheet named after the POS Upload document (e.g. `ML-00123`), 5 columns, header row bold-ish, data rows sorted by case number.

- [ ] **Step 5: Test Detailed format**

Tap share icon → bottom sheet → toggle Compact **off**.  
Subtitle shows: `Case · Serial · Variant · Code · Item · Qty · Country`.  
Tap "Share as Excel".  
Expected: 7 columns with Variant Of and Item Code between Serial # and Item Name.

- [ ] **Step 6: Test error path**

In Android developer options, revoke storage permission (or simulate by temporarily making `getTemporaryDirectory` throw). Tap Share.  
Expected: loading spinner dismissed, `GlobalSnackbar` error shown, app does not crash.
