import 'dart:developer';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

/// Thin, DocType-agnostic mixin that provides DataWedge worker lifecycle
/// and a 300 ms debounce guard.
///
/// No `on` constraint — can be applied to ANY [GetxController] subclass.
///
/// Implementors must override [onBarcodeScanned] to handle the routed scan.
///
/// ### Lifecycle
/// Call [initBarcodeListener] just before opening a sheet/screen that needs
/// barcode input, and [disposeBarcodeListener] immediately after it closes.
/// This ensures the DataWedge worker is active only while the UI is visible.
///
/// ### Usage
/// ```dart
/// class MyController extends GetxController with BarcodeListenerMixin {
///   @override
///   Future<void> onBarcodeScanned(String raw) async {
///     // handle the barcode
///   }
/// }
/// ```
mixin BarcodeListenerMixin on GetxController {
  DateTime? _lastScanTime;
  Worker?   _barcodeWorker;

  /// Reactive flag — set to `true` while [onBarcodeScanned] is executing.
  /// Bind to UI spinners or read-only guards.
  final isSheetScanning = false.obs;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Attach the DataWedge [ever] worker.
  /// Call this just before `showModalBottomSheet(...)` / `showReportFilterSheet(...)`.
  void initBarcodeListener() {
    final dw = Get.find<DataWedgeService>();
    _barcodeWorker = ever(dw.scannedCode, (String code) {
      if (code.isNotEmpty) onBarcodeScanned(code);
    });
    log('[BarcodeListenerMixin] listener attached', name: 'BarcodeListenerMixin');
  }

  /// Detach the DataWedge worker.
  /// Call this in the `.then((_) { ... })` callback after the sheet Future resolves.
  void disposeBarcodeListener() {
    _barcodeWorker?.dispose();
    _barcodeWorker = null;
    log('[BarcodeListenerMixin] listener disposed', name: 'BarcodeListenerMixin');
  }

  // ── Entry point ───────────────────────────────────────────────────────────

  /// Called for every non-empty scan that passes the debounce guard.
  /// Implementors handle routing to the correct field.
  Future<void> onBarcodeScanned(String raw) async {
    if (raw.isEmpty) return;

    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(milliseconds: 300)) {
      log('[BarcodeListenerMixin] debounced: $raw', name: 'BarcodeListenerMixin');
      return;
    }
    _lastScanTime = now;

    isSheetScanning.value = true;
    try {
      await handleScan(raw);
    } finally {
      isSheetScanning.value = false;
    }
  }

  /// Override this in the implementing controller to handle the routed scan.
  Future<void> handleScan(String raw);

  // ── EAN-8 prefix splitter (static utility — shared) ───────────────────────

  /// Splits `"12345678-BATCH-001"` → `(ean: "12345678", batchId: "BATCH-001")`.
  /// Returns `(ean: '', batchId: raw)` when the raw code is not EAN-8 prefixed.
  static ({String ean, String batchId}) splitEanBatch(String raw) {
    final parts = raw.split('-');
    if (parts.length >= 2 &&
        parts[0].length == 8 &&
        int.tryParse(parts[0]) != null) {
      return (ean: parts[0], batchId: parts.sublist(1).join('-'));
    }
    return (ean: '', batchId: raw);
  }
}