import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/animated_expand_icon.dart';

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
    final percent = (totalQty > 0) ? (scannedQty / totalQty).clamp(0.0, 1.0) : 0.0;
    final isCompleted = percent >= 1.0;

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
                  color: isCompleted ? Colors.green : Colors.orange.shade700,
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
                  progressColor: isCompleted ? Colors.green : Colors.orange,
                  backgroundColor: Colors.grey.shade300,
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
            child: Container(
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
                              _buildInfoColumn('Required', totalQty.toStringAsFixed(0)),
                              _buildInfoColumn('Scanned', scannedQty.toStringAsFixed(0)),
                              _buildInfoColumn('Rate', rate.toStringAsFixed(2)),
                            ],
                          ),
                        ),
                        ...children,
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
