# Camera Barcode Scanning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add camera-based barcode scanning — a full-screen modal overlay for form screens and a collapsible live-viewfinder panel for item sheets — both feeding the existing `ScanService` pipeline.

**Architecture:** Two new self-contained widgets (`CameraScanOverlay`, `CameraViewfinderPanel`) own distinct UX modes. `ItemSheetControllerBase` gains camera state + lifecycle, removing the `sheetScanController => null` stub in every item controller. `BarcodeInputWidget` adds a camera icon on mobile only; `GlobalItemFormSheet` adds a toggle button and the collapsible panel.

**Tech Stack:** Flutter, `mobile_scanner` (already in pubspec), GetX, `dart:io` for platform gating.

---

## File Map

| Action | Path |
|--------|------|
| Create | `lib/app/modules/global_widgets/camera_scan_overlay.dart` |
| Create | `lib/app/modules/global_widgets/camera_viewfinder_panel.dart` |
| Create | `test/widget/camera_scan_overlay_test.dart` |
| Create | `test/widget/camera_viewfinder_panel_test.dart` |
| Modify | `lib/app/shared/item_sheet/item_sheet_controller_base.dart` |
| Modify | `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` |
| Modify | `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart` |
| Modify | `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart` |
| Modify | `lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart` |
| Modify | `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart` |
| Modify | `lib/app/modules/global_widgets/barcode_input_widget.dart` |
| Modify | `lib/app/modules/global_widgets/global_item_form_sheet.dart` |
| Modify | `lib/app/shared/item_sheet/universal_item_form_sheet.dart` |

---

## Task 1: `CameraScanOverlay` widget

Full-screen modal for form screens. Owns its `MobileScannerController`, auto-dismisses on first scan, handles permission denied inline.

**Files:**
- Create: `lib/app/modules/global_widgets/camera_scan_overlay.dart`
- Create: `test/widget/camera_scan_overlay_test.dart`

- [ ] **Step 1.1 — Create `camera_scan_overlay.dart`**

```dart
// lib/app/modules/global_widgets/camera_scan_overlay.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScanOverlay extends StatefulWidget {
  const CameraScanOverlay._();

  /// Opens a full-screen camera scanner. Returns the scanned barcode string,
  /// or null if the user cancelled or permission was denied.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => const CameraScanOverlay._(),
    );
  }

  @override
  State<CameraScanOverlay> createState() => _CameraScanOverlayState();
}

class _CameraScanOverlayState extends State<CameraScanOverlay> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;
    _scanned = true;
    _controller.stop();
    if (mounted) Navigator.of(context).pop(barcode);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                return _PermissionDeniedView(
                  onClose: () => Navigator.of(context).pop(),
                );
              }
              return child ?? const SizedBox.shrink();
            },
          ),
          const _ScanWindowOverlay(),
          Positioned(
            top: 48,
            right: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          const Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              'Point at barcode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan-window overlay (dark mask + corner brackets) ─────────────────────────

class _ScanWindowOverlay extends StatelessWidget {
  const _ScanWindowOverlay();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScanWindowPainter());
}

class _ScanWindowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const windowSize   = 240.0;
    const cornerLength = 28.0;
    const cornerWidth  = 4.0;

    final cx     = size.width / 2;
    final cy     = size.height / 2;
    final left   = cx - windowSize / 2;
    final top    = cy - windowSize / 2;
    final right  = cx + windowSize / 2;
    final bottom = cy + windowSize / 2;

    final mask = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), mask);
    canvas.drawRect(
        Rect.fromLTWH(0, bottom, size.width, size.height - bottom), mask);
    canvas.drawRect(Rect.fromLTWH(0, top, left, windowSize), mask);
    canvas.drawRect(
        Rect.fromLTWH(right, top, size.width - right, windowSize), mask);

    final bracket = Paint()
      ..color      = Colors.white
      ..strokeWidth = cornerWidth
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.square;

    // Top-left
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), bracket);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), bracket);
    // Top-right
    canvas.drawLine(Offset(right - cornerLength, top), Offset(right, top), bracket);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLength), bracket);
    // Bottom-left
    canvas.drawLine(
        Offset(left, bottom - cornerLength), Offset(left, bottom), bracket);
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLength, bottom), bracket);
    // Bottom-right
    canvas.drawLine(
        Offset(right - cornerLength, bottom), Offset(right, bottom), bracket);
    canvas.drawLine(
        Offset(right, bottom), Offset(right, bottom - cornerLength), bracket);
  }

  @override
  bool shouldRepaint(_ScanWindowPainter _) => false;
}

// ── Permission-denied view ────────────────────────────────────────────────────

class _PermissionDeniedView extends StatelessWidget {
  final VoidCallback onClose;
  const _PermissionDeniedView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Camera permission required',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Allow camera access in Settings to scan barcodes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: onClose,
                child: const Text('Close',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 1.2 — Write widget test**

```dart
// test/widget/camera_scan_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/camera_scan_overlay.dart';

