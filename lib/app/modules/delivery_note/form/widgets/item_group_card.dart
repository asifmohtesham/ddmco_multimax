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
  });

  /// Returns a short display symbol for common ISO codes;
  /// falls back to the code itself so nothing is ever blank.
  static String _currencySymbol(String? code) {
    switch (code?.toUpperCase()) {
      case 'AED': return 'AED';
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'SAR': return 'SAR';
      case 'KWD': return 'KWD';
      case 'QAR': return 'QAR';
      default:    return code ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent =
        (totalQty > 0) ? (scannedQty / totalQty).clamp(0.0, 1.0) : 0.0;
    final isCompleted = percent >= 1.0;

    final currSymbol  = _currencySymbol(currency);
    final rateDisplay = currSymbol.isEmpty
        ? NumberFormat('#,##0.00').format(rate)
        : '$currSymbol ${NumberFormat('#,##0.00').format(rate)}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isCompleted ? Colors.green.shade400 : Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // ── Group header (always visible) ────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$serialNo: $itemName',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isCompleted ? 'Completed' : 'Pending',
                          style: TextStyle(
                            color: isCompleted
                                ? Colors.green
                                : Colors.orange.shade700,
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
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    progressColor:
                        isCompleted ? Colors.green : Colors.orange,
                    backgroundColor: Colors.grey.shade300,
                  ),
                  const SizedBox(width: 4),
                  AnimatedExpandIcon(isExpanded: isExpanded),
                ],
              ),
            ),
          ),

          // ── Stats row — always visible ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                _buildStatChip(
                  label: 'Required',
                  value: '${NumberFormat('#,##0.##').format(totalQty)} pcs',
                  color: Colors.grey,
                ),
                const SizedBox(width: 12),
                _buildStatChip(
                  label: 'Scanned',
                  value: '${NumberFormat('#,##0.##').format(scannedQty)} pcs',
                  color: isCompleted ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 12),
                _buildStatChip(
                  label: 'Rate',
                  value: rateDisplay,
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ),

          // ── Collapsible child items ───────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !isExpanded
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ...children,
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'ShureTechMono',
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
