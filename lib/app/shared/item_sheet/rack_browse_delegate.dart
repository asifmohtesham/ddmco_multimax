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
/// is the **calling DocType's responsibility**.  This boundary is
/// intentional: different DocTypes may map the same picker result to
/// different fields (source rack, target rack, single rack) and may have
/// different post-pick validation flows.
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
/// // In the DocType controller:
/// class MyController extends GetxController
///     implements RackFieldWithBrowseDelegate {
///
///   @override
///   bool get canBrowseRacks => itemCode.value.isNotEmpty;
///
///   @override
///   Future<RackPickerResult?> browseRacks() async {
///     if (!canBrowseRacks) return null;
///     final result = await showRackPickerSheet(...);
///     return result;   // caller writes to field and validates
///   }
/// }
///
/// // In the widget (owned by DocType, not by this interface):
/// if (result != null) {
///   controller.rackController.text = result.rackId;
///   await controller.validateRack(result.rackId);
/// }
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
  /// responsible for:
  /// 1. Writing `result.rackId` into the appropriate rack field.
  /// 2. Calling `validateRack(result.rackId)` to confirm live availability.
  /// 3. Updating any DocType-specific state that depends on the rack choice.
  ///
  /// ## Concurrency
  ///
  /// Implementations should guard against re-entrant calls (e.g. two rapid
  /// taps opening two sheets).  A simple `isValidatingRack.value` check is
  /// sufficient in most cases.
  Future<RackPickerResult?> browseRacks();
}
