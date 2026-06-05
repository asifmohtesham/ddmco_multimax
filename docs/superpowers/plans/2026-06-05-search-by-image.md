# Search by Image — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Search by Image" flow to the Item list screen that decodes EAN-8 or QR barcodes from a gallery photo, looks up the matching Item/Batch in ERPNext, and optionally enriches the Item record with the scanned photo.

**Architecture:** `ImageScanFlow.run(context)` is a static async method (same pattern as `CameraScanOverlay.show()`) that returns `Future<ImageScanResult?>`. It is fully self-contained — the caller (DocTypeSearchDelegate) awaits the result and passes it to an optional `onImageScanResult` callback; only `ItemListAppBar` wires that callback. All new code lives under `lib/app/shared/image_scan/`.

**Tech Stack:** Flutter/Dart, GetX (controller + Rx state), `mobile_scanner` (analyzeImage), `image_picker` (gallery), `dart:ui` (image dimensions), `ApiProvider.getDocument` / `uploadFile` / `updateDocument` (ERPNext).

---

## File Map

**Create:**
| File | Responsibility |
|---|---|
| `lib/app/shared/image_scan/image_scan_result.dart` | `ImageScanResult` value object (`itemCode`, optional `batchNo`) |
| `lib/app/shared/image_scan/barcode_router.dart` | `BarcodeType` enum + `BarcodeRouter` pure classification logic |
| `lib/app/shared/image_scan/barcode_highlight_painter.dart` | `CustomPainter` — bounding boxes with BoxFit.contain scaling |
| `lib/app/shared/image_scan/image_scan_controller.dart` | GetX controller — state machine, API calls, enrichment upload |
| `lib/app/shared/image_scan/item_scan_result_sheet.dart` | Bottom panel widget — item info, enrichment row, Open/Save&Open |
| `lib/app/shared/image_scan/image_scan_flow.dart` | `ImageScanFlow.run()` + `_ImageScanDialog` StatefulWidget |
| `test/unit/barcode_router_test.dart` | Unit tests for `BarcodeRouter` |
| `test/unit/barcode_highlight_painter_test.dart` | Unit tests for `BarcodeHighlightPainter.scalePoint` |

**Modify:**
| File | Change |
|---|---|
| `lib/app/modules/global_widgets/global_search_delegate.dart` | Add `onImageScanResult: ValueChanged<ImageScanResult>?` + camera icon in `buildActions` |
| `lib/app/modules/global_widgets/doctype_list_header.dart` | Thread `onImageScanResult` from `DocTypeListHeader` → `_DocTypeListHeaderDelegate` → both `DocTypeSearchDelegate` instantiations |
| `lib/app/modules/item/widgets/item_list_app_bar.dart` | Pass `onImageScanResult` callback to `DocTypeListHeader` → `Get.toNamed(ITEM_FORM)` |

---

## Task 1 — `ImageScanResult` + `BarcodeRouter`

**Files:**
- Create: `lib/app/shared/image_scan/image_scan_result.dart`
- Create: `lib/app/shared/image_scan/barcode_router.dart`
- Test: `test/unit/barcode_router_test.dart`

- [ ] **Step 1.1: Write the failing tests**

Create `test/unit/barcode_router_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/image_scan/barcode_router.dart';

void main() {
  group('BarcodeRouter.classify', () {
    test('8 numeric digits → ean8', () {
      expect(BarcodeRouter.classify('20003609'), BarcodeType.ean8);
    });
    test('7 digits → unknown (not 8)', () {
      expect(BarcodeRouter.classify('2000360'), BarcodeType.unknown);
    });
    test('8 non-numeric → unknown', () {
      expect(BarcodeRouter.classify('ABCDEFGH'), BarcodeType.unknown);
    });
    test('12 chars with hyphen → fullBatchNo', () {
      expect(BarcodeRouter.classify('20003609-ESU'), BarcodeType.fullBatchNo);
    });
    test('15 chars with hyphen → fullBatchNo', () {
      expect(BarcodeRouter.classify('20003609-ESU001'), BarcodeType.fullBatchNo);
    });
    test('12 chars no hyphen → unknown', () {
      expect(BarcodeRouter.classify('200036090ESU'), BarcodeType.unknown);
    });
    test('3 chars → batchIdOnly', () {
      expect(BarcodeRouter.classify('ESU'), BarcodeType.batchIdOnly);
    });
    test('6 chars → batchIdOnly', () {
      expect(BarcodeRouter.classify('ESU001'), BarcodeType.batchIdOnly);
    });
    test('trims leading/trailing whitespace before classifying', () {
      expect(BarcodeRouter.classify('  20003609  '), BarcodeType.ean8);
    });
  });

  group('BarcodeRouter.ean8ToItemCode', () {
    test('extracts first 7 digits', () {
      expect(BarcodeRouter.ean8ToItemCode('20003609'), '2000360');
    });
    test('throws ArgumentError on input shorter than 8', () {
      expect(() => BarcodeRouter.ean8ToItemCode('1234567'), throwsArgumentError);
    });
    test('throws ArgumentError on non-numeric 8-char input', () {
      expect(() => BarcodeRouter.ean8ToItemCode('ABCDEFGH'), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 1.2: Run tests — expect failure**

```
flutter test test/unit/barcode_router_test.dart
```

Expected: compilation error — `BarcodeRouter`, `BarcodeType` not found.

- [ ] **Step 1.3: Create `image_scan_result.dart`**

```dart
// lib/app/shared/image_scan/image_scan_result.dart
class ImageScanResult {
  final String itemCode;
  final String? batchNo;

