// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter/foundation.dart';

/// Immutable value type returned when the user selects a rack from the
/// Browse Racks picker.
///
/// ## Relationship to [RackPickerEntry]
///
/// [RackPickerEntry] is the **display model** used internally by
/// [RackPickerController] and [RackPickerSheet] to render rack rows.
/// [RackPickerResult] is the **selection output** — the minimal, stable
/// record handed back to the calling DocType once the user confirms a
/// choice.  The two types are intentionally separate:
///
/// | Concern                          | Type              |
/// |----------------------------------|-------------------|
/// | Picker list display, sorting     | `RackPickerEntry` |
/// | Post-selection data to DocType   | `RackPickerResult`|
///
/// ## Data source
///
/// Instances are produced by [RackPickerSheet] from the Stock Balance
/// report fetched with `show_dimension_wise_stock=1`.  The report is
/// scoped to a single item code and optionally filtered by warehouse.
///
/// ## Why `batchNo` is absent
///
/// The Stock Balance report used by Browse Racks does **not** include
/// a Batch No column in its per-rack rows.  Adding a `batchNo` field
/// here would therefore always be empty, misleading callers into
/// assuming batch information is available from the picker.
///
/// Batch context is already present on the calling DocType controller
/// (e.g. `batchController.text`) and must not be sourced from the
/// rack-picker result.
///
/// ## Total Row guarantee
///
/// [ApiProvider.getStockBalanceWithDimension] discards the trailing
/// Total Row before returning results to [RackPickerController].
/// A [RackPickerResult] is therefore always backed by a real rack row,
/// never by the report footer aggregate.
///
/// ## Usage
///
/// ```dart
/// final result = await browseRacks();
/// if (result == null) return;   // user dismissed picker
///
/// rackController.text = result.rackId;
/// await validateRack(result.rackId);
/// // Do NOT read result.batchNo — it does not exist.
/// ```
@immutable
class RackPickerResult {
  /// The rack asset-code selected by the user, e.g. `'KA-WH-DXB1-101A'`.
  ///
  /// This value should be written directly into the rack text field of
  /// the receiving DocType.  It is already trimmed.
  final String rackId;

  /// Available quantity for the current item in [rackId] as reported by
  /// the Stock Balance data source at the time the picker was opened.
  ///
  /// This is a snapshot value.  The DocType must re-validate via its own
  /// [validateRack] call to obtain the authoritative live balance.
  ///
  /// When [browseRacks] builds the result from an [onSelected] callback
  /// that only receives the rack String (not the full entry), pass 0.0
  /// here — the DocType's post-pick validation will overwrite it with
  /// the authoritative live balance before it is ever read.
  final double availableQty;

  /// Warehouse name associated with this rack row, when the report
  /// includes it.
  ///
  /// May be empty when the picker was opened without a warehouse filter
  /// or when the rack asset code does not embed a warehouse identifier.
  /// DocTypes should not depend on this for their primary warehouse logic.
  final String warehouse;

  /// Raw row map returned by the Stock Balance data source.
  ///
  /// Preserved for:
  /// - Advanced DocType-specific handling of extra report columns.
  /// - Diagnostic logging and QC.
  /// - Future-safe access to new fields without changing this class.
  ///
  /// Do not rely on specific keys in [raw] for production logic;
  /// use the typed fields above instead.
  final Map<String, dynamic> raw;

  const RackPickerResult({
    required this.rackId,
    required this.availableQty,
    this.warehouse = '',
    this.raw = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RackPickerResult &&
          runtimeType == other.runtimeType &&
          rackId == other.rackId;

  @override
  int get hashCode => rackId.hashCode;

  @override
  String toString() =>
      'RackPickerResult(rackId: $rackId, availableQty: $availableQty, '
      'warehouse: $warehouse)';
}
