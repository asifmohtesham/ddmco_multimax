import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';

/// 'Entry' section card on the Stock Entry Details tab: entry type picker
/// (with helper description) plus the FROM / TO warehouse fields.
///
/// A dumb presentation widget — the caller (DetailsTab) reads the reactive
/// values inside its own `Obx` and passes them in, which keeps this widget
/// testable without a live [StockEntryFormController].
///
/// Warehouse applicability follows the entry type: Material Issue uses FROM
/// only, Material Receipt uses TO only, transfers use both. A field that does
/// not apply (or before a type is chosen) renders read-only with an 'N/A'
/// placeholder.
class EntryTypeCard extends StatelessWidget {
  final String type;
  final String helperText;
  final String? fromWarehouse;
  final String? toWarehouse;
  final bool isEditable;
  final VoidCallback? onTypeTap;
  final VoidCallback? onFromTap;
  final VoidCallback? onToTap;

  const EntryTypeCard({
    super.key,
    required this.type,
    required this.helperText,
    required this.fromWarehouse,
    required this.toWarehouse,
    required this.isEditable,
    this.onTypeTap,
    this.onFromTap,
    this.onToTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMaterialIssue = type == 'Material Issue';
    final isMaterialReceipt = type == 'Material Receipt';
    final isMaterialTransfer = type == 'Material Transfer' ||
        type == 'Material Transfer for Manufacture';
    final fromActive = isMaterialIssue || isMaterialTransfer;
    final toActive = isMaterialReceipt || isMaterialTransfer;

    return DocSectionCard(
      title: 'Entry',
      margin: EdgeInsets.zero,
      children: [
        DocPickerField(
          label: 'Entry Type',
          icon: Icons.category_outlined,
          value: type,
          placeholder: 'Select Type',
          helperText: helperText,
          onTap: isEditable ? onTypeTap : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DocPickerField(
                label: 'From Warehouse',
                icon: Icons.warehouse_outlined,
                value: fromWarehouse,
                placeholder: fromActive ? 'Select Source' : 'N/A',
                trailingIcon: Icons.chevron_right,
                onTap: (isEditable && fromActive) ? onFromTap : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DocPickerField(
                label: 'To Warehouse',
                icon: Icons.warehouse_outlined,
                value: toWarehouse,
                placeholder: toActive ? 'Select Target' : 'N/A',
                trailingIcon: Icons.chevron_right,
                onTap: (isEditable && toActive) ? onToTap : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
