import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/warehouse_column.dart';

/// Gradient card showing the current Stock Entry type, a helper description,
/// and the FROM → TO warehouse selector row.
/// Step 4 — extracted from StockEntryFormScreen._buildDetailsView().
class EntryTypeCard extends StatelessWidget {
  final StockEntryFormController controller;
  final bool isEditable;
  final VoidCallback? onTypeTap;
  final VoidCallback? onFromTap;
  final VoidCallback? onToTap;

  const EntryTypeCard({
    super.key,
    required this.controller,
    required this.isEditable,
    this.onTypeTap,
    this.onFromTap,
    this.onToTap,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final type = controller.selectedStockEntryType.value;
      final isMaterialIssue = type == 'Material Issue';
      final isMaterialReceipt = type == 'Material Receipt';
      final isMaterialTransfer =
          type == 'Material Transfer' || type == 'Material Transfer for Manufacture';

      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.deepOrange.shade50,
              Colors.lightGreen.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          children: [
            // ── Entry Type row ──
            InkWell(
              onTap: isEditable ? onTypeTap : null,
              child: Row(
                children: [
                  Icon(Icons.category, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    type,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (isEditable)
                    const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                controller.getTypeHelperText(type),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.blueGrey.shade700),
              ),
            ),
            const Divider(height: 24),

            // ── FROM → TO warehouse row ──
            Row(
              children: [
                WarehouseColumn(
                  label: 'FROM',
                  selectedValue: controller.selectedFromWarehouse.value,
                  fallbackText:
                      isMaterialReceipt ? 'N/A' : 'Select Source',
                  isActive: isMaterialIssue || isMaterialTransfer,
                  isEditable: isEditable,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  labelAlignment: MainAxisAlignment.start,
                  onTap: onFromTap,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: Colors.blue.shade300),
                ),
                WarehouseColumn(
                  label: 'TO',
                  selectedValue: controller.selectedToWarehouse.value,
                  fallbackText:
                      isMaterialIssue ? 'N/A' : 'Select Target',
                  isActive: isMaterialReceipt || isMaterialTransfer,
                  isEditable: isEditable,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  labelAlignment: MainAxisAlignment.end,
                  onTap: onToTap,
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