  const ImageScanResult({required this.itemCode, this.batchNo});

  @override
  bool operator ==(Object other) =>
      other is ImageScanResult &&
      other.itemCode == itemCode &&
      other.batchNo == batchNo;

  @override
  int get hashCode => Object.hash(itemCode, batchNo);
}
```

- [ ] **Step 1.4: Create `barcode_router.dart`**

```dart
// lib/app/shared/image_scan/barcode_router.dart
enum BarcodeType { ean8, fullBatchNo, batchIdOnly, unknown }

class BarcodeRouter {
  /// Classifies a raw barcode value based on its length and content.
  ///
  /// EAN-8:        8 numeric digits          → [BarcodeType.ean8]
  /// Full Batch No: 12 or 15 chars with '-'  → [BarcodeType.fullBatchNo]
  /// Batch ID only: 3 or 6 chars             → [BarcodeType.batchIdOnly]
  /// Anything else                           → [BarcodeType.unknown]
  static BarcodeType classify(String raw) {
    final s = raw.trim();
    if (s.length == 8 && int.tryParse(s) != null) return BarcodeType.ean8;
    if ((s.length == 12 || s.length == 15) && s.contains('-')) {
      return BarcodeType.fullBatchNo;
    }
    if (s.length == 3 || s.length == 6) return BarcodeType.batchIdOnly;
    return BarcodeType.unknown;
  }

  /// Extracts the 7-digit item code from an 8-digit EAN-8 string.
  ///
  /// Throws [ArgumentError] if [ean8] is not exactly 8 numeric digits.
  static String ean8ToItemCode(String ean8) {
    if (ean8.length != 8 || int.tryParse(ean8) == null) {
      throw ArgumentError('Expected 8-digit numeric EAN-8, got: "$ean8"');
    }
    return ean8.substring(0, 7);
  }
}
```

- [ ] **Step 1.5: Run tests — expect pass**

```
flutter test test/unit/barcode_router_test.dart
```

Expected: All tests pass.

- [ ] **Step 1.6: Commit**

```
git add lib/app/shared/image_scan/image_scan_result.dart lib/app/shared/image_scan/barcode_router.dart test/unit/barcode_router_test.dart
git commit -m "feat(image-scan): add ImageScanResult value object and BarcodeRouter"
```

---

## Task 2 — `BarcodeHighlightPainter`

**Files:**
- Create: `lib/app/shared/image_scan/barcode_highlight_painter.dart`
- Test: `test/unit/barcode_highlight_painter_test.dart`

- [ ] **Step 2.1: Write failing tests**

Create `test/unit/barcode_highlight_painter_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/image_scan/barcode_highlight_painter.dart';

