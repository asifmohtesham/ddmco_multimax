import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/entry_type_card.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/compact_field.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/summary_row.dart';
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
          final type = controller.selectedStockEntryType.value;
          final isMaterialIssue = type == 'Material Issue';
          final isEditable = entry.docstatus == 0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntryTypeCard(
                controller: controller,
                isEditable: isEditable,
                onTypeTap: () => EntryTypePicker.show(context, controller),
                onFromTap: () => WarehousePicker.show(
                    context, controller, isSource: true),
                onToTap: () => WarehousePicker.show(
                    context, controller, isSource: false),
              ),

              const Text(
                'Reference & Schedule',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CompactField(
                      label: 'Date',
                      value: entry.postingDate,
                      icon: Icons.calendar_today,
                      onTap: isEditable
                          ? () => controller.pickPostingDate(context)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CompactField(
                      label: 'Time',
                      value: entry.postingTime,
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
                TextFormField(
                  controller: controller.customReferenceNoController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Reference No',
                    hintText: 'Reference number',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    prefixIcon:
                        const Icon(Icons.confirmation_number_outlined),
                    suffixIcon: const Icon(Icons.lock_outline,
                        size: 16, color: Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    SummaryRow(
                      label: 'Total Quantity',
                      value:
                          entry.customTotalQty?.toStringAsFixed(2) ?? '0',
                    ),
                    const Divider(),
                    SummaryRow(
                      label: 'Total Amount',
                      value: entry.totalAmount.toStringAsFixed(2),
                      isBold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          );
        }),
      ),
    );
  }
}