void main() {
  group('CameraScanOverlay', () {
    testWidgets('close button pops overlay with null result', (tester) async {
      String? result = 'not-set';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await CameraScanOverlay.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Close button is present in the overlay
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('"Point at barcode" label is visible in overlay', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => CameraScanOverlay.show(ctx),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Point at barcode'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 1.3 — Run test**

```
flutter test test/widget/camera_scan_overlay_test.dart -v
```

Expected: both tests PASS (camera hardware not required to test the overlay structure and cancel button).

- [ ] **Step 1.4 — Commit**

```
git add lib/app/modules/global_widgets/camera_scan_overlay.dart test/widget/camera_scan_overlay_test.dart
git commit -m "feat: add CameraScanOverlay full-screen modal widget"
```

---

## Task 2: `CameraViewfinderPanel` widget

Collapsible live-viewfinder panel for item sheets. Stateful for the green-flash animation; does NOT own the `MobileScannerController` (passed in from the base controller).

**Files:**
- Create: `lib/app/modules/global_widgets/camera_viewfinder_panel.dart`
- Create: `test/widget/camera_viewfinder_panel_test.dart`

- [ ] **Step 2.1 — Create `camera_viewfinder_panel.dart`**

```dart
// lib/app/modules/global_widgets/camera_viewfinder_panel.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Collapsible live-viewfinder panel for item sheets.
///
/// Does NOT own [controller] — the caller is responsible for its lifecycle.
/// Each successful scan triggers [onBarcode] and flashes the view green.
class CameraViewfinderPanel extends StatefulWidget {
  final MobileScannerController controller;
  final void Function(String barcode) onBarcode;

  const CameraViewfinderPanel({
    super.key,
    required this.controller,
    required this.onBarcode,
  });

  @override
  State<CameraViewfinderPanel> createState() => _CameraViewfinderPanelState();
}

class _CameraViewfinderPanelState extends State<CameraViewfinderPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;
  late final Animation<double>   _flashOpacity;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashOpacity = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _flash, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;
    _flash.forward(from: 0);
    widget.onBarcode(barcode);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _flashOpacity,
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (_flashOpacity.value > 0)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.green.withValues(alpha: _flashOpacity.value),
                  ),
                ),
            ],
          ),
          child: MobileScanner(
            controller: widget.controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                return const _InlinePermissionMessage();
              }
              return child ?? const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}

// ── Inline permission message (shown instead of viewfinder) ──────────────────

class _InlinePermissionMessage extends StatelessWidget {
  const _InlinePermissionMessage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt, color: Colors.white54, size: 40),
            SizedBox(height: 8),
            Text(
              'Camera permission required',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2.2 — Write widget test**

```dart
// test/widget/camera_viewfinder_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/modules/global_widgets/camera_viewfinder_panel.dart';

void main() {
  group('CameraViewfinderPanel', () {
    testWidgets('renders with fixed 200px height', (tester) async {
      final controller = MobileScannerController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraViewfinderPanel(
              controller: controller,
              onBarcode: (_) {},
            ),
          ),
        ),
      );

      final box = tester.renderObject<RenderBox>(
        find.byType(CameraViewfinderPanel),
      );
      expect(box.size.height, equals(200.0));
    });
  });
}
```

- [ ] **Step 2.3 — Run test**

```
flutter test test/widget/camera_viewfinder_panel_test.dart -v
```

Expected: PASS.

- [ ] **Step 2.4 — Commit**

```
git add lib/app/modules/global_widgets/camera_viewfinder_panel.dart test/widget/camera_viewfinder_panel_test.dart
git commit -m "feat: add CameraViewfinderPanel collapsible item-sheet widget"
```

---

## Task 3: `ItemSheetControllerBase` — camera fields and lifecycle

Add `isCameraExpanded`, `toggleCamera()`, lazy `MobileScannerController`, and a default `onCameraBarcode()` no-op. Remove the abstract `sheetScanController` getter and replace with a concrete nullable field.

**Files:**
- Modify: `lib/app/shared/item_sheet/item_sheet_controller_base.dart`

- [ ] **Step 3.1 — Add imports at the top of `item_sheet_controller_base.dart`**

The file currently imports:
```dart
import 'package:mobile_scanner/mobile_scanner.dart';
```
Add `dart:io` and `flutter/foundation.dart` beside the existing imports:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
```

- [ ] **Step 3.2 — Replace the abstract `sheetScanController` getter with a concrete field + new camera members**

Find this line (around line 302):
```dart
  /// Mobile scanner controller backing the scan footer.
  MobileScannerController? get sheetScanController;
```

Replace with:
```dart
  // ── Camera state ──────────────────────────────────────────────────────────

  /// Whether the camera viewfinder panel is currently expanded.
  final isCameraExpanded = false.obs;

  MobileScannerController? _sheetScanController;

  /// The live scanner controller. Non-null on Android/iOS from [onInit] onward
  /// (`autoStart: false` so the camera is off until the panel mounts).
  /// Always null on desktop/web. Disposed in [disposeControllers].
  MobileScannerController? get sheetScanController => _sheetScanController;

  /// True when running on Android or iOS (camera hardware available).
  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Expand or collapse the camera viewfinder panel.
  /// No-op on desktop / web.
  void toggleCamera() {
    if (!isMobile) return;
    isCameraExpanded.value = !isCameraExpanded.value;
  }

  /// Camera-scan entry point.
  ///
  /// Called by [GlobalItemFormSheet] when [CameraViewfinderPanel] detects a
  /// barcode.  Base implementation is a no-op; [BarcodeAwareMixin] overrides
  /// this to forward through [onBarcodeScanned] → [handleScan].
  Future<void> onCameraBarcode(String raw) async {}
```

- [ ] **Step 3.3 — Eagerly create the scanner controller in `onInit`**

Find the existing `onInit` override in `ItemSheetControllerBase` (it currently only wires the `docStatus` → `isQtyReadOnly` worker). Add the eager controller creation **before** the `ever(...)` call:

```dart
  @override
  void onInit() {
    super.onInit();
    // Create the scanner controller upfront on mobile (autoStart: false keeps
    // the camera off until the CameraViewfinderPanel widget mounts).
    // This ensures sheetScanController is never null at widget-build time on
    // mobile, so GlobalItemFormSheet renders the camera toggle immediately.
    if (isMobile) {
      _sheetScanController = MobileScannerController(autoStart: false);
    }
    // Lock / unlock the qty field based on docstatus.
    ever(docStatus, (_) {
      _isQtyReadOnly.value = docStatus.value == 1;
    });
  }
```

- [ ] **Step 3.4 — Add camera controller disposal to `disposeControllers()`**

Find the line inside `disposeControllers()` where `_controllersDisposed = true` is set, then locate the `addPostFrameCallback` block that disposes TECs. Add scanner disposal **before** the post-frame callback (camera controller is not a TEC — no animation frame dependency):

```dart
  void disposeControllers() {
    if (_controllersDisposed) return;
    _controllersDisposed = true;

    removeSheetListeners();

    // Dispose camera controller immediately (not a TEC; no frame dependency).
    _sheetScanController?.dispose();
    _sheetScanController = null;

    final textControllers = <TextEditingController>[ ... // unchanged
```

- [ ] **Step 3.5 — Run `flutter analyze` to verify no errors**

```
flutter analyze lib/app/shared/item_sheet/item_sheet_controller_base.dart
```

Expected: no issues.

- [ ] **Step 3.6 — Commit**

```
git add lib/app/shared/item_sheet/item_sheet_controller_base.dart
git commit -m "feat: add camera state and lifecycle to ItemSheetControllerBase"
```

---

## Task 4: Item controllers — remove null `sheetScanController` stub

Five item controllers each declare `MobileScannerController? get sheetScanController => null;`. The base class now provides the real concrete getter, so these stubs and their imports must be removed.

**Files (modify all five):**
- `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`
- `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`
- `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`
- `lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart`
- `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`

- [ ] **Step 4.1 — In each of the five files, remove the `mobile_scanner` import**

Find and delete the line:
```dart
import 'package:mobile_scanner/mobile_scanner.dart';
```

- [ ] **Step 4.2 — In each of the five files, remove the stub getter**

Find and delete:
```dart
  MobileScannerController? get sheetScanController => null;
```

- [ ] **Step 4.3 — Run `flutter analyze`**

```
flutter analyze lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart
```

Expected: no issues.

- [ ] **Step 4.4 — Commit**

```
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart
git commit -m "refactor: remove sheetScanController null stubs from item controllers"
```

---

## Task 5: `BarcodeInputWidget` — add camera button (mobile only)

Add a camera icon button to the right of the send button in the suffix slot. On mobile the suffix becomes a two-button row `[camera | send]`. On desktop/web the suffix is unchanged (send only).

**Files:**
- Modify: `lib/app/modules/global_widgets/barcode_input_widget.dart`

- [ ] **Step 5.1 — Add imports**

At the top of `barcode_input_widget.dart`, add:
```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multimax/app/modules/global_widgets/camera_scan_overlay.dart';
```

Remove the existing `DataWedgeService` import if it is no longer used (check first — the widget comment says it no longer attaches a worker):
```dart
// remove if present and unused:
import 'package:multimax/app/data/services/data_wedge_service.dart';
```

- [ ] **Step 5.2 — Extract the send button to a local variable and add `_buildSuffixIcon`**

In `_BarcodeInputWidgetState.build()`, the current default branch of `suffixIcon` is:
```dart
IconButton(
  icon: Icon(
      widget.isEmbedded
          ? Icons.arrow_forward
          : Icons.send,
      color: widget.isEmbedded
          ? primaryColor
          : null),
  onPressed: () {
    if (_textController.text
        .trim()
        .isNotEmpty) {
      widget.onScan(
          _textController.text.trim());
    }
  },
)
```

Replace the entire `suffixIcon: widget.isLoading ? ... : (...)` expression with a call to a new private method `_buildSuffixIcon(context, primaryColor)`:

```dart
suffixIcon: _buildSuffixIcon(context, primaryColor),
```

Then add this method to `_BarcodeInputWidgetState`:

```dart
Widget _buildSuffixIcon(BuildContext context, Color primaryColor) {
  if (widget.isLoading) {
    return const Padding(
      padding: EdgeInsets.all(12.0),
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
  if (widget.isSuccess) {
    return const Icon(Icons.check_circle, color: Colors.green);
  }
  if (widget.hasError) {
    return const Icon(Icons.error, color: Colors.red);
  }

  final sendButton = IconButton(
    icon: Icon(
      widget.isEmbedded ? Icons.arrow_forward : Icons.send,
      color: widget.isEmbedded ? primaryColor : null,
    ),
    onPressed: () {
      if (_textController.text.trim().isNotEmpty) {
        widget.onScan(_textController.text.trim());
      }
    },
  );

  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (!isMobile) return sendButton;

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: Icon(Icons.camera_alt_outlined, color: primaryColor),
        tooltip: 'Scan with camera',
        onPressed: () async {
          final result = await CameraScanOverlay.show(context);
          if (result != null && result.isNotEmpty) {
            widget.onScan(result);
          }
        },
      ),
      sendButton,
    ],
  );
}
```

- [ ] **Step 5.3 — Run `flutter analyze`**

```
flutter analyze lib/app/modules/global_widgets/barcode_input_widget.dart
```

Expected: no issues.

- [ ] **Step 5.4 — Commit**

```
git add lib/app/modules/global_widgets/barcode_input_widget.dart
git commit -m "feat: add camera scan button to BarcodeInputWidget on mobile"
```

---

## Task 6: `GlobalItemFormSheet` — camera panel params and rendering

Add four new optional params (`onCameraScan`, `isCameraExpanded`, `onToggleCamera`, `mobileScanController`), render a camera toggle icon button left of `BarcodeInputWidget`, and show `CameraViewfinderPanel` above the scan footer via `AnimatedSize`. Uncomment the scan bar in both layout branches.

**Files:**
- Modify: `lib/app/modules/global_widgets/global_item_form_sheet.dart`

- [ ] **Step 6.1 — Add imports**

Add at top of `global_item_form_sheet.dart`:
```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:multimax/app/modules/global_widgets/camera_viewfinder_panel.dart';
```

- [ ] **Step 6.2 — Add four new fields to `GlobalItemFormSheet`**

In the `// ── Scan footer` section, add after the existing three scan fields:
```dart
  // ── Camera panel ───────────────────────────────────────────────────────────
  final void Function(String)? onCameraScan;
  final RxBool? isCameraExpanded;
  final VoidCallback? onToggleCamera;
  final MobileScannerController? mobileScanController;
```

- [ ] **Step 6.3 — Add new params to the constructor**

In the constructor parameter list, after `this.isScanning = false,`, add:
```dart
    this.onCameraScan,
    this.isCameraExpanded,
    this.onToggleCamera,
    this.mobileScanController,
```

- [ ] **Step 6.4 — Replace the `scanBar` build block**

Find (around line 503):
```dart
    final scanBar = onScan != null
        ? Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
            child: BarcodeInputWidget(
              onScan: onScan!,
              controller: scanController,
              isLoading: isScanning,
              hintText: 'Scan Rack / Batch / Item',
              isEmbedded: true,
            ),
          )
        : null;
```

Replace with:
```dart
    final bool _isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final bool _showScanFooter =
        onScan != null || (onCameraScan != null && _isMobile);

    final scanBar = _showScanFooter
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Camera viewfinder panel (expandable) ──────────────────────
              if (onCameraScan != null &&
                  isCameraExpanded != null &&
                  mobileScanController != null &&
                  _isMobile)
                Obx(
                  () => AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: isCameraExpanded!.value
                        ? CameraViewfinderPanel(
                            controller: mobileScanController!,
                            onBarcode: onCameraScan!,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              // ── Scan footer row ────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border(
                      top: BorderSide(color: colorScheme.outlineVariant)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(8, 12, 16, bottomPadding + 12),
                child: Row(
                  children: [
                    if (onCameraScan != null &&
                        isCameraExpanded != null &&
                        onToggleCamera != null &&
                        _isMobile)
                      Obx(
                        () => IconButton(
                          icon: Icon(
                            isCameraExpanded!.value
                                ? Icons.camera_alt
                                : Icons.camera_alt_outlined,
                            color: colorScheme.primary,
                          ),
                          tooltip: isCameraExpanded!.value
                              ? 'Close camera'
                              : 'Open camera',
                          onPressed: onToggleCamera,
                        ),
                      ),
                    Expanded(
                      child: BarcodeInputWidget(
                        onScan: onScan ?? onCameraScan!,
                        controller: scanController,
                        isLoading: isScanning,
                        hintText: 'Scan Rack / Batch / Item',
                        isEmbedded: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        : null;
```

- [ ] **Step 6.5 — Uncomment the scan bar in both layout branches**

Find (two places):
```dart
            // if (scanBar != null) scanBar,
```

Replace both with:
```dart
            if (scanBar != null) scanBar,
```

- [ ] **Step 6.6 — Run `flutter analyze`**

```
flutter analyze lib/app/modules/global_widgets/global_item_form_sheet.dart
```

Expected: no issues.

- [ ] **Step 6.7 — Commit**

```
git add lib/app/modules/global_widgets/global_item_form_sheet.dart
git commit -m "feat: add camera viewfinder panel and toggle to GlobalItemFormSheet"
```

---

## Task 7: `UniversalItemFormSheet` — forward camera props

Forward the four new camera params from `ItemSheetControllerBase` to `GlobalItemFormSheet`.

**Files:**
- Modify: `lib/app/shared/item_sheet/universal_item_form_sheet.dart`

- [ ] **Step 7.1 — Add the four new params to the `GlobalItemFormSheet(...)` call**

Inside `UniversalItemFormSheet.build()`, the existing `GlobalItemFormSheet(...)` call ends with the scan footer params:
```dart
        // ── Scan footer ─────────────────────────────────────────────────
        onScan:         onScan,
        // MobileScannerController is not a TextEditingController; pass null.
        // Sheets that embed a live camera scanner wire it inside customFields.
        scanController: null,
        isScanning:     controller.isScanning.value,
```

Replace with:
```dart
        // ── Scan footer ─────────────────────────────────────────────────
        onScan:             onScan,
        scanController:     null,
        isScanning:         controller.isScanning.value,

        // ── Camera panel ────────────────────────────────────────────────
        onCameraScan:       (raw) => controller.onCameraBarcode(raw),
        isCameraExpanded:   controller.isCameraExpanded,
        onToggleCamera:     controller.toggleCamera,
        mobileScanController: controller.sheetScanController,
```

- [ ] **Step 7.2 — Run `flutter analyze` on the full lib directory**

```
flutter analyze lib/
```

Expected: no issues (zero errors, zero warnings).

- [ ] **Step 7.3 — Run all tests**

```
flutter test
```

Expected: all tests pass.

- [ ] **Step 7.4 — Commit**

```
git add lib/app/shared/item_sheet/universal_item_form_sheet.dart
git commit -m "feat: wire camera props from ItemSheetControllerBase to GlobalItemFormSheet"
```

---

## Post-implementation: device smoke test

These steps require a physical Android device. Not automatable in CI.

- [ ] **Form screen camera (e.g. Delivery Note form screen):**
  1. Open a DN form.
  2. Tap the camera icon in the scan bar.
  3. Point at a barcode — overlay auto-dismisses and the scan is processed.
  4. Tap `×` without scanning — overlay dismisses, nothing happens.

- [ ] **Item sheet camera (e.g. DN item-add sheet):**
  1. Open a DN item sheet.
  2. Tap the camera toggle icon in the footer — viewfinder panel expands.
  3. Point at a batch barcode — green flash, batch field fills, panel stays open.
  4. Tap toggle again — panel collapses.
  5. Close the sheet — confirm no crash (camera controller disposed cleanly).

- [ ] **Desktop / web smoke test:**
  1. Run on desktop (`flutter run -d windows` or web).
  2. Confirm no camera icon appears in `BarcodeInputWidget` or `GlobalItemFormSheet`.
