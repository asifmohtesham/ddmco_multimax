// ignore_for_file: lines_longer_than_80_chars

import 'rack_browse_delegate.dart';
import 'rack_field_delegate.dart';
import 'rack_picker_result.dart';

/// Combined rack-field + Browse Racks contract.
///
/// This is the **primary interface** that [SharedRackField] depends on.
/// Any controller that implements this interface can fully drive the rack
/// field widget, including the optional Browse Racks picker flow.
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
/// mode (see **RackFieldDelegate-only path** below).  Only when
/// [RackFieldWithBrowseDelegate] is fully implemented does the picker
/// button become active.
///
/// ## As-built adoption — 4-commit series (COMPLETE)
///
/// The refactor was phased to avoid breaking changes:
///
/// | Commit | Action                                                  |
/// |--------|---------------------------------------------------------|
/// | 1      | Extract RackFieldDelegate + RackFieldWithBrowseDelegate  |
/// |        | interfaces; rackStockMap removed from base class;       |
/// |        | rackBalanceFor() added to ItemSheetControllerBase.      |
/// | 2      | Standardize rackError to non-nullable RxString; codebase|
/// |        | audit confirmed zero nullable usages; contract sealed.  |
/// | 3      | SharedRackField.c type switch confirmed complete; base  |
/// |        | class already declared `implements RackFieldWithBrowse-  |
/// |        | Delegate` with all four default overrides; SE/DN/PR     |
/// |        | call sites satisfy the interface transitively.          |
/// | 4      | Stale commit-numbering comments removed; RackFieldDelegate|
/// |        | -only path documented; series sealed COMPLETE.          |
///
/// New DocType controllers (e.g. Material Request item sheet) can implement
/// this interface directly without inheriting [ItemSheetControllerBase].
///
/// ## RackFieldDelegate-only path (non-picker mode)
///
/// A lightweight controller that does NOT need Browse Racks support can
/// implement [RackFieldDelegate] directly and still be used with
/// [SharedRackField] as long as the call site does not pass [onPickerTap]:
///
/// ```dart
/// class LightweightRackController extends GetxController
///     implements RackFieldDelegate {
///   @override final isRackValid      = false.obs;
///   @override final isValidatingRack = false.obs;
///   @override final rackError        = RxString('');
///   @override final rackStockTooltip = RxnString(null);
///   @override final rackController   = TextEditingController();
///   @override final rackFocusNode    = FocusNode();
///
///   @override double rackBalanceFor(String rack) => _balance;
///   @override void   resetRack()                 { /* ... */ }
///   @override Future<void> validateRack(String rack) async { /* ... */ }
/// }
///
/// // In the sheet — no picker button shown because onPickerTap is null:
/// SharedRackField(c: lightweightController, accentColor: Colors.teal)
/// ```
///
/// To enable the picker button, upgrade to [RackFieldWithBrowseDelegate].
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
  /// [ItemSheetControllerBase] writes [RackPickerResult.rackId] into
  /// [rackController] and calls [validateRack].
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
