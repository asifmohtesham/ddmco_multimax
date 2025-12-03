import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

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
    final percent = (totalQty > 0) ? (scannedQty / totalQty) : 0.0;
    final isCompleted = percent >= 1.0;
    final cleanPercent = percent > 1.0 ? 1.0 : percent;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: isCompleted ? Colors.green.shade400 : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            title: Text('$serialNo: $itemName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text(
              isCompleted ? 'Completed' : 'Pending',
              style: TextStyle(
                color: isCompleted ? Colors.green : Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularPercentIndicator(
                  radius: 24.0,
                  lineWidth: 5.0,
                  percent: cleanPercent,
                  center: Text(
                    '${(cleanPercent * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  progressColor: isCompleted ? Colors.green : Colors.orange,
                  backgroundColor: Colors.grey.shade300,
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Container(
              color: Colors.black.withValues(alpha: .02),
              child: !isExpanded
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildInfoColumn('Required', totalQty.toStringAsFixed(0)),
                              _buildInfoColumn('Scanned', scannedQty.toStringAsFixed(0)),
                              _buildInfoColumn('Remaining', (totalQty - scannedQty).toStringAsFixed(0)),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
