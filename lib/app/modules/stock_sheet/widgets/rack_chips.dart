import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

/// A quantity to at most three decimals, without trailing zeros (`305`,
/// `2.5`, and `0.3` for a sum of `0.1 + 0.2`).
String formatQty(double qty) {
  final rounded = (qty * 1000).roundToDouble() / 1000;
  if (rounded == rounded.truncateToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

String _rackLabel(RackQty r) => '${r.rack ?? 'No rack'} ${formatQty(r.qty)}';

/// The stock line of a review row: a bold total, then wrapping chips with the
/// full rack names (largest first). Three chips at most, then `+n`, which opens
/// the full list; a long-press anywhere on the line opens it too. Out of stock
/// (a total of 0 or less, or a null [stock]: the item has no Stock Balance
/// row) shows a red pill and no chips.
class RackChips extends StatelessWidget {
  const RackChips({super.key, required this.stock});

  final ItemStock? stock;

  static const maxChips = 3;

  @override
  Widget build(BuildContext context) {
    final stock = this.stock;
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (stock == null || stock.outOfStock) {
      final base = AppColors.red500;
      final ink = isDark ? AppColors.red300 : AppColors.red700;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.13),
          border: Border.all(color: base.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          'Out of stock · 0',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      );
    }

    final racks = [...stock.racks]..sort((a, b) => b.qty.compareTo(a.qty));
    final shown = racks.take(maxChips).toList();
    final extra = racks.length - shown.length;

    Widget chip(String text, {VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: s.subtle,
          border: Border.all(color: s.border),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'ShureTechMono',
            fontSize: 12,
            color: s.textMuted,
          ),
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: racks.isEmpty ? null : () => showRackSheet(context, stock),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            formatQty(stock.total),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: s.text,
            ),
          ),
          for (final r in shown) chip(_rackLabel(r)),
          if (extra > 0)
            chip('+$extra', onTap: () => showRackSheet(context, stock)),
        ],
      ),
    );
  }
}

/// Every rack holding stock, in full, in a bottom sheet.
Future<void> showRackSheet(BuildContext context, ItemStock stock) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _RackSheet(stock: stock),
  );
}

class _RackSheet extends StatelessWidget {
  const _RackSheet({required this.stock});

  final ItemStock stock;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final racks = [...stock.racks]..sort((a, b) => b.qty.compareTo(a.qty));
    return Material(
      color: s.fg,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Stock by rack · ${formatQty(stock.total)}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: s.text,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in racks)
                      ListTile(
                        dense: true,
                        title: Text(
                          r.rack ?? 'No rack',
                          style: TextStyle(
                            fontFamily: 'ShureTechMono',
                            color: s.text,
                          ),
                        ),
                        trailing: Text(
                          formatQty(r.qty),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: s.text,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
