import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/utils/app_constants.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/global_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/selling/sales_order/form/sales_order_form_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/form/sales_order_item_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';

/// Item bottom-sheet for Sales Order.
///
/// Uses [UniversalItemFormSheet] (same as PO/PR/SE/DN) for UI/UX parity.
/// SO-specific fields — Delivery Date, Rate (server-priced via
/// `get_item_details`, always editable), UOM/Warehouse, and the running
/// "Estimated Amount" tile — are passed via [customFields].
///
/// The controller is registered under [kSoItemSheetTag] by the parent.
///
/// ## Spacing contract
///
/// [GlobalItemFormSheet._formChildren()] wraps every element of [customFields]
/// in `Padding(bottom: 20)` automatically. Do NOT add manual [SizedBox]
/// spacers between custom fields.
class SalesOrderItemFormSheet extends StatelessWidget {
  final ScrollController? scrollController;

  const SalesOrderItemFormSheet({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<SalesOrderItemFormController>(tag: kSoItemSheetTag);
    final formCtrl = Get.find<SalesOrderFormController>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Obx wraps the entire sheet so isSaveEnabled (from formCtrl.isEditable)
    // re-evaluates reactively whenever the parent document changes.
    return Obx(() => UniversalItemFormSheet(
          controller: ctrl,
          scrollController: scrollController,
          isSaveEnabled: formCtrl.isEditable,
          onSubmit: ctrl.submit,
          onScan: null,
          customFields: [
            // ── Details error banner ─────────────────────────────────────
            Obx(() => InlineBanner(
                  visible: ctrl.detailsError.value != null,
                  message: ctrl.detailsError.value ?? '',
                  type: BannerType.warning,
                )),

            // ── Delivery Date ────────────────────────────────────────────
            Obx(() => GlobalItemFormSheet.buildInputGroup(
                  label: 'Delivery Date',
                  color: dark ? AppColors.orange300 : AppColors.orange700,
                  child: TextFormField(
                    controller: ctrl.deliveryDateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      errorText: ctrl.rowErrors['delivery_date'],
                    ),
                    onTap: () async {
                      final transactionDate =
                          formCtrl.so.value?.transactionDate;
                      final firstDate =
                          DateTime.tryParse(transactionDate ?? '') ??
                              DateTime.now();
                      final rawInitial =
                          DateTime.tryParse(ctrl.deliveryDateController.text);
                      // A stale row date earlier than the (possibly since
                      // edited) header transactionDate would otherwise trip
                      // showDatePicker's initialDate >= firstDate assertion.
                      final initialDate =
                          (rawInitial != null && !rawInitial.isBefore(firstDate))
                              ? rawInitial
                              : firstDate;
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initialDate,
                        firstDate: firstDate,
                        lastDate: firstDate.add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        ctrl.deliveryDateController.text =
                            FormattingHelper.formatDate(picked);
                        ctrl.validateSheet();
                      }
                    },
                  ),
                )),

            // ── Rate ─────────────────────────────────────────────────────
            GlobalItemFormSheet.buildInputGroup(
              label: 'Rate',
              color: context.scheme.textMuted,
              child: Obx(() => TextFormField(
                    key: const ValueKey('so_rate_field'),
                    controller: ctrl.rateController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixIcon: ctrl.isFetchingDetails.value
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.sell_outlined, size: 18),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      helperText: ctrl.priceListRate.value > 0
                          ? 'Price list: ${FormattingHelper.formatAmount(ctrl.priceListRate.value)}'
                          : null,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      if (double.tryParse(value) == null) return 'Invalid number';
                      return null;
                    },
                  )),
            ),

            // ── UOM + Warehouse ──────────────────────────────────────────
            Obx(() => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DocPickerField(
                        label: 'UOM',
                        icon: Icons.straighten_outlined,
                        value: ctrl.uom.value,
                        placeholder: '-',
                        // Changing UOM needs a fresh conversion factor from
                        // the server; out of scope for this sheet.
                        onTap: null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DocPickerField(
                        label: 'Warehouse',
                        icon: Icons.warehouse_outlined,
                        value: ctrl.warehouse.value,
                        onTap: formCtrl.isEditable
                            ? () => showLinkSearchSheet(
                                  doctype: 'Warehouse',
                                  title: 'Warehouse',
                                  onSelected: (w) {
                                    ctrl.warehouse.value = w;
                                    ctrl.validateSheet();
                                  },
                                )
                            : null,
                      ),
                    ),
                  ],
                )),

            // ── Estimated Amount tile ────────────────────────────────────
            Obx(() {
              final blueInk =
                  dark ? AppColors.blue300 : AppColors.blue700;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.blue500.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estimated Amount',
                          style: TextStyle(
                              color: blueInk, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${FormattingHelper.getCurrencySymbol(formCtrl.so.value?.currency ?? 'AED')} '
                          '${FormattingHelper.formatAmount(ctrl.sheetAmount)}',
                          style: TextStyle(
                              color: blueInk,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Final total and VAT are calculated on save',
                      style: TextStyle(fontSize: 11, color: blueInk),
                    ),
                  ],
                ),
              );
            }),
          ],
        ));
  }
}
