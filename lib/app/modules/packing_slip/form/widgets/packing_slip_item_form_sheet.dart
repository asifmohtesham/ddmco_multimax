// packing_slip_item_form_sheet.dart
//
// Step-4: This file is now a thin stub.
//
// The sheet is opened by PackingSlipFormController._openItemSheet() which
// inlines UniversalItemFormSheet directly inside a DraggableScrollableSheet.
// Nothing in the app needs to import the old PackingSlipItemFormSheet class
// after this commit; the export below keeps existing imports from breaking
// during the transition (they are removed in step-6).
//
// _BatchDisplayTile is extracted here so the customFields list built in
// _buildCustomFields() is clean and independently testable.

import 'package:flutter/material.dart';
export 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';

/// Read-only display tile for a batch number, rendered as a custom field
/// inside UniversalItemFormSheet.
///
/// Uses Theme.of(context) directly (no workaround needed since it is a
/// proper StatelessWidget).
class BatchDisplayTile extends StatelessWidget {
  final String batchNo;

  const BatchDisplayTile({super.key, required this.batchNo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              'Batch No',
              style: TextStyle(
                color:      Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize:   12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              batchNo,
              style: TextStyle(
                fontFamily: 'ShureTechMono',
                fontWeight: FontWeight.w600,
                fontSize:   14,
                color:      Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
