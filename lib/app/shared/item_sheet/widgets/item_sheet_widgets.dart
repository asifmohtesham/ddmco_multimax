/// Barrel export for all shared item-sheet widgets.
///
/// Import this single file instead of individual paths:
///
/// ```dart
/// import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';
/// ```
///
/// Available widgets:
///   - [SharedBatchField]      -- batch no input (simple + edit modes)
///   - [SharedRackField]       -- single rack input (simple + edit modes)
///   - [SharedSerialField]     -- invoice serial number input
///   - [SharedDualRackSection] -- SE dual source+target rack section
///   - [ValidatedRackField]    -- primitive validated rack field (plain-param,
///                                controller-free; moved from stock_entry
///                                module in Commit 1 of RackFieldWithBrowseDelegate)
///   - [ValidatedBatchField]   -- primitive validated batch field (plain-param,
///                                controller-free; extracted in Commit 6 of
///                                BatchNoFieldWithBrowseDelegate refactor)
///   - [BrowseBatchButton]     -- conditional 'Browse Batches' text button
///                                rendered below the batch input field
export 'shared_batch_field.dart';
export 'shared_rack_field.dart';
export 'shared_serial_field.dart';
export 'shared_dual_rack_section.dart';
export 'validated_rack_field.dart';
export 'validated_batch_field.dart';
export 'browse_batch_button.dart';
