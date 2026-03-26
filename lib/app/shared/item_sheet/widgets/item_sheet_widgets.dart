/// Barrel export for all shared item-sheet widgets.
///
/// Import this single file instead of four separate paths:
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
export 'shared_batch_field.dart';
export 'shared_rack_field.dart';
export 'shared_serial_field.dart';
export 'shared_dual_rack_section.dart';
