import 'package:flutter/material.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';

/// Bottom sheet that lets the operator link a Purchase Receipt item to a valid,
/// OPEN Purchase Order Item row when more than one open line matches. Fully
/// received lines are never offered — the app does not over-receive.
///
/// Pops the chosen [PoLinkCandidate] (or null when dismissed).
class PurchaseReceiptPoLinkSheet extends StatelessWidget {
  final String itemCode;
  final List<PoLinkCandidate> candidates;

  const PurchaseReceiptPoLinkSheet({
    super.key,
    required this.itemCode,
    required this.candidates,
  });

  String _fmt(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28.0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Link $itemCode to an open PO line',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHigh,
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: candidates.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link_off,
                                  size: 56, color: cs.outlineVariant),
                              const SizedBox(height: 16),
                              Text(
                                'No open Purchase Order line',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: candidates.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        itemBuilder: (context, index) {
                          final c = candidates[index];
                          final remaining = (c.item.qty - c.item.receivedQty)
                              .clamp(0, double.infinity)
                              .toDouble();
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              foregroundColor: cs.onPrimaryContainer,
                              child: const Icon(Icons.inventory_2_outlined,
                                  size: 20),
                            ),
                            title: Text(
                              '${c.poName} • ${c.item.name}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: cs.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'Ordered ${_fmt(c.item.qty)} • '
                              'Received ${_fmt(c.item.receivedQty)} • '
                              'Remaining ${_fmt(remaining)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: Icon(Icons.chevron_right,
                                color: cs.onSurfaceVariant),
                            onTap: () => Navigator.of(context).pop(c),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
