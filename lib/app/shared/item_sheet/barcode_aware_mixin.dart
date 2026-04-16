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
///
/// fix(batch-scan): _routeScan now uses raw as batchValue when ean is
///   non-empty, so that a current-format scan ('20003609-ESU') sets the
///   full Batch No instead of the stripped Batch ID ('ESU').
mixin BarcodeAwareMixin on ItemSheetControllerBase, BarcodeListenerMixin {

  // ── BarcodeListenerMixin contract ─────────────────────────────────────────

  @override
  Future<void> handleScan(String raw) async {
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);
    // When ean is present, raw is already the full Batch No (e.g. '20003609-ESU').
    // When ean is absent, pass batchId for subclass handleScan overrides to process.
    await _routeScan(raw, ean.isNotEmpty ? raw : batchId);
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