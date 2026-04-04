// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Narrow interface that [SharedDualRackSection] depends on.
///
/// Any controller that implements this interface can drive the dual-rack
/// (source + target) section widget with zero additional ceremony.
///
/// ## Why a separate interface?
///
/// [SharedDualRackSection] was previously typed to the concrete
/// [StockEntryItemFormController].  That prevented any other DocType from
/// reusing the widget without inheriting an SE-specific class.
/// [DualRackDelegate] is the minimal contract the widget actually reads —
/// nothing more.
///
/// ## Adoption
///
/// [StockEntryItemFormController] implements this interface additively
/// (Commit 8).  All existing call sites pass the same concrete controller
/// and compile without changes.
///
/// Future DocType controllers that need a source + target rack layout
/// implement this interface directly, independent of
/// [ItemSheetControllerBase].
///
/// ## SE-type visibility rule
///
/// [SharedDualRackSection] derives `showSource` / `showTarget` from
/// [selectedStockEntryType].  This is intentionally on the interface
/// because the dual-rack widget is inherently movement-type-aware —
/// any future adopter will need to supply an equivalent discriminant.
abstract interface class DualRackDelegate {
  // ── Source rack ──────────────────────────────────────────────────────────
  TextEditingController get sourceRackController;
  RxBool get isSourceRackValid;
  RxBool get isValidatingSourceRack;

  void resetSourceRackValidation();
  Future<void> validateDualRack(String rack, bool isSource);

  // ── Target rack ──────────────────────────────────────────────────────────
  TextEditingController get targetRackController;
  RxBool get isTargetRackValid;
  RxBool get isValidatingTargetRack;

  void resetTargetRackValidation();

  // ── Balance ──────────────────────────────────────────────────────────────
  RxDouble get rackBalance;
  RxBool   get isLoadingRackBalance;

  // ── Error ────────────────────────────────────────────────────────────────
  RxString get rackError;

  // ── Rack stock map (picker fallback) ─────────────────────────────────────
  /// Pre-loaded rack → qty map used as the fallback / merge-base when the
  /// [RackPickerController] is loaded.  Matches the pattern used in
  /// [SharedDualRackSection._openRackPicker].
  Map<String, double> get rackStockMap;

  // ── Item identity ────────────────────────────────────────────────────────
  RxString get itemCode;

  // ── Warehouse derivation labels ──────────────────────────────────────────
  RxnString get itemSourceWarehouse;
  RxnString get derivedSourceWarehouse;
  RxnString get itemTargetWarehouse;
  RxnString get derivedTargetWarehouse;

  // ── Parent warehouse accessors ───────────────────────────────────────────
  /// The currently-selected source (From) warehouse at the header level.
  /// Exposes the parent controller's reactive value without hard-typing to
  /// [StockEntryFormController].
  RxnString get selectedFromWarehouse;

  /// The currently-selected target (To) warehouse at the header level.
  RxnString get selectedToWarehouse;

  /// The current Stock Entry type string (e.g. 'Material Transfer',
  /// 'Material Issue').  Used by [SharedDualRackSection] to derive
  /// [showSource] / [showTarget] visibility.
  RxString  get selectedStockEntryType;

  // ── Batch controller (picker: batchNo filter) ────────────────────────────
  TextEditingController get batchController;

  // ── Qty controller (picker: requestedQty) ────────────────────────────────
  TextEditingController get qtyController;
}
