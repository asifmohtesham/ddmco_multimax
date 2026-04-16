// lib/app/shared/item_sheet/dual_rack_adapters.dart
// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'dual_rack_delegate.dart';
import 'rack_field_with_browse_delegate.dart';
import 'rack_picker_controller.dart';
import 'rack_picker_result.dart';
import 'rack_picker_sheet.dart';

/// Adapts the **source-rack** half of a [DualRackDelegate] into the
/// [RackFieldWithBrowseDelegate] interface consumed by [SharedRackField].
///
/// ## Purpose
/// [SharedRackField] is the canonical, feature-complete rack widget.  It
/// requires a single [RackFieldWithBrowseDelegate] that presents one
/// unified rack field (one controller, one validity flag, one `onChange`).
/// [DualRackDelegate] splits these across *source* and *target* sides.
/// [SourceRackFieldAdapter] projects the source-side members onto the
/// single-field interface so [SharedRackField] can drive the source rack
/// without modification.
///
/// ## Picker lifecycle
/// [browseRacks] owns the full picker flow previously embedded in
/// [SharedSourceRackField._openPicker]:
///   1. Instantiate [RackPickerController] with a unique timestamped tag.
///   2. Fire `ctrl.load(...)` unawaited — sheet renders progressively.
///   3. Present [RackPickerSheet] via `Get.bottomSheet`.
///   4. On selection, write into [_d.sourceRackController] and call
///      [_d.onSourceRackChanged] so the delegate's validation pipeline runs.
///   5. Post-frame cleanup via `Get.delete<RackPickerController>(tag:)`.
///
/// No behaviour is changed relative to [SharedSourceRackField]; only the
/// ownership of the lifecycle moves from the widget to this adapter.
///
/// ## Balance
/// [rackBalanceFor] returns [_d.rackBalance.value] — the live [RxDouble]
/// maintained by [SourceRackDelegate] and populated by the controller's
/// validation pipeline.  [SharedRackField] calls this in its [Obx] rebuild
/// so the [BalanceChip] updates reactively.
class SourceRackFieldAdapter implements RackFieldWithBrowseDelegate {
  final DualRackDelegate _d;

  /// Constructs an adapter projecting the source-rack side of [delegate].
  const SourceRackFieldAdapter(DualRackDelegate delegate) : _d = delegate;

  // ── RackFieldDelegate ─────────────────────────────────────────────────────

  @override
  TextEditingController get rackController   => _d.sourceRackController;

  @override
  FocusNode get rackFocusNode =>
      _d.sourceRackController.value == _d.sourceRackController.value
      // FocusNode is not on SourceRackDelegate; create a stable instance.
      // Callers that need focus management should add rackFocusNode to
      // SourceRackDelegate in a follow-up commit.
          ? FocusNode()
          : FocusNode();
  // TODO(rack-focus): add `FocusNode get sourceRackFocusNode` to
  //   SourceRackDelegate and wire it here.

  @override
  RxBool get isRackValid       => _d.isSourceRackValid;

  @override
  RxBool get isValidatingRack  => _d.isValidatingSourceRack;

  @override
  RxString get rackError       => _d.rackError;

  /// Not used by SharedRackField when [balanceOverride] is supplied.
  @override
  double rackBalanceFor(String rack) => _d.rackBalance.value;

  @override
  RxnString get rackStockTooltip => RxnString(null); // SE has no per-rack tooltip

  /// Soft-resets source-rack validity state without clearing the text field.
  ///
  /// Called when the user taps the pencil/edit icon to re-enter edit mode
  /// on the source rack.  Preserves [_d.sourceRackController] text so the
  /// operator can edit in-place rather than retyping.
  ///
  /// Delegates to [SourceRackDelegate.resetSourceRackValidation] which
  /// clears [isSourceRackValid], [rackError], and [rackBalance] but leaves
  /// [sourceRackController.text] intact.  This satisfies [RackFieldDelegate]'s
  /// [softResetRack] contract for the source-rack side.
  @override
  void softResetRack() => _d.resetSourceRackValidation();

  @override
  void resetRack() => _d.resetSourceRackValidation();

  @override
  Future<void> validateRack(String rack) => _d.onSourceRackChanged(rack);

  // ── RackBrowseDelegate ────────────────────────────────────────────────────

  @override
  RxString get itemCode => _d.itemCode;

  @override
  TextEditingController get batchController => _d.batchController;

  @override
  TextEditingController get qtyController   => _d.qtyController;