void main() {
  group('BarcodeHighlightPainter.scalePoint — BoxFit.contain logic', () {
    // Image 1000×800, Render 300×300:
    // scaleX = 0.3, scaleY = 0.375 → scale = min = 0.3
    // offsetX = (300 - 1000*0.3) / 2 = 0
    // offsetY = (300 - 800*0.3)  / 2 = (300 - 240) / 2 = 30 (letterbox)
    const image = Size(1000, 800);
    const render = Size(300, 300);

    test('top-left corner → render origin + letterbox offsetY', () {
      final result = BarcodeHighlightPainter.scalePoint(
          Offset.zero, image, render);
      expect(result.dx, closeTo(0.0, 0.001));
      expect(result.dy, closeTo(30.0, 0.001));
    });

    test('bottom-right corner fills render width, fits inside height', () {
      final result = BarcodeHighlightPainter.scalePoint(
          const Offset(1000, 800), image, render);
      expect(result.dx, closeTo(300.0, 0.001));
      expect(result.dy, closeTo(270.0, 0.001)); // 800*0.3 + 30 = 270
    });

    test('centre of image maps to centre of render', () {
      final result = BarcodeHighlightPainter.scalePoint(
          const Offset(500, 400), image, render);
      expect(result.dx, closeTo(150.0, 0.001));
      expect(result.dy, closeTo(150.0, 0.001)); // 400*0.3 + 30 = 150
    });

    test('pillarbox — tall image, wide render', () {
      // Image 800×1000, Render 300×300:
      // scaleX = 0.375, scaleY = 0.3 → scale = 0.3
      // offsetX = (300 - 800*0.3) / 2 = 30, offsetY = 0
      final result = BarcodeHighlightPainter.scalePoint(
          Offset.zero,
          const Size(800, 1000),
          const Size(300, 300));
      expect(result.dx, closeTo(30.0, 0.001));
      expect(result.dy, closeTo(0.0, 0.001));
    });

    test('exact fit — no offset', () {
      final result = BarcodeHighlightPainter.scalePoint(
          const Offset(150, 150),
          const Size(300, 300),
          const Size(300, 300));
      expect(result.dx, closeTo(150.0, 0.001));
      expect(result.dy, closeTo(150.0, 0.001));
    });
  });
}
```

- [ ] **Step 2.2: Run tests — expect failure**

```
flutter test test/unit/barcode_highlight_painter_test.dart
```

Expected: compilation error — `BarcodeHighlightPainter` not found.

- [ ] **Step 2.3: Create `barcode_highlight_painter.dart`**

```dart
// lib/app/shared/image_scan/barcode_highlight_painter.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Draws bounding-box overlays over detected barcodes, scaled to match a
/// [BoxFit.contain] image rendered inside the paint area.
class BarcodeHighlightPainter extends CustomPainter {
  final List<Barcode> barcodes;
  final int? selectedIndex;

  /// Natural pixel dimensions of the source image.
  final Size imageSize;

