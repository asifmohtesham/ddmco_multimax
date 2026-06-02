import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Contract for any controller that provides a **Target Rack** field.
///
/// Implement this on any DocType item-sheet controller that requires the
/// operator to specify which bin stock is being placed *into*.
///
/// A Manufacture finished-good row only implements [TargetRackDelegate].
/// A Material Transfer row implements both [SourceRackDelegate] and
/// [TargetRackDelegate] via the unified [DualRackDelegate].
abstract interface class TargetRackDelegate {
  TextEditingController get targetRackController;
  RxBool  get isTargetRackValid;
  RxBool  get isValidatingTargetRack;
  RxString get rackError;
  RxString get itemCode;
  TextEditingController get batchController;
  TextEditingController get qtyController;
  RxnString get targetRackWarehouse;  // resolved warehouse for picker scope

  void resetTargetRackValidation();
  Future<void> onTargetRackChanged(String rack);
}