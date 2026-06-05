# Search by Image — Feature Design Spec

**Date:** 2026-06-05  
**Status:** Approved for implementation  
**Scope:** Item search only (hook designed for future extension to other DocTypes)

---

## Overview

A "Search by Image" flow that allows warehouse staff to photograph a product label, automatically detect its EAN-8 or QR barcode, and navigate directly to the matching ERPNext Item — with an optional prompt to enrich the Item record with the scanned photo if no image is set.

No new packages are required. All dependencies (`mobile_scanner`, `image_picker`, `ApiProvider.uploadFile()`) are already in the project.

---

## Entry Point

The feature is accessed via a camera icon injected into `DocTypeSearchDelegate.buildActions`. The icon is shown **only** when the new optional `onImageScanResult` callback is set — meaning it is invisible on every DocType list screen except Item.

`ItemListAppBar` wires the callback; no other list screen is affected.

`ImageScanFlow.run()` returns an `ImageScanResult` value object (not a plain `String`) so both `itemCode` and the optional `batchNo` (present only on the Full Batch No QR path) are available to the caller:

```dart
// Simple value object — lives in image_scan_flow.dart
class ImageScanResult {
  final String itemCode;
  final String? batchNo;
  const ImageScanResult({required this.itemCode, this.batchNo});
}

// DocTypeSearchDelegate — new optional param
final ValueChanged<ImageScanResult>? onImageScanResult;

// In buildActions — icon shown only when callback is provided
if (onImageScanResult != null)
  IconButton(
    icon: const Icon(Icons.image_search),
    onPressed: () async {
      final result = await ImageScanFlow.run(context);
      if (result != null) {
        close(context, null);
        onImageScanResult!(result);
      }
    },
  ),

// In ItemListAppBar — wires result to navigation
onImageScanResult: (result) => Get.toNamed(
  AppRoutes.ITEM_FORM,
  arguments: {'itemCode': result.itemCode, 'batchNo': result.batchNo},
),
```

---

## Architecture

### New files — `lib/app/shared/image_scan/`

The scanner is **Item-agnostic**. `ImageScanFlow.run()` returns a raw item code string; it has no knowledge of ERPNext Items. Item-specific logic is isolated to `ItemScanResultSheet`.

| File | Responsibility |
|---|---|
| `image_scan_flow.dart` | Static `run(context)` entry point. Orchestrates gallery pick → dialog → returns `Future<ImageScanResult?>` |
| `image_scan_controller.dart` | Holds scanned image path, detected barcodes, selected index, lookup state. Calls ERPNext APIs for Item/Batch lookup and `uploadFile()` for enrichment. |
| `barcode_highlight_painter.dart` | `CustomPainter` — draws bounding boxes from `Barcode.corners`, scaled to rendered image dimensions |
| `item_scan_result_sheet.dart` | Bottom sheet over image preview. Shows matched item. Handles enrichment prompt and navigation. |

### Modified files

| File | Change |
|---|---|
| `lib/app/modules/global_widgets/global_search_delegate.dart` | Add optional `onImageScanResult: ValueChanged<ImageScanResult>?` param + camera icon in `buildActions` |
| `lib/app/modules/item/widgets/item_list_app_bar.dart` | Wire `onImageScanResult` → `Get.toNamed(ITEM_FORM, arguments: …)` |

---

## Data Flow

### Step-by-step sequence

1. **Icon tap** — `DocTypeSearchDelegate.buildActions` calls `await ImageScanFlow.run(context)`
2. **Gallery picker** — `ImagePicker().pickImage(source: ImageSource.gallery)`. Cancel → `run()` returns `null` immediately.
3. **Full-screen dialog opens** — selected image renders immediately. `MobileScannerController.analyzeImage(path)` runs concurrently behind a loading overlay.
4. **Analysis result branching:**
   - *No barcodes detected* → show fallback state (see §Fallback below)
   - *Barcodes detected* → `BarcodeHighlightPainter` draws bounding boxes using `Barcode.corners` scaled to render size. Single code → auto-selected. Multiple codes → bottom sheet lists each (format label + raw value); user taps one.
5. **Barcode type routing** — three paths:

   | Detected value | Classification | Lookup |
   |---|---|---|
   | 8 numeric digits | EAN-8 | `item_code = raw.substring(0, 7)` → `GET /api/resource/Item/{item_code}` |
   | 12 or 15 chars containing `-` | QR — Full Batch No | `splitEanBatch(raw)` → `GET /api/resource/Batch/{raw}` → `batch.item` = item_code; navigate with `batchNo` arg |
   | 3 or 6 chars | QR — Batch ID only | Unresolvable — show message + fallback |

   `BarcodeListenerMixin.splitEanBatch()` is reused as-is for the Full Batch No path.