  const BarcodeHighlightPainter({
    required this.barcodes,
    required this.imageSize,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero) return;

    for (var i = 0; i < barcodes.length; i++) {
      final corners = barcodes[i].corners;
      if (corners == null || corners.isEmpty) continue;

      final isSelected = selectedIndex == i;
      final paint = Paint()
        ..color = isSelected ? Colors.greenAccent : Colors.orangeAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 2.0;

      final path = Path();
      final pts = corners
          .map((o) => scalePoint(Offset(o.x, o.y), imageSize, size))
          .toList();
      path.moveTo(pts[0].dx, pts[0].dy);
      for (var j = 1; j < pts.length; j++) {
        path.lineTo(pts[j].dx, pts[j].dy);
      }
      path.close();
      canvas.drawPath(path, paint);

      // Label (index) near top-left corner of box
      final labelOffset = pts[0] + const Offset(4, -18);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: isSelected ? Colors.greenAccent : Colors.orangeAccent,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(BarcodeHighlightPainter old) =>
      old.barcodes != barcodes ||
      old.selectedIndex != selectedIndex ||
      old.imageSize != imageSize;

  /// Scales [point] from natural image pixel coordinates to [renderSize]
  /// applying BoxFit.contain logic: uniform scale, centred with letterbox or
  /// pillarbox offset.
  ///
  /// Exposed as a static method so it can be tested without a canvas.
  static Offset scalePoint(Offset point, Size imageSize, Size renderSize) {
    final scaleX = renderSize.width / imageSize.width;
    final scaleY = renderSize.height / imageSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (renderSize.width - imageSize.width * scale) / 2;
    final offsetY = (renderSize.height - imageSize.height * scale) / 2;
    return Offset(point.dx * scale + offsetX, point.dy * scale + offsetY);
  }
}
```

- [ ] **Step 2.4: Run tests — expect pass**

```
flutter test test/unit/barcode_highlight_painter_test.dart
```

Expected: All 5 tests pass.

- [ ] **Step 2.5: Commit**

```
git add lib/app/shared/image_scan/barcode_highlight_painter.dart test/unit/barcode_highlight_painter_test.dart
git commit -m "feat(image-scan): add BarcodeHighlightPainter with BoxFit.contain scaling"
```

---

## Task 3 — `ImageScanController`

**Files:**
- Create: `lib/app/shared/image_scan/image_scan_controller.dart`

No automated tests — this controller makes live API calls (no mocking in this codebase). Covered by manual device tests in Task 6 smoke-test.

- [ ] **Step 3.1: Create `image_scan_controller.dart`**

```dart
// lib/app/shared/image_scan/image_scan_controller.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/shared/image_scan/barcode_router.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

enum ImageScanState {
  idle,
  analyzing,
  noBarcode,
  barcodeFound,
  looking,
  found,
  notFound,
  unresolvable,
  error,
}

class ImageScanController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  final imageNaturalSize = Rx<Size>(Size.zero);
  final barcodes = <Barcode>[].obs;
  final selectedBarcodeIndex = RxnInt();
  final scanState = ImageScanState.idle.obs;
  final errorMessage = ''.obs;

  final foundItemCode = RxnString();
  final foundItemName = RxnString();
  final foundItemGroup = RxnString();
  final foundItemHasImage = false.obs;
  final foundBatchNo = RxnString();
  final isEnriching = false.obs;

  /// Reads [path], decodes its dimensions, then scans for barcodes.
  /// If exactly one barcode is found it is auto-selected and looked up.
  Future<void> analyzeImage(String path, MobileScannerController scanner) async {
    barcodes.clear();
    selectedBarcodeIndex.value = null;
    scanState.value = ImageScanState.analyzing;

    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      imageNaturalSize.value =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());

      final capture = await scanner.analyzeImage(path);
      if (capture == null || capture.barcodes.isEmpty) {
        scanState.value = ImageScanState.noBarcode;
        return;
      }

      barcodes.value = capture.barcodes;
      scanState.value = ImageScanState.barcodeFound;

      if (barcodes.length == 1) await selectBarcode(0);
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] analyzeImage: $e');
      errorMessage.value = 'Could not read image';
      scanState.value = ImageScanState.error;
    }
  }

  /// Called when the user taps a barcode in the highlight overlay or the
  /// multi-barcode picker sheet.
  Future<void> selectBarcode(int index) async {
    selectedBarcodeIndex.value = index;
    await _route(barcodes[index].rawValue ?? '');
  }

  /// Called when the user submits the manual item code text field.
  Future<void> lookupManual(String itemCode) async {
    await _lookupItem(itemCode.trim(), batchNo: null);
  }

  /// Re-runs the lookup for the currently selected barcode — used by the retry
  /// button shown on network errors.
  Future<void> retryLookup() async {
    final idx = selectedBarcodeIndex.value;
    if (idx != null && idx < barcodes.length) {
      await _route(barcodes[idx].rawValue ?? '');
    }
  }

  Future<void> _route(String raw) async {
    switch (BarcodeRouter.classify(raw)) {
      case BarcodeType.ean8:
        await _lookupItem(BarcodeRouter.ean8ToItemCode(raw), batchNo: null);
      case BarcodeType.fullBatchNo:
        await _lookupBatch(raw);
      case BarcodeType.batchIdOnly:
        errorMessage.value =
            'This is a Batch ID — scan the full barcode or enter an item code manually.';
        scanState.value = ImageScanState.unresolvable;
      case BarcodeType.unknown:
        errorMessage.value = 'Unrecognised barcode format.';
        scanState.value = ImageScanState.unresolvable;
    }
  }

  Future<void> _lookupItem(String itemCode, {required String? batchNo}) async {
    scanState.value = ImageScanState.looking;
    try {
      final response = await _api.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'] as Map<String, dynamic>;
        foundItemCode.value = itemCode;
        foundItemName.value = data['item_name'] as String?;
        foundItemGroup.value = data['item_group'] as String?;
        final img = data['image'];
        foundItemHasImage.value = img != null && (img as String).isNotEmpty;
        foundBatchNo.value = batchNo;
        scanState.value = ImageScanState.found;
      } else {
        scanState.value = ImageScanState.notFound;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] _lookupItem: $e');
      errorMessage.value = e.toString();
      scanState.value = ImageScanState.error;
    }
  }

  Future<void> _lookupBatch(String batchNo) async {
    scanState.value = ImageScanState.looking;
    try {
      final response = await _api.getDocument('Batch', batchNo);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'] as Map<String, dynamic>;
        final itemCode = data['item'] as String?;
        if (itemCode == null || itemCode.isEmpty) {
          scanState.value = ImageScanState.notFound;
          return;
        }
        await _lookupItem(itemCode, batchNo: batchNo);
      } else {
        scanState.value = ImageScanState.notFound;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] _lookupBatch: $e');
      errorMessage.value = e.toString();
      scanState.value = ImageScanState.error;
    }
  }

  /// Uploads [filePath] as the Item image and PATCHes the `image` field.
  /// Returns [ImageScanResult] on success, or `null` on any failure.
  Future<ImageScanResult?> enrichAndComplete(String filePath) async {
    final itemCode = foundItemCode.value;
    if (itemCode == null) return null;

    isEnriching.value = true;
    try {
      final fileUrl = await _api.uploadFile(
        filePath: filePath,
        doctype: 'Item',
        docname: itemCode,
        fieldname: 'image',
      );
      await _api.updateDocument('Item', itemCode, {'image': fileUrl});
      return ImageScanResult(itemCode: itemCode, batchNo: foundBatchNo.value);
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageScanController] enrichAndComplete: $e');
      return null;
    } finally {
      isEnriching.value = false;
    }
  }

  /// Builds the result without enrichment. Call when the user taps "Open".
  ImageScanResult buildResult() => ImageScanResult(
        itemCode: foundItemCode.value!,
        batchNo: foundBatchNo.value,
      );
}
```

- [ ] **Step 3.2: Run static analysis**

```
flutter analyze lib/app/shared/image_scan/image_scan_controller.dart
```

Expected: No errors.

- [ ] **Step 3.3: Commit**

```
git add lib/app/shared/image_scan/image_scan_controller.dart
git commit -m "feat(image-scan): add ImageScanController state machine"
```

---

## Task 4 — `ItemScanResultSheet`

**Files:**
- Create: `lib/app/shared/image_scan/item_scan_result_sheet.dart`

- [ ] **Step 4.1: Create `item_scan_result_sheet.dart`**

```dart
// lib/app/shared/image_scan/item_scan_result_sheet.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/shared/image_scan/image_scan_controller.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';

