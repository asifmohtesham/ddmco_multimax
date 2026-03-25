import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/purchase_order/form/controllers/purchase_order_item_form_controller.dart';
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/data/utils/app_constants.dart';

/// Item bottom-sheet for Purchase Order.
///
/// Uses [UniversalItemFormSheet] (same as PR/SE/DN) for full UI/UX parity.
/// PO-specific fields — Rate, Reqd By Date, and the running Amount tile —
/// are passed via [customFields].
///
/// The controller is registered under [kPoItemSheetTag] by the parent.
///
/// The entire [UniversalItemFormSheet] is wrapped in an [Obx] so that
/// [isSaveEnabled] — derived from [PurchaseOrderFormController.isEditable] —
/// re-evaluates reactively whenever [purchaseOrder] changes (e.g. after a
/// save/submit that alters docstatus).
class PurchaseOrderItemFormSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const PurchaseOrderItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final ctrl     = Get.find<PurchaseOrderItemFormController>(tag: kPoItemSheetTag);
    final formCtrl = Get.find<PurchaseOrderFormController>();

    // Obx wraps the entire sheet so that isSaveEnabled — read from
    // formCtrl.isEditable — is re-evaluated whenever purchaseOrder changes.
    return Obx(() => UniversalItemFormSheet(
      controller:       ctrl,
      scrollController: scrollController,
      // isEditable reads purchaseOrder.value?.docstatus == 0 reactively
      // because we are inside an Obx scope.
      isSaveEnabled:    formCtrl.isEditable,
      onSubmit: () async {
        await ctrl.submit();
      },
      onScan: null,
      customFields: [
        // ── Reqd By Date ────────────────────────────────────────────────────
        GlobalItemFormSheet.buildInputGroup(
          label: 'Reqd by Date',
          color: Colors.orange,
          child: TextFormField(
            controller: ctrl.scheduleDateController,
            readOnly: true,
            decoration: const InputDecoration(
              prefixIcon:     Icon(Icons.calendar_today, size: 18),
              border:         OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate:   DateTime.now(),
                lastDate:    DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                ctrl.scheduleDateController.text =
                    DateFormat('yyyy-MM-dd').format(picked);
              }
            },
            validator: (value) =>
                value == null || value.isEmpty ? 'Required' : null,
          ),
        ),

        const SizedBox(height: 16),

        // ── Rate ──────────────────────────────────────────────────────────
        GlobalItemFormSheet.buildInputGroup(
          label: 'Rate',
          color: Colors.grey,
          child: TextFormField(
            key:          const ValueKey('po_rate_field'),
            controller:   ctrl.rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixIcon:     Icon(Icons.attach_money, size: 18),
              border:         OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Required';
              if (double.tryParse(value) == null) return 'Invalid number';
              return null;
            },
          ),
        ),

        const SizedBox(height: 16),

        // ── Running Amount tile ──────────────────────────────────────────
        Obx(() => Container(
          padding:    const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Amount',
                style: TextStyle(
                    color:      Colors.blue.shade900,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${FormattingHelper.getCurrencySymbol(formCtrl.purchaseOrder.value?.currency ?? 'AED')} '
                '${NumberFormat('#,##0.00').format(ctrl.sheetAmount)}',
                style: TextStyle(
                    color:      Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize:   16),
              ),
            ],
          ),
        )),
      ],
    ));
  }
}
