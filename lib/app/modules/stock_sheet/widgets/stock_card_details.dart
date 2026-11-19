import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/ageing_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

/// A quantity to at most three decimals, without trailing zeros (`305`,
/// `2.5`, and `0.3` for a sum of `0.1 + 0.2`).
String formatQty(double qty) {
  final rounded = (qty * 1000).roundToDouble() / 1000;
  if (rounded == rounded.truncateToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

/// The open card of a review row: the item's Rack-Wise Stock Balance (from
/// the stock check already made) and its Stock Ageing ([ageing], fetched on
/// the first opening). On screen only; none of it reaches the file.
class StockCardDetails extends StatelessWidget {
  const StockCardDetails({
    super.key,
    required this.stock,
    required this.ageing,
    required this.onRetry,
  });

  /// Null when the item has no Stock Balance row: out of stock.
  final ItemStock? stock;

  /// Null when nothing has been asked for (an out-of-stock item never is).
  final AgeingState? ageing;

  /// Asks for the Stock Ageing again after it failed.
  final VoidCallback onRetry;

  static const _mono = 'ShureTechMono';

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final stock = this.stock;
    final inStock = stock != null && !stock.outOfStock;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(6, 8, 4, 2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context, 'Rack-Wise Stock Balance'),
          const SizedBox(height: 4),
          if (inStock)
            _racks(context, stock)
          else
            _quiet(context, 'No stock in Finished Goods - KA.'),
          const SizedBox(height: 10),
          _heading(context, 'Stock Ageing'),
          const SizedBox(height: 4),
          if (!inStock)
            _quiet(context, 'Not in the Stock Ageing report: nothing in stock.')
          else
            _ageing(context),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: context.scheme.textMuted,
    ),
  );

  Widget _quiet(BuildContext context, String text) => Text(
    text,
    style: TextStyle(fontSize: 13, color: context.scheme.textMuted),
  );

  /// One line per rack, largest first (as [ItemStock.racks] is); a total
  /// line when there is more than one.
  Widget _racks(BuildContext context, ItemStock stock) {
    final s = context.scheme;
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: s.textMuted,
    );
    final value = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: s.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget line(Widget left, Widget right) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          right,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line(Text('Rack', style: head), Text('Balance Qty', style: head)),
        for (final r in stock.racks)
          line(
            Text(
              r.rack ?? 'No rack',
              style: r.rack == null
                  ? TextStyle(fontSize: 13, color: s.text)
                  : TextStyle(fontFamily: _mono, fontSize: 12, color: s.text),
            ),
            Text(formatQty(r.qty), style: value),
          ),
        if (stock.racks.length > 1)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: s.border)),
            ),
            child: line(
              const SizedBox.shrink(),
              Text(
                formatQty(stock.total),
                style: value.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  Widget _ageing(BuildContext context) {
    final s = context.scheme;
    final ageing = this.ageing;
    switch (ageing?.status) {
      case null:
      case AgeingStatus.loading:
        return Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: s.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            _quiet(context, 'Fetching Stock Ageing…'),
          ],
        );
      case AgeingStatus.missing:
        return _quiet(context, 'Not in the Stock Ageing report.');
      case AgeingStatus.denied:
        return _quiet(context, "You don't have access to Stock Ageing.");
      case AgeingStatus.failed:
        return Row(
          children: [
            Expanded(child: _quiet(context, "Couldn't load Stock Ageing.")),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        );
      case AgeingStatus.ready:
        final rows = ageing!.rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              if (row.warehouse != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    row.warehouse!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: s.text,
                    ),
                  ),
                ),
              _AgeingFigures(row: row),
            ],
          ],
        );
    }
  }
}

/// One Stock Ageing row: the four figures in two columns, labelled as the
/// report titles them, then each age bucket with its quantity and a bar
/// scaled to the largest bucket.
class _AgeingFigures extends StatelessWidget {
  const _AgeingFigures({required this.row});

  final ItemAgeing row;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final label = TextStyle(fontSize: 13, color: s.textMuted);
    final value = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: s.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget pair(String name, String figure) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(name, style: label)),
          const SizedBox(width: 8),
          Text(figure, style: value),
        ],
      ),
    );
    final most = row.buckets.fold<double>(0, (m, b) => math.max(m, b.qty));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  pair(row.availableQtyLabel, formatQty(row.availableQty)),
                  pair(row.earliestLabel, '${row.earliest}'),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  pair(row.averageAgeLabel, formatQty(row.averageAge)),
                  pair(row.latestLabel, '${row.latest}'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final b in row.buckets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text('Age (${b.label})', style: label),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: most > 0
                            ? (b.qty / most).clamp(0.0, 1.0)
                            : 0,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: s.primary.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(formatQty(b.qty), style: value),
              ],
            ),
          ),
      ],
    );
  }
}
