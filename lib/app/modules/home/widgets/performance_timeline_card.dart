import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PerformanceTimelineCard extends StatelessWidget {
  final String viewMode; // 'Hourly', 'Daily', 'Weekly'
  final Function(String) onToggleView;
  final List<TimelinePoint> data;
  final bool isLoading;

  // Daily/Hourly Date
  final DateTime? selectedDate;
  final Function(DateTime)? onDateChanged;

  // Weekly Range
  final DateTimeRange? selectedRange;
  final Function(DateTimeRange)? onRangeChanged;

  const PerformanceTimelineCard({
    super.key,
    required this.viewMode,
    required this.onToggleView,
    required this.data,
    required this.isLoading,
    this.selectedDate,
    this.onDateChanged,
    this.selectedRange,
    this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Toggle & Date Picker
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Performance',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            'Items Managed & Fulfilled',
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (viewMode == 'Weekly' && selectedRange != null)
                      _buildRangePicker(context)
                    else if (selectedDate != null)
                      _buildDatePicker(context),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    children: [
                      _buildToggleBtn(context, 'Hourly', viewMode == 'Hourly'),
                      _buildToggleBtn(context, 'Daily', viewMode == 'Daily'),
                      _buildToggleBtn(context, 'Weekly', viewMode == 'Weekly'),
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
              SizedBox(height: 150, child: Center(child: Text('No activity data found.', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)))))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  height: 180,
                  width: data.length > 7 ? data.length * 50.0 : MediaQuery.of(context).size.width - 64,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: data.map((point) => _buildBarColumn(context, point)).toList(),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(context, Colors.blue, 'Delivery'),
                const SizedBox(width: 12),
                _buildLegendItem(context, Colors.orange, 'Stock Entry'),
                const SizedBox(width: 12),
                _buildLegendItem(context, Colors.green, 'Receipt'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate!,
          firstDate: DateTime(2023),
          lastDate: DateTime.now(),
        );
        if (picked != null && onDateChanged != null) {
          onDateChanged!(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                DateFormat('d MMM yyyy').format(selectedDate!),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildRangePicker(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2023),
          lastDate: DateTime.now(),
          initialDateRange: selectedRange,
        );
        if (picked != null && onRangeChanged != null) {
          onRangeChanged!(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range, size: 14, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${DateFormat('d MMM').format(selectedRange!.start)} - ${DateFormat('d MMM').format(selectedRange!.end)}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleBtn(BuildContext context, String label, bool isActive) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => onToggleView(label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive ? [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 2)] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildBarColumn(BuildContext context, TimelinePoint point) {
    final cs = Theme.of(context).colorScheme;
    double maxTotal = 0;
    for (var p in data) {
      if (p.total > maxTotal) maxTotal = p.total;
    }
    if (maxTotal == 0) maxTotal = 1;

    final double heightFactor = 120.0 / maxTotal;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (point.total > 0)
          Text(
            NumberFormat.compact().format(point.total),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurface.withValues(alpha: 0.54)),
          ),
        const SizedBox(height: 4),
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
          style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}

class TimelinePoint {
  final String label;
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
