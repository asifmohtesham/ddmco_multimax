import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';

class ItemGroupCard extends StatelessWidget {
  final bool isExpanded;
  final int serialNo;
  final String itemName;
  final double rate;
  final double totalQty;
  final double scannedQty;
  final VoidCallback onToggle;
  final List<Widget> children;

  /// ISO currency code (e.g. 'AED', 'USD').  Displayed as a symbol
  /// prefix on the Rate chip so the value is unambiguous.
  final String? currency;

  /// Remaining qty available for this serial under the POS cap.
  /// When non-null and finite, a 'Remaining' stat chip is rendered.
  /// Colour: green when 0 (fully consumed), amber when ≤ 20 % of
  /// totalQty, otherwise primary.
  final double? remainingQty;

  /// Override label for the totalQty chip (default: 'Required').
  final String totalQtyLabel;

  /// Override label for the scannedQty chip (default: 'Scanned').
  final String scannedQtyLabel;

  /// When non-null, a 'Packed Qty' stat chip is rendered after the scanned chip.
  final double? packedQty;

  /// External-system demand qty for this serial (the top of the fulfilment
  /// funnel: POS Upload Qty ≥ DN Qty ≥ Packed). When non-null, a demand chip
  /// is rendered first as an at-a-glance reminder of the quantity to meet.
  /// Coloured amber when below [totalQty] (under-supply vs the DN commitment),
  /// otherwise primary.
  final double? posUploadQty;

  /// Override label for the [posUploadQty] chip (default: 'POS Upload Qty').
  final String posUploadQtyLabel;

  /// Unit suffix for all quantity chips (default: 'pcs'). Callers should pass
  /// the document's stock UOM so the figures match the source document.
  final String unit;

  const ItemGroupCard({
    super.key,
    required this.isExpanded,
    required this.serialNo,
    required this.itemName,
    required this.rate,
    required this.totalQty,
    required this.scannedQty,
    required this.onToggle,
    required this.children,
    this.currency,
    this.remainingQty,
    this.totalQtyLabel = 'Required',
    this.scannedQtyLabel = 'Scanned',
    this.packedQty,
    this.posUploadQty,
    this.posUploadQtyLabel = 'POS Upload Qty',
    this.unit = 'pcs',
  });

  /// Returns a short display symbol for common ISO codes;
  /// falls back to the code itself so nothing is ever blank.
  static String _currencySymbol(String? code) {
    switch (code?.toUpperCase()) {
      case 'AED': return 'AED';
      case 'USD': return r'$';
      case 'EUR': return '\u20ac';
      case 'GBP': return '\u00a3';
      case 'SAR': return 'SAR';
      case 'KWD': return 'KWD';
      case 'QAR': return 'QAR';
      default:    return code ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final percent =
        (totalQty > 0) ? (scannedQty / totalQty).clamp(0.0, 1.0) : 0.0;
    final isCompleted = percent >= 1.0;


    // Semantic colour alias — resolved once, used for rail, border,
    // status label, progress ring, and Scanned stat chip.
    final completionColor =
        isCompleted ? Colors.green.shade600 : cs.primary;

    final currSymbol  = _currencySymbol(currency);
    final rateDisplay = currSymbol.isEmpty
        ? NumberFormat('#,##0.00').format(rate)
        : '$currSymbol ${NumberFormat('#,##0.00').format(rate)}';

    // ── POS Upload (demand) chip colour ────────────────────────────
    // Amber when external demand is below the DN commitment (an unexpected
    // under-supply that must not be silently trusted), else primary so it
    // reads as the headline demand figure.
    final Color posUploadColor = (posUploadQty != null && posUploadQty! < totalQty)
        ? Colors.amber.shade700
        : cs.primary;

    // ── Remaining chip colour logic ────────────────────────────────
    // resolved here so it sits near the other semantic colours above.
    Color? remainingColor;
    String? remainingDisplay;
    if (remainingQty != null && remainingQty!.isFinite) {
      remainingDisplay =
          '${NumberFormat('#,##0.##').format(remainingQty!)} $unit';
      if (remainingQty! <= 0) {
        remainingColor = Colors.green.shade600;   // fully consumed
      } else if (totalQty > 0 && remainingQty! / totalQty <= 0.2) {
        remainingColor = Colors.amber.shade700;   // ≤ 20 % left → warn
      } else {
        remainingColor = cs.primary;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isCompleted ? Colors.green.shade600 : cs.outlineVariant,
          width: 1,
        ),
      ),
      // IntrinsicHeight lets the rail Container stretch to the full
      // height of the card regardless of whether it is collapsed or expanded.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Completion rail ──────────────────────────────────────────────
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: completionColor,
                borderRadius: const BorderRadius.only(
                  topLeft:    Radius.circular(11),
                  bottomLeft: Radius.circular(11),
                ),
              ),
            ),

            // ── Card content ─────────────────────────────────────────────────
            Expanded(
              child: Column(
                children: [
                  // ── Group header (always visible) ────────────────────────
                  InkWell(
                    onTap: onToggle,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$serialNo: $itemName',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    fontFamily: 'ShureTechMono',
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isCompleted ? 'Completed' : 'Pending',
                                  style: TextStyle(
                                    color: completionColor,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Circular progress + chevron
                          CircularPercentIndicator(
                            radius: 22.0,
                            lineWidth: 4.0,
                            percent: percent,
                            center: Text(
                              '${(percent * 100).toInt()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: cs.onSurface,
                              ),
                            ),
                            progressColor: completionColor,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                          const SizedBox(width: 4),
                          AnimatedExpandIcon(isExpanded: isExpanded),
                        ],
                      ),
                    ),
                  ),

                  // ── Stats row — always visible ───────────────────────────
                  // IG-1: Wrap replaces Row so that a 4th chip (Remaining)
                  // flows to a second run instead of overflowing the card
                  // Column's tight height constraint from IntrinsicHeight.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (posUploadQty != null)
                          _buildStatChip(
                            context: context,
                            label: posUploadQtyLabel,
                            value: '${NumberFormat('#,##0.##').format(posUploadQty!)} $unit',
                            valueColor: posUploadColor,
                          ),
                        _buildStatChip(
                          context: context,
                          label: totalQtyLabel,
                          value: '${NumberFormat('#,##0.##').format(totalQty)} $unit',
                          valueColor: cs.onSurfaceVariant,
                        ),
                        _buildStatChip(
                          context: context,
                          label: scannedQtyLabel,
                          value: '${NumberFormat('#,##0.##').format(scannedQty)} $unit',
                          valueColor: completionColor,
                        ),
                        if (packedQty != null)
                          _buildStatChip(
                            context: context,
                            label: 'Packed Qty',
                            value: '${NumberFormat('#,##0.##').format(packedQty!)} $unit',
                            valueColor: cs.tertiary,
                          ),
                        _buildStatChip(
                          context: context,
                          label: 'Rate',
                          value: rateDisplay,
                          valueColor: cs.secondary,
                        ),
                        if (remainingDisplay != null)
                          _buildStatChip(
                            context: context,
                            label: 'Remaining',
                            value: remainingDisplay,
                            valueColor: remainingColor!,
                          ),
                      ],
                    ),
                  ),

                  // ── Collapsible child items ─────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: !isExpanded
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              Divider(
                                height: 1,
                                indent: 12,
                                endIndent: 16,
                                color: cs.outlineVariant,
                              ),
                              ...children,
                              const SizedBox(height: 8),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required BuildContext context,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'ShureTechMono',
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