/// Bottom panel shown inside the scan dialog when an Item or Batch has been
/// resolved. Slides up from the bottom of the Stack — not a separate route.
class ItemScanResultSheet extends StatelessWidget {
  final ImageScanController controller;
  final String imagePath;

  const ItemScanResultSheet({
    super.key,
    required this.controller,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() => _build(context, controller.scanState.value));
  }

  Widget _build(BuildContext context, ImageScanState state) {
    if (state == ImageScanState.notFound) return _notFoundPanel(context);
    if (state == ImageScanState.found) return _foundPanel(context);
    return const SizedBox.shrink();
  }

  // ── Not-found panel ─────────────────────────────────────────────────────────

  Widget _notFoundPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return _panel(
      cs: cs,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.search_off, color: cs.error, size: 28),
          const SizedBox(height: 8),
          Text('No item found',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('No matching Item in ERPNext.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Dismiss'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Found panel ─────────────────────────────────────────────────────────────

  Widget _foundPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Obx(() {
      final itemCode = controller.foundItemCode.value!;
      final itemName = controller.foundItemName.value ?? itemCode;
      final itemGroup = controller.foundItemGroup.value ?? '';
      final hasImage = controller.foundItemHasImage.value;
      final batchNo = controller.foundBatchNo.value;
      final isEnriching = controller.isEnriching.value;

      return _panel(
        cs: cs,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: cs.primary, size: 20),
                const SizedBox(width: 6),
                Text('Item Found',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),

            // ── Item name ────────────────────────────────────────────────
            Text(itemName,
                style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),

            // ── Item code pill ───────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(itemCode,
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSecondaryContainer)),
            ),

            // ── Item group ───────────────────────────────────────────────
            if (itemGroup.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(itemGroup,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],

            // ── Batch context ────────────────────────────────────────────
            if (batchNo != null) ...[
              const SizedBox(height: 4),
              Text('Batch: $batchNo',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ],

            // ── Enrichment row (only when item has no image) ─────────────
            if (!hasImage) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: cs.onTertiaryContainer, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Save this image as the item photo?',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Actions ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isEnriching
                        ? null
                        : () => Navigator.of(context)
                            .pop(controller.buildResult()),
                    child: const Text('Open'),
                  ),
                ),
                if (!hasImage) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isEnriching
                          ? null
                          : () => _saveAndOpen(context),
                      child: isEnriching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Text('Save & Open'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    });
  }

  Future<void> _saveAndOpen(BuildContext context) async {
    final result = await controller.enrichAndComplete(imagePath);
    if (!context.mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      GlobalSnackbar.error(
          message:
              'Could not save image. Tap "Open" to continue without saving.');
    }
  }

  // ── Shared panel shell ──────────────────────────────────────────────────────

  Widget _panel({required ColorScheme cs, required Widget child}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16)
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4.2: Run static analysis**

```
flutter analyze lib/app/shared/image_scan/item_scan_result_sheet.dart
```

Expected: No errors.

- [ ] **Step 4.3: Commit**

```
git add lib/app/shared/image_scan/item_scan_result_sheet.dart
git commit -m "feat(image-scan): add ItemScanResultSheet"
```

