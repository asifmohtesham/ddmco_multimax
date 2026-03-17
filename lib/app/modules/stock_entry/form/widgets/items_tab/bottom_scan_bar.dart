import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// Pinned scan-input bar shown at the bottom of the Items tab.
/// Step 6 & 9 — extracted from screen, Container() replaced with SizedBox.shrink().
class BottomScanBar extends StatelessWidget {
  final StockEntryFormController controller;

  const BottomScanBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.stockEntry.value?.docstatus != 0) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, -4),
            )
          ],
        ),
        padding: const EdgeInsets.only(bottom: 0),
        child: Obx(() => BarcodeInputWidget(
              onScan: (code) => controller.scanBarcode(code),
              isLoading: controller.isScanning.value,
              controller: controller.barcodeController,
              activeRoute: AppRoutes.STOCK_ENTRY_FORM,
              hintText: 'Scan Item / Batch ...',
            )),
      ),
    );
  }
}
