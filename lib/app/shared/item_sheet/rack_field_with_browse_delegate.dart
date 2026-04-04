// ignore_for_file: lines_longer_than_80_chars

import 'rack_browse_delegate.dart';
import 'rack_field_delegate.dart';
import 'rack_picker_result.dart';

/// Combined rack-field + Browse Racks contract.
///
/// This is the **primary interface** that [SharedRackField] (post Commit 6)
/// will depend on instead of [ItemSheetControllerBase].  Any controller
/// that implements this interface can fully drive the rack field widget,
/// including the optional Browse Racks picker flow.
///
/// ## Composition
///
/// [RackFieldWithBrowseDelegate] is the union of two narrower interfaces:
///
/// | Interface            | Responsibility                              |
/// |----------------------|---------------------------------------------|
/// | [RackFieldDelegate]  | Reactive state, text controller, validation |
/// | [RackBrowseDelegate] | Browse Racks picker flow                    |
///
/// Keeping them separate means a controller can implement [RackFieldDelegate]
/// alone (no picker support) and still work with the widget in non-picker
/// mode.  Only when [RackFieldWithBrowseDelegate] is fully implemented does
/// the picker button become active.
///
/// ## Adoption path
///
/// The refactor is phased to avoid breaking changes:
///
/// 1. **Commit 5**: [ItemSheetControllerBase] adopts this interface
///    additively, providing default implementations of all members so
///    existing concrete controllers require no changes.
/// 2. **Commit 6**: [SharedRackField] switches its field type from
///    `ItemSheetControllerBase` to `RackFieldWithBrowseDelegate`.
/// 3. **Commit 7**: Delivery Note wires its concrete picker flow.
/// 4. **Commit 9**: Stock Entry follows after DN QC passes.
///
/// New DocType controllers (e.g. Material Request item sheet) can implement
/// this interface directly without inheriting [ItemSheetControllerBase].
///
/// ## Post-pick responsibility
///
/// [handleRackPicked] is the standard hook for DocType-owned post-selection
/// logic.  [ItemSheetControllerBase] supplies a default implementation that
/// writes [RackPickerResult.rackId] into [rackController] and calls
/// [validateRack].  DocTypes with divergent post-pick behaviour
/// (e.g. SE source vs target rack) override this method.
///
/// [SharedRackField] does **not** call [handleRackPicked] itself.  The
/// widget fires [onPickerTap] (a callback), and the DocType-owned sheet
/// orchestrator decides when and how to call [handleRackPicked].
abstract interface class RackFieldWithBrowseDelegate
    implements RackFieldDelegate, RackBrowseDelegate {
  /// Standard post-selection hook.
  ///
  /// Called by the DocType orchestrator after [browseRacks] returns a
  /// non-null [RackPickerResult].  The default implementation in
  /// [ItemSheetControllerBase] (added in Commit 5) writes
  /// [RackPickerResult.rackId] into [rackController] and calls
  /// [validateRack].
  ///
  /// Override in the concrete controller to apply DocType-specific
  /// post-pick behaviour before or after calling the default logic.
  ///
  /// ## Why this is on the interface (not just the base class)
  ///
  /// Declaring it here means any controller that implements this interface
  /// — including ones that do not extend [ItemSheetControllerBase] — must
  /// explicitly decide what happens after a rack is picked.  This prevents
  /// silent no-ops in future lightweight DocType controllers.
  Future<void> handleRackPicked(RackPickerResult result);
}
