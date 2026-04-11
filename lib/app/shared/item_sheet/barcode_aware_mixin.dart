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

  @override
  Future<void> handleScan(String raw) async {
    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);
    // ignore: unused_local_variable
    final _ = ean; // EAN may be used by subclasses for item-code resolution
    await _routeScan(raw, batchId);
  }

  // ── Camera entry point ────────────────────────────────────────────────────

  /// Camera (mobile_scanner) entry point.
  /// Override only if camera and DataWedge need separate handling.
  Future<void> onCameraBarcode(String raw) async => onBarcodeScanned(raw);

  // ── Internal routing ──────────────────────────────────────────────────────

  Future<void> _routeScan(String raw, String batchId) async {
    if (!isBatchValid.value) {
      batchController.text = batchId;
      await validateBatch(batchId);
    } else {
      applyRackScan(raw);
    }
  }

  // ── Implementor contract ──────────────────────────────────────────────────

  /// Handle a rack barcode scan. Route to source/target rack per DocType rules.
  void applyRackScan(String code);
}