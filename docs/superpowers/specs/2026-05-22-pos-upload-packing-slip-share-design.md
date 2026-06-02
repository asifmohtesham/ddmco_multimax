# POS Upload – Share Packing Slip Excel

**Date:** 2026-05-22  
**Status:** Approved

## Problem

The POS Upload form screen shows Packing Slip data (case numbers, items, quantities) but provides no way to export or share that data. Warehouse staff need to hand off a structured list to logistics or customers.

## Solution

Add a Share button to the POS Upload form's `DocTypeFormHeader`. Tapping it opens a bottom sheet where the user chooses Compact or Detailed column layout, then shares an `.xlsx` workbook via the system share sheet.

---

## Architecture

No new service or provider. All logic lives in `PosUploadFormController` (consistent with `batch_form_controller` and `item_form_controller`). UI change is entirely in `PosUploadFormScreen`.

### New dependency

```yaml
excel: ^4.0.6
```

Project already has `share_plus`, `path_provider`, and `dart:io` via existing controllers.

---

## Excel Generation

### Sheet

- Single sheet named `upload.name` (e.g. `"ML-00123"`)
- File saved to `getTemporaryDirectory()` as `<upload.name>_packing_slip.xlsx` (slashes replaced with underscores)
- MIME type: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`

### Row source

Iterate `packingSlips` (already sorted `fromCaseNo asc` by the API), filtered to `ps.customPoNo == upload.name`, then each PS's `items` (already sorted by `customInvoiceSerialNumber` in `PackingSlip.fromJson`). No re-sorting needed.

### Item Name lookup

Build `Map<String, String>` of `idx.toString() → itemName` from `posUpload.items` once before the loop.

### Format 1 — Compact (`compact: true`)

| Col | Header | Source |
|-----|--------|--------|
| 0 | Case # | `_psCase(ps)` → `IntCellValue` or `TextCellValue` |
| 1 | Invoice Serial # | `psItem.customInvoiceSerialNumber` as `IntCellValue` |
| 2 | Item Name | POS Upload item name from lookup map |
| 3 | Qty | `psItem.qty` as `DoubleCellValue` |
| 4 | Country of Origin | `psItem.customCountryOfOrigin ?? ''` as `TextCellValue` |

### Format 2 — Detailed (`compact: false`)

| Col | Header | Source |
|-----|--------|--------|
| 0 | Case # | `_psCase(ps)` |
| 1 | Invoice Serial # | `psItem.customInvoiceSerialNumber` as `IntCellValue` |
| 2 | Variant Of | `psItem.customVariantOf ?? ''` |
| 3 | Item Code | `psItem.itemCode` |
| 4 | Item Name | POS Upload item name from lookup map |
| 5 | Qty | `psItem.qty` as `DoubleCellValue` |
| 6 | Country of Origin | `psItem.customCountryOfOrigin ?? ''` |

### Case # helper (`_psCase`)

- `fromCaseNo == null` → `TextCellValue(ps.name)`
- `fromCaseNo != null && toCaseNo == fromCaseNo` (or `toCaseNo == null`) → `IntCellValue(fromCaseNo!)`
- `fromCaseNo != toCaseNo` → `TextCellValue('$fromCaseNo-$toCaseNo')`

---

## Controller Changes (`pos_upload_form_controller.dart`)

New imports:
```dart
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
```

New members:
- `sharePackingSlipExcel({required bool compact})` — generates and shares the workbook
- `_psCase(PackingSlip ps)` → `CellValue` — private case label helper

Loading UX: `Get.dialog(CircularProgressIndicator, barrierDismissible: false)` while file is being written, dismissed before `Share.shareXFiles` is called — same pattern as `item_form_controller.dart:397`.

Error handling: `GlobalSnackbar.error` on any exception; `Get.back()` closes the loading dialog before showing the error.

---

## UI Changes (`pos_upload_form_screen.dart`)

### Share button visibility

Inside the outer `Obx`, add:
```dart
final hasPackingSlips = controller.packingSlips.isNotEmpty;
```

Pass to `DocTypeFormHeader`:
```dart
onShare: hasPackingSlips ? () => _showShareSheet(context) : null,
```

The `DocTypeFormHeader` already hides the share icon when `onShare` is `null`.

### `_showShareSheet(BuildContext context)`

Method on `PosUploadFormScreen`. Uses `showModalBottomSheet` with a `StatefulBuilder`:

- Title: `"Export Packing Slip"`
- `SwitchListTile` labelled `"Compact"`, initial value `true`
  - Subtitle when compact: `"Case · Serial · Item · Qty · Country"`
  - Subtitle when detailed: `"Case · Serial · Variant · Code · Item · Qty · Country"`
- `FilledButton.icon(Icons.table_view_outlined)` labelled `"Share as Excel"`
  - Dismisses the sheet (`Navigator.of(ctx).pop()`)
  - Calls `controller.sharePackingSlipExcel(compact: compact)`

---

## Files Changed

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `excel: ^4.0.6` |
| `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` | Add `sharePackingSlipExcel`, `_psCase` |
| `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart` | Wire share button, add `_showShareSheet` |

No new files. No changes to models, providers, routes, or bindings.
