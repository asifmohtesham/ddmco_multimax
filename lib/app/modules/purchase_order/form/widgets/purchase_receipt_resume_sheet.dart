import 'package:flutter/material.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';

/// Bottom sheet shown when a Purchase Order already has open draft Purchase
/// Receipt(s). Lets the user resume one of them or start a fresh receipt.
/// Purely presentational — all behaviour flows through [onResume] / [onCreateNew].
class PurchaseReceiptResumeSheet extends StatelessWidget {
  final List<DraftReceiptSummary> drafts;
  final void Function(String name) onResume;
  final VoidCallback onCreateNew;

  const PurchaseReceiptResumeSheet({
    super.key,
    required this.drafts,
    required this.onResume,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              alignment: Alignment.center,
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                'Draft Receipt Exists',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'This Purchase Order already has an unsubmitted receipt. '
                'Resume it, or start a new one.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 4),
            Divider(height: 1, color: cs.outlineVariant),

            // Draft list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: drafts.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 72,
                  endIndent: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final d = drafts[index];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: const Icon(Icons.edit_document, size: 20),
                    ),
                    title: Text(
                      d.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: d.postingDate.isEmpty
                        ? null
                        : Text(
                            d.postingDate,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                    trailing:
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    onTap: () => onResume(d.name),
                  );
                },
              ),
            ),

            Divider(height: 1, color: cs.outlineVariant),

            // Create-new action
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton.icon(
                onPressed: onCreateNew,
                icon: const Icon(Icons.add),
                label: const Text('Start a new receipt'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
