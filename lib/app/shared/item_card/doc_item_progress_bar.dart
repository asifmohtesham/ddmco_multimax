import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Standardised per-item progress bar shown inside [DocItemCard] when
/// a target quantity is known.
///
/// Used by:
///   PO  — ordered qty vs received qty
///   PR  — receipt row qty vs PO line qty
///   SE  — entry qty vs max qty from POS Upload
///
/// DN and PS pass [targetQty] = null in their [ItemCardData], so
/// [DocItemCard] never instantiates this widget for those DocTypes.
///
/// Colour semantics — all colorScheme tokens:
///   not started (qty == 0)   → track only
///   in progress (0 < qty < target) → cs.primary
///   complete    (qty >= target)    → cs.tertiary
///   over-received (qty > target)   → cs.error
class DocItemProgressBar extends StatelessWidget {
  /// Quantity already processed on this row.
  final double qty;

  /// The reference total this row is being fulfilled against.
  /// Must be > 0; callers are responsible for guarding.
  final double targetQty;

  /// Optional UOM label appended to the progress text, e.g. 'pcs'.
  final String? uom;

  const DocItemProgressBar({
    super.key,
    required this.qty,
    required this.targetQty,
    this.uom,
  }) : assert(targetQty > 0, 'targetQty must be > 0');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final double percent = (qty / targetQty).clamp(0.0, 1.0);
    final bool isComplete  = qty >= targetQty;
    final bool isOver      = qty > targetQty;

    final Color progressColor = isOver
        ? cs.error
        : isComplete
            ? cs.tertiary
            : cs.primary;

    final String uomSuffix = uom != null ? ' $uom' : '';
    final String progressLabel = isComplete
        ? 'Fully received'
        : 'Rcvd: ${NumberFormat('#,##0.##').format(qty)}$uomSuffix'
          ' / ${NumberFormat('#,##0.##').format(targetQty)}$uomSuffix';

    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: progressColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(percent * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: progressColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }
}
