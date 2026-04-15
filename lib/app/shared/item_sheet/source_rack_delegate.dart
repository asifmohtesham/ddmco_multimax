import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Contract for any controller that provides a **Source Rack** field.
///
/// Implement this on any DocType item-sheet controller that requires the
/// operator to specify which bin stock is being drawn *from*.
///
/// ## Warehouse resolution order
/// [sourceRackWarehouse] is the resolved warehouse used to scope the rack
/// picker. Controllers compute this from item-level overrides → derived
/// warehouse → header-level fromWarehouse, in that priority order.
abstract interface class SourceRackDelegate {
  TextEditingController get sourceRackController;
  RxBool  get isSourceRackValid;
  RxBool  get isValidatingSourceRack;
  RxDouble get rackBalance;           // balance at the selected source rack
  RxBool  get isLoadingRackBalance;
  RxString get rackError;
  RxString get itemCode;
  TextEditingController get batchController;
  TextEditingController get qtyController;
  RxnString get sourceRackWarehouse;  // resolved warehouse for picker scope

  void resetSourceRackValidation();
  Future<void> onSourceRackChanged(String rack);
}