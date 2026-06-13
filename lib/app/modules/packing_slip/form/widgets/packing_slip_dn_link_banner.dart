import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_dn_reference_resolver.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Items-tab indicator of Delivery Note reference validity.
///
/// * [DnRefStatus.checking]    → nothing (DN still loading).
/// * [DnRefStatus.allLinked]   → slim green confirmation chip.
/// * [DnRefStatus.hasUnlinked] → amber banner listing orphan rows with a
///   Resolve action (re-match + save) and per-row Remove.
class PackingSlipDnLinkBanner extends StatelessWidget {
  const PackingSlipDnLinkBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PackingSlipFormController>();
    return Obx(() {
      switch (controller.dnRefStatus) {
        case DnRefStatus.checking:
          return const SizedBox.shrink();
        case DnRefStatus.allLinked:
          return _allLinkedChip();
        case DnRefStatus.hasUnlinked:
          return _unlinkedBanner(controller);
      }
    });
  }

  Widget _allLinkedChip() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              'All items linked to Delivery Note',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade900),
            ),
          ],
        ),
      );

  Widget _unlinkedBanner(PackingSlipFormController controller) {
    final orphans = controller.unlinkedItems;
    final canEdit = controller.packingSlip.value?.docstatus == 0;
    final isSaving = controller.isSaving.value;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${orphans.length} packed item(s) aren\'t linked to the '
                  'Delivery Note — they will block submission in ERPNext.',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed:
                    isSaving ? null : controller.resolveDnReferencesAndSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Resolve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const Divider(height: 16),
            ...orphans.map((o) => _orphanTile(controller, o, canEdit)),
          ],
        ],
      ),
    );
  }

  Widget _orphanTile(
    PackingSlipFormController controller,
    PackingSlipItem item,
    bool canEdit,
  ) {
    final serial = item.customInvoiceSerialNumber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.itemCode}  ·  ${item.qty} ${item.uom}'
              '${serial != null && serial != '0' ? '  ·  #$serial' : ''}',
              style: const TextStyle(fontSize: 12, fontFamily: 'ShureTechMono'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canEdit)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 20, color: Colors.red.shade400),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: const EdgeInsets.all(8),
              tooltip: 'Remove',
              onPressed: () => controller.deleteItem(item),
            ),
        ],
      ),
    );
  }
}
