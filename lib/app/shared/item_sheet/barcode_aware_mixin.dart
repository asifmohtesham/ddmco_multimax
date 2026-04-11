// lib/app/shared/item_sheet/barcode_aware_mixin.dart

import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// Centralised barcode-scanning contract for item-level bottom sheets.
///
/// Provides:
///   • [initBarcodeListener]    — attach DataWedge worker (called by parent
///                                coordinator just before bottomSheet opens).
///   • [disposeBarcodeListener] — detach worker (called by parent after sheet
///                                closes).
///   • [onBarcodeScanned]       — unified DataWedge / camera entry point with
///                                300 ms debounce guard.
///   • [splitEanBatch]          — static EAN-8 prefix splitter.
///   • [isSheetScanning]        — Rx flag for UI spinner.
///
/// Routing contract:
///   • If batch field is empty → fill batch and call [validateBatch].
///   • If batch is already valid → delegate to [applyRackScan] (implementor).
///
/// Implementors must override [applyRackScan] (already present in SE sheet).
/// [onCameraBarcode] defaults to forwarding to [onBarcodeScanned]; override
/// only if camera and DataWedge need separate handling.
mixin BarcodeAwareMixin on ItemSheetControllerBase {
  DateTime? _lastScanTime;
  Worker?   _barcodeWorker;

  final isSheetScanning = false.obs;

  // ── Lifecycle hooks (called by parent coordinator) ────────────────────────

  void initBarcodeListener() {
    final dw = Get.find<DataWedgeService>();
    _barcodeWorker = ever(dw.scannedCode, (String code) {
      if (code.isNotEmpty) onBarcodeScanned(code);
    });
    log('[BarcodeAwareMixin] listener attached', name: 'BarcodeAwareMixin');
  }

  void disposeBarcodeListener() {
    _barcodeWorker?.dispose();
    _barcodeWorker = null;
    log('[BarcodeAwareMixin] listener disposed', name: 'BarcodeAwareMixin');
  }

  // ── Entry points ──────────────────────────────────────────────────────────

  /// Primary entry point for both DataWedge hardware scans and camera scans.
  Future<void> onBarcodeScanned(String raw) async {
    if (raw.isEmpty) return;

    // Debounce — hardware scanners can fire duplicate events within ms.
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!) <
            const Duration(milliseconds: 300)) {
      log('[BarcodeAwareMixin] debounced: $raw', name: 'BarcodeAwareMixin');
      return;
    }
    _lastScanTime = now;

    isSheetScanning.value = true;
    try {
      final (:ean, :batchId) = splitEanBatch(raw);
      // if (ean.isNotEmpty) currentScannedEan = ean; // base S1 field
      await _routeScan(raw, batchId);
    } finally {
      isSheetScanning.value = false;
    }
  }

  /// Camera (mobile_scanner) entry point.
  /// Override if camera and DataWedge need separate handling.
  Future<void> onCameraBarcode(String raw) async => onBarcodeScanned(raw);

  // ── EAN-8 prefix splitter ─────────────────────────────────────────────────

  /// Splits an EAN-8 prefixed barcode (e.g. "12345678-BATCH-001") into its
  /// EAN and batch components.
  ///
  /// Returns [ean: '', batchId: raw] when the raw code is not EAN-8 prefixed.
  static ({String ean, String batchId}) splitEanBatch(String raw) {
    final parts = raw.split('-');
    if (parts.length >= 2 &&
        parts[0].length == 8 &&
        int.tryParse(parts[0]) != null) {
      return (ean: parts[0], batchId: parts.sublist(1).join('-'));
    }
    return (ean: '', batchId: raw);
  }

  // ── Internal routing ──────────────────────────────────────────────────────

  Future<void> _routeScan(String raw, String batchId) async {
    if (!isBatchValid.value) {
      // Batch slot empty — fill and validate.
      batchController.text = batchId;
      await validateBatch(batchId);
    } else {
      // Batch already confirmed — assume rack scan.
      applyRackScan(raw);
    }
  }

  // ── Implementor contract ──────────────────────────────────────────────────

  /// Handle a rack barcode scan. Implementors route to source/target rack
  /// based on DocType rules.
  ///
  /// SE implementation: [StockEntryItemFormController.applyRackScan].
  void applyRackScan(String code);
}