6. **Result bottom sheet** (`ItemScanResultSheet`) slides up over the image preview:
   - Shows: item name, item code, item group
   - Full Batch No path: also shows *Batch: [value]*
   - If `item.image == null`: enrichment row — *"Save this image as the item photo?"*
   - Actions: **"Open"** (navigate only) | **"Save & Open"** (upload then navigate)

7. **Navigation** — `ItemScanResultSheet` calls `Navigator.of(context).pop(ImageScanResult(itemCode: ..., batchNo: ...))`, which propagates back through `ImageScanFlow.run()` to the `onImageScanResult` callback in `ItemListAppBar`. `ItemListAppBar` then calls `Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'itemCode': result.itemCode, 'batchNo': result.batchNo})`. The Full Batch No path sets `batchNo`, which the existing `ItemFormController.highlightedBatchNo` mechanism uses to highlight the correct batch in the Stock tab.

### Fallback state (no barcode / Batch ID only)

Shown in-dialog over the image:
- Message explaining why lookup failed
- **"Try another image"** button — re-opens gallery picker within the same dialog (loops back to step 2)
- **Manual item code text field** — submitting skips directly to the Item lookup (step 5, EAN-8 path logic)

---

## Enrichment Flow

Triggered when `item.image == null` and user taps "Save & Open":

1. `ApiProvider.uploadFile(filePath, doctype: 'Item', docname: itemCode, fieldname: 'image')` → returns relative `file_url`
2. PATCH Item document `image` field with the returned `file_url` — use whichever `ApiProvider` method handles document updates (verify method name against `api_provider.dart` during implementation; `uploadFile` already exists and is confirmed)
3. On success: close dialog → navigate to Item form (image will be visible on load)
4. On upload failure: snackbar error, sheet stays open — user can retry or tap plain "Open"
5. On PATCH failure (upload succeeded): snackbar warning, navigation proceeds regardless

**Enrichment is non-blocking.** A failed upload never prevents the user from reaching the Item form.

---

## Error Handling

| Failure | Recovery |
|---|---|
| Gallery permission denied | Snackbar: *"Gallery access denied"* — close dialog |
| `analyzeImage()` throws | Error overlay on image: *"Could not read image"* + "Try another image" button |
| No barcodes detected | A+B fallback (try again / manual entry) |
| QR = Batch ID only | Message: *"This is a Batch ID — scan the full barcode or enter an item code manually"* + A+B fallback |
| Item/Batch lookup network error | Error state with retry button (re-runs same lookup) |
| Item not found | Result sheet: *"No item found for [value]"* — dismiss returns `null` |
| Batch not found | Result sheet: *"Batch [value] not found"* — dismiss returns `null` |
| `uploadFile()` fails | Snackbar error, sheet stays open for retry or plain "Open" |
| Item `image` PATCH fails | Snackbar warning, navigation proceeds regardless |

---

## Testing Plan

### Unit tests

| Test | Verifies |
|---|---|
| `BarcodeRouter.classify()` | EAN-8 (8 numeric) → `ean8`; `20003609-ESU` → `fullBatchNo`; `ESU` → `batchIdOnly`; `ESU001` → `batchIdOnly` |
| `ean8ToItemCode()` | `"20003609"` → `"2000360"`; rejects non-8-digit strings |
| `splitEanBatch` reuse | Covered by existing mixin tests |
| `BarcodeHighlightPainter` scaling | Image 1000×800 rendered at 300×240 → corners scaled by factor 0.3 |

### Controller tests (mock `ApiProvider`)

| Test | Verifies |
|---|---|
| EAN-8 path | `analyzeImage` returns EAN-8 → calls `GET /Item/2000360` → `found` state, no batchNo |
| Full Batch No path | QR `20003609-ESU` → calls `GET /Batch/20003609-ESU` → `found` state with `batchNo` set |
| Batch ID only | QR `ESU` → `unresolvable` state, no API call |
| Item not found | Empty API response → `notFound` state |
| Network error + retry | API throws → `error` state → retry re-runs lookup |
| Enrichment success | `uploadFile()` returns URL → PATCH called → `enrichmentSaved` emitted |
| Enrichment upload failure | `uploadFile()` throws → `enrichmentError` emitted, navigation not blocked |

### Manual / device tests

- Gallery picker opens and selected image renders in dialog
- Bounding boxes visually align with barcode regions on real product photos
- Single barcode auto-selects; multiple barcodes show selection sheet
- EAN-8 photo → Item form opens
- Full Batch No QR photo → Item form opens, batch tab highlights correct batch
- Item with no image → enrich → Item form shows uploaded photo
- Item with existing image → enrichment row not shown

---

## Out of Scope

- Camera live-scan (feature uses gallery only — live scan is `CameraScanOverlay`)
- Visual product recognition (no barcode present)
- Enrichment for items that already have an image (replace/overwrite flow)
- Non-Item DocType resolution (architecture allows future extension via `onImageScanResult` callback)
