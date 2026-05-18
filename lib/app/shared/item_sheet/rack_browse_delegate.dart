// ignore_for_file: lines_longer_than_80_chars

import 'rack_picker_result.dart';

/// Browse-racks capability contract.
///
/// A controller that implements this interface can open the shared
/// [RackPickerSheet] and return the user's selection as a
/// [RackPickerResult].
///
/// ## Responsibility boundary
///
/// This interface owns **only the browse flow**:
/// - Checking pre-conditions ([canBrowseRacks]).
/// - Opening the picker sheet.
/// - Returning the selection result.
///
/// It does **not** write into any form field.  Post-selection handling
/// (writing to `rackController`, triggering validation, updating balance)
/// is the **calling DocType's responsibility** via [handleRackPicked] on
/// [RackFieldWithBrowseDelegate].  This boundary is intentional: different
/// DocTypes may map the same picker result to different fields (source
/// rack, target rack, single rack) and may have different post-pick
/// validation flows.
///
/// ## Pre-conditions
///
/// Implementations must check [canBrowseRacks] before opening the sheet.
/// Typical pre-conditions:
/// - `itemCode` is non-empty
/// - `resolvedWarehouse` is known (or acceptable to browse without filter)
///
/// ## Total Row guarantee (from data source)
///
/// The Stock Balance report used by Browse Racks may include a **Total
/// Row as its last entry**.  That row is a report footer aggregate — it is
/// NOT a real rack record and must never be exposed as a selectable option.
///
/// [ApiProvider.getStockBalanceWithDimension] already discards this row
/// before returning results to [RackPickerController].  This contract
/// documents the invariant here for cross-file traceability: any future
/// implementation of [browseRacks] that bypasses the shared API helper
/// **must** replicate the Total Row discard.
///
/// ## Usage example
///
/// ```dart
/// // In the DocType controller — implement RackFieldWithBrowseDelegate
/// // (which extends both RackFieldDelegate and RackBrowseDelegate):
/// class MyController extends GetxController
///     implements RackFieldWithBrowseDelegate {
///
///   @override
///   bool get canBrowseRacks => itemCode.value.isNotEmpty;
///
///   @override
///   Future<RackPickerResult?> browseRacks() async {
///     if (!canBrowseRacks) return null;
///     return showRackPickerSheet(...);
///   }
///
///   // handleRackPicked is the canonical post-pick hook.
///   // ItemSheetControllerBase supplies a default implementation that
///   // writes rackId into rackController and calls validateRack().
///   // Override when DocType-specific post-pick logic is required:
///   @override
///   Future<void> handleRackPicked(RackPickerResult result) async {
///     rackController.text = result.rackId;
///     await validateRack(result.rackId);
///     // DocType-specific extra logic here...
///   }
/// }
///
/// // In the sheet orchestrator — call handleRackPicked after browseRacks:
/// final result = await controller.browseRacks();
/// if (result != null) await controller.handleRackPicked(result);
/// ```
abstract interface class RackBrowseDelegate {
  /// Whether the controller currently satisfies the pre-conditions required
  /// to open the rack picker.
  ///
  /// When `false`, the shelves icon button in [ValidatedRackField] should
  /// be disabled or hidden.  Implementations must not rely on [browseRacks]
  /// being guarded by the widget — callers may invoke [browseRacks] directly
  /// (e.g. from a test or an alternative UI path).
  bool get canBrowseRacks;

  /// Opens the shared rack picker and returns the selected [RackPickerResult],
  /// or `null` if the user dismissed the sheet without making a selection.
  ///
  /// ## Post-selection contract
  ///
  /// This method returns **only the selection**.  The calling DocType is
  /// responsible for calling [RackFieldWithBrowseDelegate.handleRackPicked]
  /// with the result.  The default implementation in
  /// [ItemSheetControllerBase.handleRackPicked] writes `result.rackId`
  /// into `rackController` and calls `validateRack`.  Override
  /// `handleRackPicked` in the concrete controller for DocType-specific
  /// post-pick logic.
  ///
  /// ## Concurrency
  ///
  /// Implementations should guard against re-entrant calls (e.g. two rapid
  /// taps opening two sheets).  A simple `isValidatingRack.value` check is
  /// sufficient in most cases.
  Future<RackPickerResult?> browseRacks();
}
