import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doc_summary_row.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/entry_type_card.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/warehouse_picker.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/entry_type_picker.dart';

/// Scrollable Details tab for the Stock Entry form.
/// Step 5 — extracted from StockEntryFormScreen._buildDetailsView().
class DetailsTab extends StatelessWidget {
  final StockEntryFormController controller;
  final StockEntry entry;

  const DetailsTab({
    super.key,
    required this.controller,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        child: Obx(() {
          final type = controller.stockEntryType.value;
          final isMaterialIssue = type == 'Material Issue';
          final isEditable = entry.docstatus == 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntryTypeCard(
                type: type,
                helperText: controller.getTypeHelperText(type),
                fromWarehouse: controller.fromWarehouse.value,
                toWarehouse: controller.toWarehouse.value,
                isEditable: isEditable,
                onTypeTap: () => EntryTypePicker.show(context, controller),
                onFromTap: () => WarehousePicker.show(
                    context, controller, isSource: true),
                onToTap: () => WarehousePicker.show(
                    context, controller, isSource: false),
              ),

              const SizedBox(height: 16),

              DocSectionCard(
                title: 'Reference & Schedule',
                margin: EdgeInsets.zero,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DocPickerField(
                          label: 'Date',
                          value: entry.postingDate,
                          icon: Icons.calendar_today_outlined,
                          trailingIcon: Icons.edit_calendar_outlined,
                          onTap: isEditable
                              ? () => controller.pickPostingDate(context)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DocPickerField(
                          label: 'Time',
                          value:
                              FormattingHelper.formatTime(entry.postingTime),
                          icon: Icons.access_time,
                          onTap: isEditable
                              ? () => controller.pickPostingTime(context)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  if (isMaterialIssue) ...[
                    const SizedBox(height: 12),
                    // System-populated, never user-edited — read-only field.
                    // ValueListenableBuilder (not the Obx) tracks the text so
                    // programmatic updates to the controller still repaint.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable:
                          controller.customReferenceNoController,
                      builder: (context, ref, _) => DocPickerField(
                        label: 'Reference No',
                        icon: Icons.confirmation_number_outlined,
                        value: ref.text,
                        placeholder: '—',
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              DocSectionCard(
                title: 'Summary',
                margin: EdgeInsets.zero,
                children: [
                  DocSummaryRow(
                    label: 'Total Quantity',
                    value:
                        entry.customTotalQty?.toStringAsFixed(2) ?? '0',
                  ),
                  const Divider(),
                  DocSummaryRow(
                    label: 'Total Amount',
                    value: entry.totalAmount.toStringAsFixed(2),
                    isBold: true,
                  ),
                ],
              ),
              const SizedBox(height: 80),
            ],
          );
        }),
      ),
    );
  }
}
