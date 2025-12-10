import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PerformanceTimelineCard extends StatelessWidget {
  final bool isWeekly;
  final Function(bool) onToggleView;
  final List<TimelinePoint> data;
  final bool isLoading;

  const PerformanceTimelineCard({
    super.key,
    required this.isWeekly,
    required this.onToggleView,
    required this.data,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Items Managed & Fulfilled', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    children: [
                      _buildToggleBtn('Daily', !isWeekly),
                      _buildToggleBtn('Weekly', isWeekly),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Chart Area
            if (isLoading)
              const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()))
            else if (data.isEmpty)
              const SizedBox(height: 150, child: Center(child: Text('No activity data found.', style: TextStyle(color: Colors.grey))))
            else
              SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: data.map((point) => _buildBarColumn(context, point)).toList(),
                ),
              ),

            const SizedBox(height: 16),

            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.blue, 'Delivery'),
                const SizedBox(width: 12),
                _buildLegendItem(Colors.orange, 'Stock Entry'),
                const SizedBox(width: 12),
                _buildLegendItem(Colors.green, 'Receipt'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool isActive) {
    return GestureDetector(
      onTap: () => onToggleView(label == 'Weekly'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.black : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildBarColumn(BuildContext context, TimelinePoint point) {
    // Calculate relative heights (simple stacking)
    // Find max value in dataset to normalize
    double maxTotal = 0;
    for (var p in data) {
      if (p.total > maxTotal) maxTotal = p.total;
    }
    if (maxTotal == 0) maxTotal = 1;

    final double heightFactor = 120.0 / maxTotal; // 140 is max pixel height for bars

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Tooltip or Value
        if (point.total > 0)
          Text(
            point.total.toStringAsFixed(0),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
        const SizedBox(height: 4),

        // Stacked Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            children: [
              if (point.receiptQty > 0)
                Container(width: 12, height: point.receiptQty * heightFactor, color: Colors.green),
              if (point.stockQty > 0)
                Container(width: 12, height: point.stockQty * heightFactor, color: Colors.orange),
              if (point.deliveryQty > 0)
                Container(width: 12, height: point.deliveryQty * heightFactor, color: Colors.blue),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          point.label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        if (point.customerCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Icon(Icons.person, size: 10, color: Theme.of(context).primaryColor),
          ),
      ],
    );
  }
}

class TimelinePoint {
  final String label; // "Mon", "Tue" or "Wk 1"
  final DateTime date;
  final double stockQty;
  final double deliveryQty;
  final double receiptQty;
  final int customerCount;

  TimelinePoint({
    required this.label,
    required this.date,
    this.stockQty = 0,
    this.deliveryQty = 0,
    this.receiptQty = 0,
    this.customerCount = 0,
  });

  double get total => stockQty + deliveryQty + receiptQty;
}