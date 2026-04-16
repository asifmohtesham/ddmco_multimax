import 'dart:developer';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// Item-sheet–specific barcode routing built on top of [BarcodeListenerMixin].
///
/// Adds the batch-first / rack-fallback routing contract on top of the
/// DocType-agnostic [BarcodeListenerMixin].
///
/// Implementors must override [applyRackScan].
/// [onCameraBarcode] forwards to [onBarcodeScanned] by default.
mixin BarcodeAwareMixin on ItemSheetControllerBase, BarcodeListenerMixin {

  // ── BarcodeListenerMixin contract ─────────────────────────────────────────

  // ── BarcodeAwareMixin: handleScan override for deprecated batch labels ─────
  /// Extends the base routing with SHIPMENT-* label support.
  /// Base class handles: current format '20003609-ESU' (ean present → raw used as-is).
  /// This override handles: 'SHIPMENT-ESU', 'SHIPMENT-24-ESU', 'SHIPMENT-24-ESU-1'
  ///   by extracting the Batch ID and prepending the stored item EAN8.
  @override
  Future<void> handleScan(String raw) async {
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);

    if (ean.isNotEmpty) {
      // Current format: raw is already the correct full Batch No.
      // Delegate to base — it will use raw as batchValue.
      await super.handleScan(raw);
      return;
    }

    // Deprecated or plain Batch ID: extract and reassemble.
    final extractedId = _extractBatchId(raw);
    final fullBatchNo = _itemEan8.isNotEmpty
        ? '$_itemEan8-$extractedId'
        : extractedId; // fallback: no EAN8 context available

    batchController.text = fullBatchNo;
    await validateBatch(fullBatchNo);
  }

  /// Splits on '-', discards the literal token 'SHIPMENT',
  /// discards any token shorter than 3 characters.
  /// Returns the first surviving token, or [raw] if none survive.
  String _extractBatchId(String raw) {
    final candidates = raw.split('-').where((p) =>
    p.toUpperCase() != 'SHIPMENT' &&
        p.length >= 3
    ).toList();
    return candidates.isNotEmpty ? candidates.first : raw;
  }

  // ── Camera entry point ────────────────────────────────────────────────────

  /// Camera (mobile_scanner) entry point.
  /// Override only if camera and DataWedge need separate handling.
  Future<void> onCameraBarcode(String raw) async => onBarcodeScanned(raw);

  // ── Internal routing ──────────────────────────────────────────────────────

  Future<void> _routeScan(String raw, String batchValue) async {
    if (!isBatchValid.value) {
      batchController.text = batchValue;
      await validateBatch(batchValue);
    } else {
      applyRackScan(raw);
    }
  }

  // ── Implementor contract ──────────────────────────────────────────────────

  /// Handle a rack barcode scan. Route to source/target rack per DocType rules.
  void applyRackScan(String code);
}