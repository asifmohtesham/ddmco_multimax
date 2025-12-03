import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

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

    return ExpansionTile(
      // margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: isCompleted ? Colors.green : Colors.transparent,
          width: 1.5,
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$serialNo. $itemName', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Nos $totalQty x $rate', style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: LinearPercentIndicator(
              percent: percent > 1.0 ? 1.0 : percent,
              lineHeight: 18.0,
              center: Text(
                '${scannedQty.toStringAsFixed(0)} / ${totalQty.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.grey.shade300,
              progressColor: isCompleted ? Colors.green : Colors.orange,
              barRadius: const Radius.circular(8),
            ),
          ),
        ],
      ),
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Container(
            child: !isExpanded
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ...children,
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