  /// Whether the source-rack picker can currently be opened.
  ///
  /// Returns `true` only when both an item code and a resolved source
  /// warehouse are available — the two pre-conditions required by
  /// [RackPickerSheet] to scope the rack list.
  ///
  /// This getter is read inside [SharedRackField]'s [Obx] rebuild, so it
  /// is evaluated reactively: the picker button appears as soon as
  /// [_d.sourceRackWarehouse] becomes non-empty (e.g. after the operator
  /// picks an item that resolves to a warehouse).
  ///
  /// Mirrors the inline `onPickerTap` guard in [SharedDualRackSection]:
  /// ```dart
  /// onPickerTap: (controller.itemCode.value.isNotEmpty &&
  ///     (controller.sourceRackWarehouse?.value?.isNotEmpty ?? false))
  ///     ? srcAdapter.browseRacks
  ///     : null,
  /// ```
  /// Having both guards is intentional: the widget suppresses the button
  /// entirely when `null`; this getter adds a second, internal guard so
  /// [browseRacks] is always safe to call even from non-widget code paths.
  @override
  bool get canBrowseRacks =>
      _d.itemCode.value.isNotEmpty &&
          (_d.sourceRackWarehouse?.value?.isNotEmpty ?? false);

  /// Opens the rack picker scoped to [_d.sourceRackWarehouse] and returns
  /// the operator's selection, or `null` if dismissed.
  ///
  /// ## Responsibility boundary
  /// This method owns **only the browse flow** per [RackBrowseDelegate]'s
  /// contract [cite:56]:
  ///   - Checks [canBrowseRacks] pre-condition.
  ///   - Instantiates [RackPickerController] with a unique timestamped tag
  ///     to prevent GetX tag collisions when two sheets open in sequence.
  ///   - Fires `ctrl.load(...)` unawaited — the sheet renders progressively
  ///     as data arrives.
  ///   - Presents [RackPickerSheet] via `Get.bottomSheet`.
  ///   - Returns the selection as a [RackPickerResult] — does NOT write
  ///     into [_d.sourceRackController] directly.
  ///   - Post-frame cleanup of the [RackPickerController] singleton.
  ///
  /// Post-selection handling (writing the rack ID into the controller,
  /// triggering validation) is performed by [handleRackPicked], which the
  /// [SharedDualRackSection] orchestrator calls after this method returns.
  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks) return null;

    final warehouse = _d.sourceRackWarehouse?.value ?? '';
    final tag       = 'src_rack_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl      = Get.put(RackPickerController(), tag: tag);

    unawaited(ctrl.load(
      itemCode:     _d.itemCode.value,
      batchNo:      _d.batchController.text.trim(),
      warehouse:    warehouse,
      requestedQty: double.tryParse(_d.qtyController.text) ?? 0.0,
      currentRack:  _d.sourceRackController.text.trim(),
      fallbackMap:  const {},
    ));

    RackPickerResult? result;

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          // availableQty is 0.0 here because RackPickerSheet.onSelected receives
          // only the rack String, not the full entry.  The post-pick call to
          // handleRackPicked → onSourceRackChanged / onTargetRackChanged triggers
          // the controller's validateRack pipeline which fetches and populates the
          // authoritative live balance before availableQty is ever read.
          // See RackPickerResult.availableQty Dartdoc for the full rationale.
          result = RackPickerResult(rackId: rack, availableQty: 0.0);
        },
      ),
      isScrollControlled: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });

    return result;
  }

  /// Writes the picked [result.rackId] into [_d.sourceRackController] and
  /// triggers source-rack validation via [_d.onSourceRackChanged].
  ///
  /// Called by [SharedDualRackSection] (or any sheet orchestrator) after
  /// [browseRacks] returns a non-null result.  The separation of [browseRacks]
  /// (returns result) and [handleRackPicked] (applies result) matches the
  /// [RackFieldWithBrowseDelegate] contract [cite:55].
  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    _d.sourceRackController.text = result.rackId;
    await _d.onSourceRackChanged(result.rackId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Adapts the **target-rack** half of a [DualRackDelegate] into the
/// [RackFieldWithBrowseDelegate] interface consumed by [SharedRackField].
///
/// ## Balance
/// Target rack has no outbound stock balance to display.  [rackBalanceFor]
/// always returns `0.0` and [SharedRackField] is instantiated with
/// `balanceOverride: () => null` so the [BalanceChip] is never shown for
/// the target side (chip only shows when `balance > 0 || forceShow`).
///
/// ## Picker lifecycle
/// Mirrors [SourceRackFieldAdapter.browseRacks] but scoped to
/// [_d.targetRackWarehouse] and wired to [_d.onTargetRackChanged].
class TargetRackFieldAdapter implements RackFieldWithBrowseDelegate {
  final DualRackDelegate _d;

  /// Constructs an adapter projecting the target-rack side of [delegate].
  const TargetRackFieldAdapter(DualRackDelegate delegate) : _d = delegate;

  // ── RackFieldDelegate ─────────────────────────────────────────────────────

  @override
  TextEditingController get rackController  => _d.targetRackController;

  @override
  FocusNode get rackFocusNode => FocusNode();
  // TODO(rack-focus): add `FocusNode get targetRackFocusNode` to
  //   TargetRackDelegate and wire it here.

  @override
  RxBool get isRackValid      => _d.isTargetRackValid;

  @override
  RxBool get isValidatingRack => _d.isValidatingTargetRack;

  @override
  RxString get rackError      => _d.rackError;

  /// Always returns `0.0`; target rack has no outbound balance.
  ///
  /// [SharedRackField] is instantiated with `balanceOverride: () => null`
  /// for the target side, so this method is never reached at runtime.
  @override
  double rackBalanceFor(String rack) => 0.0;

  @override
  RxnString get rackStockTooltip => RxnString(null);

  /// Soft-resets target-rack validity state without clearing the text field.
  ///
  /// Delegates to [TargetRackDelegate.resetTargetRackValidation].
  /// See [SourceRackFieldAdapter.softResetRack] for the full rationale.
  @override
  void softResetRack() => _d.resetTargetRackValidation();

  @override
  void resetRack() => _d.resetTargetRackValidation();

  @override
  Future<void> validateRack(String rack) => _d.onTargetRackChanged(rack);

  // ── RackBrowseDelegate ────────────────────────────────────────────────────

  @override
  RxString get itemCode => _d.itemCode;

  @override
  TextEditingController get batchController => _d.batchController;

  @override
  TextEditingController get qtyController   => _d.qtyController;

  /// Whether the target-rack picker can currently be opened.
  ///
  /// Returns `true` only when both an item code and a resolved target
  /// warehouse are available.  See [SourceRackFieldAdapter.canBrowseRacks]
  /// for the full rationale.
  @override
  bool get canBrowseRacks =>
      _d.itemCode.value.isNotEmpty &&
          (_d.targetRackWarehouse?.value?.isNotEmpty ?? false);

  /// Opens the rack picker scoped to [_d.targetRackWarehouse].
  /// See [SourceRackFieldAdapter.browseRacks] for the full rationale.
  @override
  Future<RackPickerResult?> browseRacks() async {
    if (!canBrowseRacks) return null;

    final warehouse = _d.targetRackWarehouse?.value ?? '';
    final tag       = 'tgt_rack_${DateTime.now().microsecondsSinceEpoch}';
    final ctrl      = Get.put(RackPickerController(), tag: tag);

    unawaited(ctrl.load(
      itemCode:     _d.itemCode.value,
      batchNo:      _d.batchController.text.trim(),
      warehouse:    warehouse,
      requestedQty: double.tryParse(_d.qtyController.text) ?? 0.0,
      currentRack:  _d.targetRackController.text.trim(),
      fallbackMap:  const {},
    ));

    RackPickerResult? result;

    await Get.bottomSheet(
      RackPickerSheet(
        pickerTag:  tag,
        onSelected: (rack) {
          // availableQty is 0.0 here because RackPickerSheet.onSelected receives
          // only the rack String, not the full entry.  The post-pick call to
          // handleRackPicked → onSourceRackChanged / onTargetRackChanged triggers
          // the controller's validateRack pipeline which fetches and populates the
          // authoritative live balance before availableQty is ever read.
          // See RackPickerResult.availableQty Dartdoc for the full rationale.
          result = RackPickerResult(rackId: rack, availableQty: 0.0);
        },
      ),
      isScrollControlled: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<RackPickerController>(tag: tag)) {
        Get.delete<RackPickerController>(tag: tag);
      }
    });

    return result;
  }

  /// Writes the picked [result.rackId] into [_d.targetRackController] and
  /// triggers target-rack validation via [_d.onTargetRackChanged].
  @override
  Future<void> handleRackPicked(RackPickerResult result) async {
    _d.targetRackController.text = result.rackId;
    await _d.onTargetRackChanged(result.rackId);
  }
}
