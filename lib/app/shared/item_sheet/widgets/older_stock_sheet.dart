import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/batch_age_provider.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';

/// Text shown beside the batch field when a scan is refused.
const String kOlderStockMessage = 'Older stock must ship first.';

/// Opens [OlderStockSheet]. Completes with `true` when the user chose to scan
/// the older batch, otherwise `false`/null.
Future<bool?> showOlderStockSheet(
  BuildContext context, {
  required String itemLabel,
  required String refusedBatch,
  required List<OlderBatch> older,
  required Future<List<RackStockLine>> Function() loadRacks,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OlderStockSheet(
        itemLabel: itemLabel,
        refusedBatch: refusedBatch,
        older: older,
        loadRacks: loadRacks,
      ),
    );

/// Explains why a batch was refused: older stock of the item is still
/// available and has to ship first. Lists that stock and the racks the item
/// is kept in, so the floor user can go and find it. There is no override —
/// a supervisor makes the exception in Desk.
class OlderStockSheet extends StatefulWidget {
  const OlderStockSheet({
    super.key,
    required this.itemLabel,
    required this.refusedBatch,
    required this.older,
    required this.loadRacks,
  });

  final String itemLabel;
  final String refusedBatch;

  /// Oldest first.
  final List<OlderBatch> older;

  /// Fetches the racks the item is kept in. Called once, when the sheet opens.
  final Future<List<RackStockLine>> Function() loadRacks;

  static const int maxBatchesShown = 3;
  static const int maxRacksShown = 8;

  @override
  State<OlderStockSheet> createState() => _OlderStockSheetState();
}

class _OlderStockSheetState extends State<OlderStockSheet> {
  late final Future<List<RackStockLine>> _racks = widget.loadRacks();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.scheme;
    final isDark = theme.brightness == Brightness.dark;
    final alert = isDark ? AppColors.red300 : AppColors.red700;
    final media = MediaQuery.of(context);

    final shown = widget.older.take(OlderStockSheet.maxBatchesShown).toList();
    final hidden = widget.older.length - shown.length;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        // Keep the action clear of the system navigation bar.
        padding: EdgeInsets.only(bottom: media.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.inventory_outlined, color: alert, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Older stock must ship first',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (widget.itemLabel.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.itemLabel,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.textMuted),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Batch '),
                            TextSpan(
                              text: widget.refusedBatch,
                              style: const TextStyle(
                                fontFamily: 'ShureTechMono',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(
                              text: ' cannot be used yet. Older stock of this '
                                  'item is still available and has to be '
                                  'shipped first.',
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(
                        shown.length == 1
                            ? 'Ship this batch first'
                            : 'Ship these batches first, oldest at the top',
                      ),
                      const SizedBox(height: 8),
                      for (final batch in shown)
                        _OlderBatchTile(batch: batch, alert: alert),
                      if (hidden > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text(
                            '+ $hidden more older '
                            '${hidden == 1 ? 'batch' : 'batches'}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.textMuted),
                          ),
                        ),
                      const SizedBox(height: 14),
                      const _SectionLabel('This item is stored in'),
                      const SizedBox(height: 8),
                      FutureBuilder<List<RackStockLine>>(
                        future: _racks,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const _RackNote(
                              key: ValueKey('older_stock_racks_loading'),
                              text: 'Looking up racks…',
                              loading: true,
                            );
                          }
                          if (snapshot.hasError) {
                            return const _RackNote(
                              key: ValueKey('older_stock_racks_error'),
                              text: 'Rack information is not available '
                                  'right now.',
                            );
                          }
                          final racks = snapshot.data ?? const [];
                          if (racks.isEmpty) {
                            return const _RackNote(
                              key: ValueKey('older_stock_racks_empty'),
                              text: 'No rack is recorded for this item.',
                            );
                          }
                          final visible = racks
                              .take(OlderStockSheet.maxRacksShown)
                              .toList();
                          final more = racks.length - visible.length;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final rack in visible) _RackTile(rack: rack),
                              if (more > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '+ $more more '
                                    '${more == 1 ? 'rack' : 'racks'}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: scheme.textMuted),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Racks show where the item is kept. The '
                                  'older batch may be in any of them.',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: scheme.textMuted),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: FilledButton.icon(
                key: const ValueKey('older_stock_scan_older'),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: const Text('Scan older batch'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                'Need this batch? Ask your supervisor to add it in Desk.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.scheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
      );
}

class _OlderBatchTile extends StatelessWidget {
  const _OlderBatchTile({required this.batch, required this.alert});

  final OlderBatch batch;
  final Color alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.scheme;
    final date = DateFormat('dd MMM yyyy').format(batch.age.date);
    final warehouses = batch.qtyByWarehouse.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      key: ValueKey('older_batch_${batch.batchNo}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        // Status tint over the surface — the StatusPill convention.
        color: AppColors.red500.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red500.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  batch.batchNo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'ShureTechMono',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${formatOlderStockQty(batch.availableQty)} available',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: alert, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            batch.age.fromReceipt ? 'Received $date' : 'Dated $date',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.textMuted),
          ),
          const SizedBox(height: 4),
          for (final entry in warehouses)
            Text(
              '${entry.key}  ·  ${formatOlderStockQty(entry.value)}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RackTile extends StatelessWidget {
  const _RackTile({required this.rack});
  final RackStockLine rack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.scheme;
    final hasRack = rack.rack.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.shelves, size: 18, color: scheme.textSubtle),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasRack ? rack.rack : 'No rack recorded',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: hasRack ? 'ShureTechMono' : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  rack.warehouse,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.textMuted),
                ),
              ],
            ),
          ),
          Text(
            formatOlderStockQty(rack.qty),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RackNote extends StatelessWidget {
  const _RackNote({super.key, required this.text, this.loading = false});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (loading) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.scheme.textMuted),
            ),
          ),
        ],
      );
}

/// Whole quantities without decimals, others with up to two.
String formatOlderStockQty(double qty) => qty.truncateToDouble() == qty
    ? NumberFormat.decimalPattern().format(qty)
    : NumberFormat('#,##0.##').format(qty);

/// "View older stock" link shown under the batch field after a refusal, so the
/// explanation stays one tap away once the sheet has been dismissed.
class OlderStockLink extends StatelessWidget {
  const OlderStockLink({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.red300 : AppColors.red700;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('older_stock_link'),
        onPressed: onTap,
        icon: Icon(Icons.info_outline, size: 16, color: color),
        label: Text('View older stock', style: TextStyle(color: color)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
