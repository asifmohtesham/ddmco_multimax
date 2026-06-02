import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/source_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/target_rack_delegate.dart';

/// Combined contract for controllers that provide both a source and a
/// target rack (e.g. Material Transfer, Transfer for Manufacture).
///
/// [selectedStockEntryType] has been removed. Visibility is now declared
/// by the controller via [showSourceRack] / [showTargetRack] rather than
/// inferred by the widget from an SE-type string.
abstract interface class DualRackDelegate
    implements SourceRackDelegate, TargetRackDelegate {
  // Warehouse derivation labels (used by DerivedWarehouseLabel widget).
  RxnString get itemSourceWarehouse;
  RxnString get derivedSourceWarehouse;
  RxnString get itemTargetWarehouse;
  RxnString get derivedTargetWarehouse;
  RxnString get selectedFromWarehouse;
  RxnString get selectedToWarehouse;
  // Overrides sourceRackWarehouse / targetRackWarehouse from parent delegates.
  // Kept here so DerivedWarehouseLabel can still render for SE use-cases.

  /// Whether the source rack field should render for the current item/context.
  ///
  /// Controllers override this getter reactively. For Manufacture SE:
  ///   - `isFinishedItem == true`  → returns `false` (FG row is output-only)
  ///   - `isFinishedItem == false` → returns `true`  (raw material row)
  ///
  /// The getter is called inside an [Obx] in [SharedDualRackSection.build]
  /// so the field appears/disappears reactively when [isFinishedItem] changes.
  bool get showSourceRack;

  /// Whether the target rack field should render for the current item/context.
  bool get showTargetRack;
}
