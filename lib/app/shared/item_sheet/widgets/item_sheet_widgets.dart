/// Barrel export for all shared item-sheet widgets.
///
/// Available widgets / adapters:
///   - [SharedBatchField]
///   - [SharedRackField]               — single rack (simple + edit modes),
///                                       BalanceChip + Browse Rack included
///   - [SharedDualRackSection]         — SE dual rack; renders two
///                                       [SharedRackField] instances via
///                                       [SourceRackFieldAdapter] /
///                                       [TargetRackFieldAdapter]
///   - [SourceRackFieldAdapter]        — bridges [DualRackDelegate] source-side
///                                       to [RackFieldWithBrowseDelegate]
///   - [TargetRackFieldAdapter]        — bridges [DualRackDelegate] target-side
///                                       to [RackFieldWithBrowseDelegate]
///   - [SharedQtyField]
///   - [QtyCapBadge]
///   - [SharedInvoiceSerialNumberField]
///   - [ValidatedRackField]
///   - [ValidatedBatchField]
///   - [BrowseBatchButton]
///
/// Removed in Commit 4 (SE rack regression fix):
///   - SharedSourceRackField  (deleted — replaced by SharedRackField + adapter)
///   - SharedTargetRackField  (deleted — replaced by SharedRackField + adapter)
export 'shared_batch_field.dart';
export 'shared_rack_field.dart';
export 'shared_qty_field.dart';
export 'qty_cap_badge.dart';
export 'shared_invoice_serial_number_field.dart';
export 'shared_dual_rack_section.dart';
export 'validated_rack_field.dart';
export 'validated_batch_field.dart';
export 'browse_batch_button.dart';
// Adapters — exported so callers that build custom dual-rack UIs can
// instantiate adapters directly without importing dual_rack_adapters.dart.
export 'package:multimax/app/shared/item_sheet/dual_rack_adapters.dart';
