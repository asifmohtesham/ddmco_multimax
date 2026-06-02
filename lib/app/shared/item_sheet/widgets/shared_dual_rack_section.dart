// lib/app/shared/item_sheet/widgets/shared_dual_rack_section.dart
// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:multimax/app/shared/item_sheet/dual_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/dual_rack_adapters.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';

/// Renders a source rack field followed by a target rack field for any
/// controller that implements [DualRackDelegate].
///
/// ## Architecture
/// Each side is rendered by a standard [SharedRackField] — the same
/// feature-complete widget used by Delivery Note and Purchase Receipt.
/// This automatically restores:
///   - [BalanceChip] on the source side (driven by [DualRackDelegate.rackBalance])
///   - Browse Rack shelves button on both sides
///   - [GlobalItemFormSheet.buildInputGroup] framing (section label +
///     coloured left border) on both fields
///   - Reactive validation spinner + green check-circle suffix
///
/// The two sides are bridged to [SharedRackField]'s required
/// [RackFieldWithBrowseDelegate] interface via thin adapters:
///   - [SourceRackFieldAdapter] projects [DualRackDelegate]'s source-side
///     members (sourceRackController, isSourceRackValid, rackBalance, …)
///   - [TargetRackFieldAdapter] projects the target-side members
///
/// The adapters are instantiated once per build cycle as `final` locals;
/// they are lightweight value-objects with no mutable state.
///
/// ## Visibility
/// [DualRackDelegate.showSourceRack] and [DualRackDelegate.showTargetRack]
/// gate each field reactively inside the outer [Obx].  Manufacture
/// finished-good rows show only the target; Material Issue shows only
/// the source; all transfer types show both.
///
/// ## Balance chip
/// Source rack shows a [BalanceChip] via [SharedRackField]'s
/// `balanceOverride` callback, which reads [DualRackDelegate.rackBalance]
/// live.  Target rack suppresses the chip by passing
/// `balanceOverride: () => null` — target is a destination; its balance
/// is not operationally relevant during a transfer.
///
/// ## Regression note (fixed in this commit)
/// Previous implementation used [SharedSourceRackField] and
/// [SharedTargetRackField] which rendered bare, unframed [TextField]
/// widgets — no [BalanceChip], no `buildInputGroup`, no reactive browse
/// button.  This commit deletes both of those widgets and replaces them
/// with [SharedRackField] via the adapter bridge.
class SharedDualRackSection extends StatelessWidget {
  /// Controller implementing [DualRackDelegate].
  ///
  /// Typically [StockEntryItemFormController] or
  /// [JobCardItemFormController]; any future controller that implements
  /// [DualRackDelegate] is automatically compatible.
  final DualRackDelegate controller;

  const SharedDualRackSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Adapters are final locals, not fields, because they hold no mutable
    // state and do not require disposal.  They are cheap to recreate.
    final srcAdapter = SourceRackFieldAdapter(controller);
    final tgtAdapter = TargetRackFieldAdapter(controller);

    return Obx(() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Source Rack ───────────────────────────────────────────────────
        // Shown only when the controller confirms the current row draws
        // stock from a source location (e.g. hidden for Manufacture FG row).
        if (controller.showSourceRack)
          SharedRackField(
            key:      const ValueKey('dual_rack_source'),
            c:        srcAdapter,
            label:    'Source Rack',
            hint:     'Enter or scan source rack ID',
            editMode: true,
            // Live balance from SourceRackDelegate.rackBalance — the RxDouble
            // populated by the controller's validateSourceRack pipeline.
            // Passed as balanceOverride so the BalanceChip reads the live
            // RxDouble rather than the map-based rackBalanceFor fallback.
            balanceOverride: () => controller.rackBalance.value,
            // Browse button is active when both an item code and a resolved
            // source warehouse are available.  Reactive because the Obx
            // surrounding this build() re-evaluates when either changes.
            onPickerTap: controller.itemCode.value.isNotEmpty &&
                (controller.sourceRackWarehouse?.value?.isNotEmpty ?? false)
                ? () async {
              final result = await srcAdapter.browseRacks();
              if (result != null) await srcAdapter.handleRackPicked(result);
            }
                : null,
            accentColor: Colors.purple,
          ),

        // ── Target Rack ───────────────────────────────────────────────────
        // Shown only for SE types that require a destination rack.
        if (controller.showTargetRack)
          SharedRackField(
            key:      const ValueKey('dual_rack_target'),
            c:        tgtAdapter,
            label:    'Target Rack',
            hint:     'Enter or scan target rack ID',
            editMode: true,
            // Target rack has no outbound balance to display; suppress chip
            // by returning null from the override.
            balanceOverride: () => null,
            onPickerTap: controller.itemCode.value.isNotEmpty &&
                (controller.targetRackWarehouse?.value?.isNotEmpty ?? false)
                ? () async {
              final result = await tgtAdapter.browseRacks();
              if (result != null) await tgtAdapter.handleRackPicked(result);
            }
                : null,
            accentColor: Colors.blueGrey,
          ),
      ],
    ));
  }
}
