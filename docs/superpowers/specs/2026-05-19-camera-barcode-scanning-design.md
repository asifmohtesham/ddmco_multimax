# Camera Barcode Scanning — Design Spec

**Date:** 2026-05-19
**Status:** Approved

---

## Overview

Add camera-based barcode scanning as a third input path alongside the existing
DataWedge hardware scanner and manual text entry. The feature has two distinct
UX modes depending on context:

- **Form screens** (Delivery Note, PO, MR, etc.): a camera icon in
  `BarcodeInputWidget` opens a full-screen modal overlay that auto-dismisses on
  the first successful scan.
- **Item sheets** (all DocType item-add/edit sheets): an expandable live
  viewfinder panel slides in above the existing scan footer, staying open until
  the user collapses it or closes the sheet.

Both paths feed into the existing `ScanService.processScan()` pipeline unchanged.
Platform gate: camera UI is suppressed on desktop/web
(`Platform.isAndroid || Platform.isIOS`).

---

## New Files

| File | Purpose |
|---|---|
| `lib/app/modules/global_widgets/camera_scan_overlay.dart` | Full-screen modal for form screens |
| `lib/app/modules/global_widgets/camera_viewfinder_panel.dart` | Collapsible animated panel for item sheets |

---

## Modified Files

| File | Change |
|---|---|
| `lib/app/modules/global_widgets/barcode_input_widget.dart` | Add camera icon button (mobile only); opens `CameraScanOverlay` |
| `lib/app/modules/global_widgets/global_item_form_sheet.dart` | Accept `onCameraScan` callback + `isCameraExpanded` Rx; render `CameraViewfinderPanel` above scan footer |
| `lib/app/shared/item_sheet/universal_item_form_sheet.dart` | Forward camera props from controller to `GlobalItemFormSheet` |
| `lib/app/shared/item_sheet/item_sheet_controller_base.dart` | Add `isCameraExpanded` RxBool, `toggleCamera()`, concrete `sheetScanController` field, lazy controller init |
| All item-sheet controllers (SE, DN, PR, PO, PS) | Remove `sheetScanController => null`; inherit concrete implementation from base |

---

## Data Flow

### Form-screen path

```
User taps camera icon in BarcodeInputWidget
  → CameraScanOverlay.show(context) → full-screen dialog
  → MobileScannerController starts camera stream (owned by overlay State)
  → First BarcodeCapture event → controller.stop() → Navigator.pop(barcode)
  → BarcodeInputWidget calls onScan(barcode)
  → BarcodeScanMixin.scanBarcode() → ScanService.processScan() (unchanged)
```

### Item-sheet path

```
User taps camera icon in GlobalItemFormSheet footer
  → controller.toggleCamera() flips isCameraExpanded
  → CameraViewfinderPanel animates in (AnimatedSize + ClipRect)
  → MobileScannerController (owned by ItemSheetControllerBase) starts
  → BarcodeCapture → controller.onCameraBarcode(raw)
  → BarcodeAwareMixin.onCameraBarcode() → onBarcodeScanned() → handleScan()
  → Existing rack/batch routing runs unchanged
  → Green flash confirms scan; panel stays open
  → User collapses manually or sheet closes
```

---

## Component Details

### `CameraScanOverlay`

- Shown via `CameraScanOverlay.show(BuildContext)` returning `Future<String?>`
- Full-screen `Dialog`, dark scrim background
- `MobileScanner` widget fills frame; decorative corner-bracket overlay
- Top-right `×` button to cancel (returns `null`)
- "Point at barcode" label at bottom
- On permission denied: inline message + "Open Settings" button
- `MobileScannerController` created in `initState`, disposed in `dispose`

### `CameraViewfinderPanel`

- Stateless widget; receives `MobileScannerController` and `onBarcode` callback
- Wraps `MobileScanner` in `AnimatedSize` + `ClipRect` for expand/collapse
- Fixed `200px` height when expanded
- Small collapse handle bar at top
- Green flash (`AnimationController`) on each successful scan
- On permission denied: shows inline message in place of viewfinder
- Does NOT own or dispose the controller (owned by `ItemSheetControllerBase`)

### `BarcodeInputWidget` changes

- Camera icon added as a second suffix button (mobile only)
- Suffix becomes a `Row` of `[camera_alt_outlined | send/arrow]`
- Camera button calls `CameraScanOverlay.show(context)` then calls `onScan(result)` if result is non-null
- No state change to the existing send button

### `GlobalItemFormSheet` changes

- New optional params: `onCameraScan`, `isCameraExpanded` (RxBool), `scanController`
- Camera icon button added left of `BarcodeInputWidget` in the scan footer row
- `CameraViewfinderPanel` inserted above the scan footer, visible when `isCameraExpanded.value` is true

### `ItemSheetControllerBase` changes

- `isCameraExpanded` RxBool field (default false)
- `toggleCamera()` method — flips `isCameraExpanded`, lazily creates
  `MobileScannerController` on first expand, stops it on collapse
- `sheetScanController` promoted from abstract getter returning null to a
  concrete nullable field backed by the lazily-created controller
- Controller stopped (not disposed) on collapse; disposed in `disposeControllers`

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Camera permission denied | Inline message + "Open Settings"; no crash |
| `BarcodeCapture` with no barcodes | Silently ignored; camera keeps running |
| Unrecognised barcode format | Passes through to `ScanService`; existing `GlobalSnackbar.error` fires |
| Sheet closed while camera open | `disposeControllers` stops + disposes `MobileScannerController` |
| Multiple barcodes in one frame | First barcode in the capture list wins |

---

## Out of Scope

- Torch / flashlight toggle
- QR code-specific handling (all formats `mobile_scanner` supports will pass through)
- Continuous scan mode for form screens (auto-dismiss is the only mode)

---

## Testing

- `CameraScanOverlay` and `CameraViewfinderPanel`: widget tests with a mock
  `MobileScannerController`
- Camera → `onScan` → `BarcodeScanMixin` path: integration-testable with a fake
  barcode string injected directly into `onScan`
- No changes to `ScanService` or `DataWedgeService` — existing scan tests
  are unaffected
