import 'dart:async';

// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

import 'item_sheet_controller_base.dart';

/// Suggests an in-warehouse rack when the operator enters a positive quantity.
mixin AutoFillRackMixin on ItemSheetControllerBase {
  Map<String, double> get rackStockMap;

  VoidCallback? _autoFillQtyListener;
  int _autoFillGeneration = 0;
  final isFindingAutoFillRack = false.obs;

  TextEditingController get autoFillRackController => rackController;

  void onAutoFillRackSelected(String rack) => validateRack(rack);

  void initAutoFillListener() {
    _autoFillQtyListener = _onQtyChangedForAutoFill;
    qtyController.addListener(_autoFillQtyListener!);
  }

  void disposeAutoFillListener() {
    if (_autoFillQtyListener != null) {
      qtyController.removeListener(_autoFillQtyListener!);
      _autoFillQtyListener = null;
    }
  }

  void _onQtyChangedForAutoFill() {
    if (!isAddMode || autoFillRackController.text.isNotEmpty) return;
    final qty = double.tryParse(qtyController.text) ?? 0.0;
    if (qty <= 0 || rackStockMap.isEmpty) return;
    unawaited(autoFillRackForQty(qty));
  }

  Future<void> autoFillRackForQty(double qty) async {
    final warehouse = resolvedWarehouse;
    final stock = Map<String, double>.of(rackStockMap);
    if (!isAddMode ||
        autoFillRackController.text.isNotEmpty ||
        warehouse == null ||
        warehouse.isEmpty ||
        stock.isEmpty ||
        !Get.isRegistered<ApiProvider>()) {
      return;
    }

    final generation = ++_autoFillGeneration;
    final item = itemCode.value;
    final batch = batchController.text;
    final quantityText = qtyController.text;
    final rackController = autoFillRackController;
    isFindingAutoFillRack.value = true;
    try {
      final racks = await Get.find<ApiProvider>().getRacksByWarehouse(
        warehouse,
      );
      if (isClosed ||
          generation != _autoFillGeneration ||
          resolvedWarehouse != warehouse ||
          itemCode.value != item ||
          batchController.text != batch ||
          qtyController.text != quantityText ||
          rackController.text.isNotEmpty) {
        return;
      }

      final candidates = racks.where(stock.containsKey).toList()
        ..sort((a, b) => stock[b]!.compareTo(stock[a]!));
      if (candidates.isEmpty) return;
      final best = candidates.first;
      if (stock[best]! < qty) {
        GlobalSnackbar.warning(
          message:
              'Insufficient stock in rack "$best" (available: ${stock[best]}). '
              'Please verify before saving.',
        );
      }
      disposeAutoFillListener();
      rackController.text = best;
      onAutoFillRackSelected(best);
    } finally {
      if (!isClosed && generation == _autoFillGeneration) {
        isFindingAutoFillRack.value = false;
      }
    }
  }
}