---

## Task 5 — `ImageScanFlow` + `_ImageScanDialog`

**Files:**
- Create: `lib/app/shared/image_scan/image_scan_flow.dart`

- [ ] **Step 5.1: Create `image_scan_flow.dart`**

```dart
// lib/app/shared/image_scan/image_scan_flow.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/shared/image_scan/barcode_highlight_painter.dart';
import 'package:multimax/app/shared/image_scan/image_scan_controller.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';
import 'package:multimax/app/shared/image_scan/item_scan_result_sheet.dart';

/// Entry point for the search-by-image flow.
///
/// Call [run] from any context that has a valid [BuildContext]. It opens the
/// gallery, displays a full-screen scan dialog, and returns the resolved
/// [ImageScanResult], or `null` if the user cancelled at any point.
class ImageScanFlow {
  static Future<ImageScanResult?> run(BuildContext context) async {
    final file =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    if (!context.mounted) return null;

    return showDialog<ImageScanResult>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => _ImageScanDialog(initialImagePath: file.path),
    );
  }
}

// ── Full-screen dialog ─────────────────────────────────────────────────────────

class _ImageScanDialog extends StatefulWidget {
  final String initialImagePath;
  const _ImageScanDialog({required this.initialImagePath});

  @override
  State<_ImageScanDialog> createState() => _ImageScanDialogState();
}

class _ImageScanDialogState extends State<_ImageScanDialog> {
  late final ImageScanController _ctrl;
  late final MobileScannerController _scanner;
  late Worker _stateWorker;
  late String _currentPath;
  final _manualFieldCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialImagePath;
    _scanner = MobileScannerController();
    _ctrl = Get.put(ImageScanController(), tag: 'image_scan_dialog');
    // Use ever() to react to state changes outside the build phase.
    // This is the only safe way to trigger showModalBottomSheet in response
    // to Rx state changes inside a StatefulWidget.
    _stateWorker = ever(_ctrl.scanState, _onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctrl.analyzeImage(_currentPath, _scanner);
    });
  }

  void _onStateChanged(ImageScanState state) {
    if (!mounted) return;
    if (state == ImageScanState.barcodeFound && _ctrl.barcodes.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBarcodePickerSheet();
      });
    }
  }

  @override
  void dispose() {
    _stateWorker.dispose();
    _scanner.dispose();
    _manualFieldCtrl.dispose();
    Get.delete<ImageScanController>(tag: 'image_scan_dialog');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('Search by Image'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _ImageLayer(imagePath: _currentPath, controller: _ctrl),
            Obx(() => _buildOverlay(_ctrl.scanState.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(ImageScanState state) {
    switch (state) {
      case ImageScanState.analyzing:
      case ImageScanState.looking:
        return const _LoadingOverlay();
      case ImageScanState.noBarcode:
        return _FallbackOverlay(
          message: 'No barcode detected in this image.',
          onTryAgain: _tryAnotherImage,
          manualController: _manualFieldCtrl,
          onManualSubmit: _ctrl.lookupManual,
        );
      case ImageScanState.unresolvable:
      case ImageScanState.error:
        return _FallbackOverlay(
          message: _ctrl.errorMessage.value,
          onTryAgain: _tryAnotherImage,
          manualController: _manualFieldCtrl,
          onManualSubmit: _ctrl.lookupManual,
        );
      case ImageScanState.found:
      case ImageScanState.notFound:
        return ItemScanResultSheet(
            controller: _ctrl, imagePath: _currentPath);
      case ImageScanState.idle:
      case ImageScanState.barcodeFound:
        return const SizedBox.shrink();
    }
  }

  Future<void> _tryAnotherImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _currentPath = file.path);
    await _ctrl.analyzeImage(file.path, _scanner);
  }

  void _showBarcodePickerSheet() {
    final barcodes = _ctrl.barcodes;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Multiple barcodes detected — pick one:',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: barcodes.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.qr_code),
              title: Text(barcodes[i].rawValue ?? '—'),
              subtitle: Text(barcodes[i].format.name),
              onTap: () {
                Navigator.of(context).pop();
                _ctrl.selectBarcode(i);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Image + highlight layer ────────────────────────────────────────────────────

class _ImageLayer extends StatelessWidget {
  final String imagePath;
  final ImageScanController controller;

  const _ImageLayer({required this.imagePath, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(imagePath), fit: BoxFit.contain),
            if (controller.barcodes.isNotEmpty &&
                controller.imageNaturalSize.value != Size.zero)
              CustomPaint(
                painter: BarcodeHighlightPainter(
                  barcodes: controller.barcodes,
                  imageSize: controller.imageNaturalSize.value,
                  selectedIndex: controller.selectedBarcodeIndex.value,
                ),
              ),
          ],
        ));
  }
}

// ── Loading overlay ────────────────────────────────────────────────────────────

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

// ── Fallback overlay (no barcode / unresolvable / error) ──────────────────────

class _FallbackOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onTryAgain;
  final TextEditingController manualController;
  final ValueChanged<String> onManualSubmit;

  const _FallbackOverlay({
    required this.message,
    required this.onTryAgain,
    required this.manualController,
    required this.onManualSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_search, color: Colors.white70, size: 64),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onTryAgain,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Try another image'),
          ),
          const SizedBox(height: 20),
          const Text('— or —',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: manualController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter item code',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.white70),
                onPressed: () {
                  final code = manualController.text.trim();
                  if (code.isNotEmpty) onManualSubmit(code);
                },
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              final code = v.trim();
              if (code.isNotEmpty) onManualSubmit(code);
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5.2: Run static analysis**

```
flutter analyze lib/app/shared/image_scan/image_scan_flow.dart
```

Expected: No errors.

- [ ] **Step 5.3: Commit**

```
git add lib/app/shared/image_scan/image_scan_flow.dart
git commit -m "feat(image-scan): add ImageScanFlow dialog and fallback overlay"
```

---

## Task 6 — Wire `DocTypeSearchDelegate`

**Files:**
- Modify: `lib/app/modules/global_widgets/global_search_delegate.dart`

- [ ] **Step 6.1: Add `onImageScanResult` field and camera icon**

In `global_search_delegate.dart`, add the import at the top:

```dart
import 'package:multimax/app/shared/image_scan/image_scan_flow.dart';
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';
```

Add the new field alongside the existing ones in `DocTypeSearchDelegate`:

```dart
// ── Image scan (optional) ──────────────────────────────────────────────
/// Called when the user picks an image that resolves to an Item.
/// When non-null, a camera icon is shown in the search bar actions.
final ValueChanged<ImageScanResult>? onImageScanResult;
```

Update the constructor to include `this.onImageScanResult`:

```dart
DocTypeSearchDelegate({
  this.doctype = '',
  this.targetRoute = '',
  this.searchQuery,
  this.onSearchChanged,
  this.onSearchClear,
  this.activeFilters,
  this.onFilterTap,
  this.onImageScanResult,   // ← add this line
});
```

Add the camera icon at the **end** of the `buildActions` return list, after the existing filter button:

```dart
// Camera icon — only shown when caller provides onImageScanResult.
if (onImageScanResult != null)
  IconButton(
    icon: const Icon(Icons.image_search),
    tooltip: 'Search by image',
    onPressed: () async {
      final result = await ImageScanFlow.run(context);
      if (result != null) {
        close(context, null);
        onImageScanResult!(result);
      }
    },
  ),
