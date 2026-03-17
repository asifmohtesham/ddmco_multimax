import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Step 3 — replaces the two identical warehouse-label Obx blocks.
/// Priority cascade: itemWarehouse → derivedWarehouse → headerWarehouse.
/// Renders nothing when no warehouse is resolved.
class DerivedWarehouseLabel extends StatelessWidget {
  final RxnString itemWarehouse;
  final RxnString derivedWarehouse;
  final RxnString headerWarehouse;

  const DerivedWarehouseLabel({
    super.key,
    required this.itemWarehouse,
    required this.derivedWarehouse,
    required this.headerWarehouse,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final itemWh = itemWarehouse.value;
      final derivedWh = derivedWarehouse.value;
      final headerWh = headerWarehouse.value;

      String? text;
      if (itemWh != null && itemWh.isNotEmpty) {
        text = 'Warehouse: $itemWh (auto from rack)';
      } else if (derivedWh != null && derivedWh.isNotEmpty) {
        text = 'Warehouse: $derivedWh (auto from rack)';
      } else if (headerWh != null && headerWh.isNotEmpty) {
        text = 'Warehouse: $headerWh (from header)';
      }

      if (text == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      );
    });
  }
}
