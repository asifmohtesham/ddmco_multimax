import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'item_sheet_controller_base.dart';
import 'scan_scope.dart';

/// Centralises [DataWedgeService] + [ScanService] scan routing for all
/// [ItemSheetControllerBase] subclasses.
///
/// ## Applying the mixin
///
/// ```dart
/// class MyItemFormController extends ItemSheetControllerBase
///     with BarcodeAwareMixin {
///   @override
///   void onInit() {
///     super.onInit();
///     initBarcodeListeners();
///   }
/// }
/// ```
///
/// ## Two scan sources
///
/// | Source | Service | Use-case |
/// |---|---|---|
/// | DataWedge | [DataWedgeService] | Zebra/Honeywell hardware trigger |
/// | Camera | [ScanService] | In-app MobileScanner camera scan |
///
/// Both streams are merged into the same [_onRaw] dispatch handler so
/// field-routing, deduplication, and `isScanning` pulse are source-agnostic.
///
/// ## Routing priority
///
/// 1. **Focused field** — the [FocusNode] with keyboard focus wins.
/// 2. **First empty field** — scanned in [activeScanScopes] order.
/// 3. **Fallback override** — overwrites [activeScanScopes.first] when all
///    fields are populated.
///
/// ## Scan suppression
///
/// Override [isScanEnabled] → `false` to silence all scans for a DocType
/// (e.g. Job Card, Work Order item sheets where scanning is not applicable).
///
/// ## Dual-rack support
///
/// Override [_targetRackController] and [_targetRackFocusNode] in any
/// controller that exposes a target-rack field (e.g. [StockEntryItemFormController]).
///
/// ## Deduplication
///
/// DataWedge hardware scanners commonly fire 2–3 duplicate events per
/// physical trigger pull within a 300 ms window. The mixin discards
/// identical values arriving within that window — applies equally to
/// both DataWedge and ScanService events.
mixin BarcodeAwareMixin on ItemSheetControllerBase {
  StreamSubscription<String>? _dwSub;
  StreamSubscription<String>? _scanSub;

  String? _lastRaw;
  DateTime? _lastTime;

  // ── Public hooks ─────────────────────────────────────────────────────

  /// Return `false` to suppress all scan events for this DocType.
  bool get isScanEnabled => true;

  /// Ordered list of [ScanScope]s this controller participates in.
  ///
  /// Override to exclude scopes that don't apply to your DocType:
  /// ```dart
  /// // Delivery Note — no rack fields
  /// @override
  /// List<ScanScope> get activeScanScopes =>
  ///     const [ScanScope.itemBarcode, ScanScope.batchNo];
  /// ```
  List<ScanScope> get activeScanScopes => const [
        ScanScope.itemBarcode,
        ScanScope.batchNo,
        ScanScope.sourceRack,
        ScanScope.targetRack,
      ];

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Subscribe to [DataWedgeService] and [ScanService].
  /// Call from [onInit] after `super.onInit()`.
  ///
  /// Safe to call multiple times — cancels previous subscriptions first.
  void initBarcodeListeners() {
    _dwSub?.cancel();
    _scanSub?.cancel();

    _dwSub = Get.find<DataWedgeService>()
        .barcodeStream
        .listen(_onRaw);

    _scanSub = Get.find<ScanService>()
        .barcodeStream
        .listen(_onRaw);
  }

  @override
  void onClose() {
    _dwSub?.cancel();
    _dwSub = null;
    _scanSub?.cancel();
    _scanSub = null;
    super.onClose();
  }

  // ── Internal dispatch ─────────────────────────────────────────────────

  void _onRaw(String raw) {
    if (!isScanEnabled || isClosed) return;
    final now = DateTime.now();
    final trimmed = raw.trim();
    // Dedup: drop duplicate hardware events within 300 ms.
    if (trimmed == _lastRaw &&
        _lastTime != null &&
        now.difference(_lastTime!) < const Duration(milliseconds: 300)) return;
    _lastRaw = trimmed;
    _lastTime = now;

    isScanning.value = true;
    onBarcodeScanned(trimmed);
    Future.delayed(
      const Duration(milliseconds: 350),
      () {
        if (!isClosed) isScanning.value = false;
      },
    );
  }

  // ── Routing ───────────────────────────────────────────────────────────

  /// Route [barcode] using the 3-level priority chain.
  ///
  /// Override only when the default chain doesn't fit your DocType.
  /// Prefer overriding [onItemBarcodeScanned] / [onTargetRackScanned]
  /// for targeted customisation.
  @protected
  void onBarcodeScanned(String barcode) {
    // Priority 1: focused field.
    final focused = _focusedScope();
    if (focused != null && activeScanScopes.contains(focused)) {
      _applyToScope(focused, barcode);
      return;
    }
    // Priority 2: first empty field.
    for (final scope in activeScanScopes) {
      if (_isEmpty(scope)) {
        _applyToScope(scope, barcode);
        return;
      }
    }
    // Priority 3: fallback — overwrite first scope in list.
    if (activeScanScopes.isNotEmpty) {
      _applyToScope(activeScanScopes.first, barcode);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  ScanScope? _focusedScope() {
    if (itemBarcodeFocusNode.hasFocus) return ScanScope.itemBarcode;
    if (batchFocusNode.hasFocus) return ScanScope.batchNo;
    if (rackFocusNode.hasFocus) return ScanScope.sourceRack;
    if (_targetRackFocusNode?.hasFocus ?? false) return ScanScope.targetRack;
    return null;
  }

  bool _isEmpty(ScanScope scope) {
    switch (scope) {
      case ScanScope.itemBarcode:
        return itemCode.value.isEmpty;
      case ScanScope.batchNo:
        return batchController.text.isEmpty;
      case ScanScope.sourceRack:
        return rackController.text.isEmpty;
      case ScanScope.targetRack:
        return _targetRackController?.text.isEmpty ?? true;
    }
  }

  void _applyToScope(ScanScope scope, String barcode) {
    switch (scope) {
      case ScanScope.itemBarcode:
        itemCode.value = barcode;
        onItemBarcodeScanned(barcode);
        break;
      case ScanScope.batchNo:
        batchController.text = barcode;
        validateBatch(barcode);
        break;
      case ScanScope.sourceRack:
        rackController.text = barcode;
        validateRack(barcode);
        break;
      case ScanScope.targetRack:
        final tgt = _targetRackController;
        if (tgt != null) {
          tgt.text = barcode;
          onTargetRackScanned(barcode);
        }
        break;
    }
  }

  // ── Extension points ──────────────────────────────────────────────────

  /// Called when [ScanScope.itemBarcode] receives a scan.
  ///
  /// Base: no-op. Override in each DocType to trigger item lookup.
  @protected
  void onItemBarcodeScanned(String barcode) {}

  /// Called when [ScanScope.targetRack] receives a scan.
  ///
  /// Base: no-op. Override in [StockEntryItemFormController] to call
  /// `validateDualRack(barcode, false)`.
  @protected
  void onTargetRackScanned(String barcode) {}

  /// The target-rack [TextEditingController]. Base returns `null`.
  /// Override in dual-rack controllers (e.g. Stock Entry).
  TextEditingController? get _targetRackController => null;

  /// The target-rack [FocusNode]. Base returns `null`.
  /// Override in dual-rack controllers (e.g. Stock Entry).
  FocusNode? get _targetRackFocusNode => null;
}