```

- [ ] **Step 6.2: Run analysis**

```
flutter analyze lib/app/modules/global_widgets/global_search_delegate.dart
```

Expected: No errors.

- [ ] **Step 6.3: Commit**

```
git add lib/app/modules/global_widgets/global_search_delegate.dart
git commit -m "feat(image-scan): add onImageScanResult callback and camera icon to DocTypeSearchDelegate"
```

---

## Task 7 — Thread `DocTypeListHeader`

**Files:**
- Modify: `lib/app/modules/global_widgets/doctype_list_header.dart`

`DocTypeListHeader` creates `DocTypeSearchDelegate` deep inside `_DocTypeListHeaderDelegate`. The `onImageScanResult` parameter must be threaded through both classes.

- [ ] **Step 7.1: Add import**

At the top of `doctype_list_header.dart`, add:

```dart
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';
```

- [ ] **Step 7.2: Add field to `DocTypeListHeader`**

After the existing `onSearchClear` field declaration (around line 184):

```dart
/// When non-null, the search delegate shows a camera icon that opens the
/// image scan flow. Only [ItemListAppBar] sets this.
final ValueChanged<ImageScanResult>? onImageScanResult;
```

Add `this.onImageScanResult` to the `DocTypeListHeader` constructor (after `onSearchClear`):

```dart
this.onImageScanResult,
```

- [ ] **Step 7.3: Pass through in `_buildSliver`**

In `_buildSliver`, pass `onImageScanResult` to `_DocTypeListHeaderDelegate` (after `onSearchClear`):

```dart
onImageScanResult: onImageScanResult,
```

- [ ] **Step 7.4: Add field and constructor param to `_DocTypeListHeaderDelegate`**

After the `onSearchClear` field declaration in `_DocTypeListHeaderDelegate`:

```dart
final ValueChanged<ImageScanResult>? onImageScanResult;
```

Add `required this.onImageScanResult` to `_DocTypeListHeaderDelegate`'s constructor (after `onSearchClear`):

```dart
required this.onImageScanResult,
```

- [ ] **Step 7.5: Pass `onImageScanResult` to both `DocTypeSearchDelegate` instantiations**

There are **two** places in `_DocTypeListHeaderDelegate` where `DocTypeSearchDelegate` is instantiated (around lines 646 and 687). Add `onImageScanResult: onImageScanResult,` to both:

```dart
// First instantiation (searchQuery != null branch, ~line 646):
delegate: DocTypeSearchDelegate(
  doctype: searchDoctype ?? '',
  targetRoute: searchRoute ?? '',
  searchQuery: searchQuery,
  onSearchChanged: onSearchChanged,
  onSearchClear: onSearchClear,
  activeFilters: null,
  onFilterTap: null,
  onImageScanResult: onImageScanResult,   // ← add
),

