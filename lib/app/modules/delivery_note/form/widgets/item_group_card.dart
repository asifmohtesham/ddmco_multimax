import 'package:flutter/material.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (totalQty > 0) ? (scannedQty / totalQty).clamp(0.0, 1.0) : 0.0;
    final isCompleted = percent >= 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isCompleted ? cs.tertiary : cs.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            title: Text(
              '$serialNo: $itemName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                isCompleted ? 'Completed' : 'Pending',
                style: TextStyle(
                  color: isCompleted ? cs.tertiary : cs.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularPercentIndicator(
                  radius: 22.0,
                  lineWidth: 4.0,
                  percent: percent,
                  center: Text(
                    '${(percent * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  progressColor: isCompleted ? cs.tertiary : cs.secondary,
                  backgroundColor: cs.outlineVariant,
                ),
                const SizedBox(width: 8),
                AnimatedExpandIcon(isExpanded: isExpanded),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !isExpanded
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoColumn(context, 'Required', totalQty.toStringAsFixed(0)),
                            _buildInfoColumn(context, 'Scanned', scannedQty.toStringAsFixed(0)),
                            _buildInfoColumn(context, 'Rate', rate.toStringAsFixed(2)),
                          ],
                        ),
                      ),
                      ...children,
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(BuildContext context, String title, String value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontFamily: 'ShureTechMono',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
