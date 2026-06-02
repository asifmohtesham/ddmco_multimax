import 'dart:developer';
import 'package:multimax/app/shared/barcode_listener_mixin.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

/// Item-sheet–specific barcode routing built on top of [BarcodeListenerMixin].
///
/// ## Routing priority (evaluated in order)
///
/// 1. **Rack pattern** — if [isRackBarcode] matches, route to [applyRackScan]
///    immediately, regardless of whether batch has been validated.  The
///    implementor's [applyRackScan] is responsible for API confirmation.
///
/// 2. **Batch gate** — if [isBatchValid] is false, treat as batch: write
///    [batchValue] to [batchController] and call [validateBatch].
///
/// 3. **Post-batch rack** — if [isBatchValid] is true and no rack pattern
///    matched above, route to [applyRackScan].
///
/// ## Rack barcode pattern
/// Rack names follow the company asset-code convention:
///   `<company>-<type>-<location>-<shelf>`  e.g.  `KA-WH-DXB1-101A`
/// [isRackBarcode] detects this locally; [applyRackScan] then confirms
/// via an API call.
///
/// ## EAN-8 batch format
/// Current-format batch barcodes carry an 8-digit numeric EAN-8 prefix:
///   `20003609-ESU`
/// [BarcodeListenerMixin.splitEanBatch] detects this.  The full raw string
/// is passed as [batchValue] so the complete Batch No is written to the
/// field.
///
/// Implementors must override [applyRackScan].
/// [onCameraBarcode] forwards to [onBarcodeScanned] by default.
mixin BarcodeAwareMixin on ItemSheetControllerBase, BarcodeListenerMixin {

  // ── BarcodeListenerMixin contract ─────────────────────────────────────────

  @override
  Future<void> handleScan(String raw) async {
    // Check rack pattern on the unmodified raw string, BEFORE splitEanBatch
    // strips the company prefix (e.g. "KA-" from "KA-WH-DXB1-BLOCK 1").
    if (BarcodeAwareMixin.isRackBarcode(raw)) {
      log('[BarcodeAwareMixin] rack pattern matched: $raw', name: 'ItemSheet');
      applyRackScan(raw);
      return;
    }

    final (:ean, :batchId) = BarcodeListenerMixin.splitEanBatch(raw);
    // When ean is present, raw is already the full Batch No (e.g. '{EAN}-{Batch ID}').
    // When ean is absent, pass batchId for subclass handleScan overrides to process.
    await _routeScan(raw, ean.isNotEmpty ? raw : batchId);
  }

  // ── Camera entry point ────────────────────────────────────────────────────

  /// Camera (mobile_scanner) entry point.
  /// Override only if camera and DataWedge need separate handling.
  Future<void> onCameraBarcode(String raw) async => onBarcodeScanned(raw);

  // ── Rack barcode pattern ───────────────────────────────────────────────────

  /// Returns true when [raw] matches the company rack asset-code convention:
  ///   `<company>-<type>-<location>-<shelf>`
  ///   e.g. `KA-WH-DXB1-101A`
  ///
  /// Rules:
  ///   • Exactly 4 hyphen-delimited parts.
  ///   • parts[0] is 2-3 alphabetic characters (company prefix — NOT numeric,
  ///     so it is never confused with an EAN-8 prefix).
  ///   • parts[1] is 2-4 uppercase letters (location type: WH, POS, …).
  ///   • parts[2] starts with 2-3 letters followed by 1+ digits (DXB1, DXB2, …).
  ///   • parts[3] is at least 3 characters (shelf ID: 101A, 202B, …).
  ///
  /// This check is purely local — no API call.  [_routeScan] then passes the
  /// candidate to [validateRack] for authoritative API confirmation.
  static bool isRackBarcode(String raw) {
    final parts = raw.split('-');
    if (parts.length < 4) return false;          // ← was == 4, now >= 4

    final companyOk  = RegExp(r'^[A-Za-z]{2,3}$').hasMatch(parts[0]);
    final typeOk     = RegExp(r'^[A-Z]{2,4}$').hasMatch(parts[1]);
    final locationOk = RegExp(r'^[A-Za-z]{2,3}\d+$').hasMatch(parts[2]);
    // Shelf = everything after the third hyphen — may contain spaces or hyphens
    final shelf      = parts.sublist(3).join('-');
    final shelfOk    = shelf.trim().isNotEmpty;

    return companyOk && typeOk && locationOk && shelfOk;
  }

  // ── Internal routing ──────────────────────────────────────────────────────

  Future<void> _routeScan(String raw, String batchValue) async {
    // ── Rack-first: check pattern before the batch-valid gate ─────────────
    // A rack barcode (KA-WH-DXB1-101A) must be routed to applyRackScan
    // regardless of whether batch has been validated yet.
    if (isRackBarcode(raw)) {
      log('[BarcodeAwareMixin] rack pattern matched: $raw', name: 'ItemSheet');
      applyRackScan(raw);
      return;
    }

    // ── Batch-first routing ────────────────────────────────────────────────
    if (!isBatchValid.value) {
      batchController.text = batchValue;
      await validateBatch(batchValue);
    } else {
      applyRackScan(raw);
    }
  }

  // ── Implementor contract ──────────────────────────────────────────────────

  /// Handle a confirmed rack barcode scan.
  ///
  /// Implementors MUST:
  ///   1. Write [code] to the appropriate rack [TextEditingController].
  ///   2. Call [validateRack] (or equivalent) for API confirmation.
  void applyRackScan(String code);
}