// Second instantiation (pure API search branch, ~line 687):
delegate: DocTypeSearchDelegate(
  doctype: searchDoctype ?? '',
  targetRoute: searchRoute ?? '',
  searchQuery: null,
  onSearchChanged: onSearchChanged,
  onSearchClear: onSearchClear,
  activeFilters: null,
  onFilterTap: null,
  onImageScanResult: onImageScanResult,   // ← add
),
```

- [ ] **Step 7.6: Run analysis**

```
flutter analyze lib/app/modules/global_widgets/doctype_list_header.dart
```

Expected: No errors.

- [ ] **Step 7.7: Commit**

```
git add lib/app/modules/global_widgets/doctype_list_header.dart
git commit -m "feat(image-scan): thread onImageScanResult through DocTypeListHeader"
```

---

## Task 8 — Wire `ItemListAppBar`

**Files:**
- Modify: `lib/app/modules/item/widgets/item_list_app_bar.dart`

- [ ] **Step 8.1: Add import**

At the top of `item_list_app_bar.dart`, add:

```dart
import 'package:multimax/app/data/routes/app_routes.dart';  // already present
import 'package:multimax/app/shared/image_scan/image_scan_result.dart';
```

- [ ] **Step 8.2: Pass `onImageScanResult` to `DocTypeListHeader`**

Inside `ItemListAppBar.build()`, add `onImageScanResult` to the `DocTypeListHeader(...)` call (after `onSearchClear`):

```dart
onImageScanResult: (ImageScanResult result) {
  Get.toNamed(
    AppRoutes.ITEM_FORM,
    arguments: {
      'itemCode': result.itemCode,
      'batchNo': result.batchNo,
    },
  );
},
```

- [ ] **Step 8.3: Run analysis**

```
flutter analyze lib/app/modules/item/widgets/item_list_app_bar.dart
```

Expected: No errors.

- [ ] **Step 8.4: Run full analysis**

```
flutter analyze
```

Expected: No errors across the project.

- [ ] **Step 8.5: Run all unit tests**

```
flutter test test/unit/
```

Expected: All tests pass (including the 2 new test files from Tasks 1 and 2).

- [ ] **Step 8.6: Commit**

```
git add lib/app/modules/item/widgets/item_list_app_bar.dart
git commit -m "feat(image-scan): wire onImageScanResult in ItemListAppBar"
```

---

## Manual Smoke Test Checklist

Run on a physical Android device with DataWedge available.

- [ ] Dashboard → Items → tap Search icon → camera icon visible in search bar actions
- [ ] Tap camera icon → gallery opens → cancel → search overlay stays open (no crash)
- [ ] Pick image with no barcode → "No barcode detected" message shown + "Try another image" button + manual field visible
- [ ] "Try another image" → gallery re-opens inside same dialog (no flicker)
- [ ] Type item code in manual field → Submit → item found → result sheet slides up
- [ ] Pick image with EAN-8 → bounding box drawn over barcode → item found → result sheet slides up → "Open" → Item form opens
- [ ] Item has no image → enrichment row visible → "Save & Open" → upload progress → Item form opens with image
- [ ] Item already has image → enrichment row NOT shown → only "Open" action
- [ ] Pick image with Full Batch No QR (`XXXXXXXX-YYY`) → item found → result sheet shows "Batch: ..." → "Open" → Item form opens with batch highlighted in Stock tab
- [ ] Pick image with Batch ID only QR (3 or 6 chars) → unresolvable message shown + fallback controls
