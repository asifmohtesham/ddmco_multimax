import 'package:flutter/material.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';

class StockBalanceChart extends StatelessWidget {
  final List<WarehouseStock> stockLevels;

  const StockBalanceChart({super.key, required this.stockLevels});

  @override
  Widget build(BuildContext context) {
    if (stockLevels.isEmpty) {
      return const SizedBox.shrink();
    }

    // 1. Calculate Maximum Quantity for Scaling
    double maxQty = 0;
    for (var stock in stockLevels) {
      if (stock.quantity > maxQty) maxQty = stock.quantity;
    }

    // Avoid division by zero
    if (maxQty == 0) maxQty = 1;

    // Sort stocks by quantity descending for better visualization
    final sortedStocks = List<WarehouseStock>.from(stockLevels)
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    // Limit to top 5-7 to prevent overcrowding if there are many warehouses
    // (Optional: show all inside a scrollable view if needed, but dashboard usually implies summary)
    final displayStocks = sortedStocks.length > 8
        ? sortedStocks.sublist(0, 8)
        : sortedStocks;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Stock Distribution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                if (sortedStocks.length > 8)
                  Text('Top 8 of ${sortedStocks.length}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            ...displayStocks.map((stock) => _buildBarRow(context, stock, maxQty)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarRow(BuildContext context, WarehouseStock stock, double maxQty) {
    // Calculate percentage width
    // Ensure negative stocks don't break the layout (though rare in visualization context)
    final double qty = stock.quantity < 0 ? 0 : stock.quantity;
    final double percentage = (qty / maxQty).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Warehouse Name (Left Axis)
          SizedBox(
            width: 100,
            child: Text(
              stock.warehouse,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // The Bar
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Background track
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Foreground Bar
                    FractionallySizedBox(
                      widthFactor: percentage,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getBarColor(percentage),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(width: 12),

          // Value Label
          SizedBox(
            width: 50,
            child: Text(
              stock.quantity.toStringAsFixed(2), // Assuming max 2 decimals
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Color _getBarColor(double percentage) {
    // Gradient logic or fixed colors based on intensity
    if (percentage > 0.8) return Colors.green.shade600;
    if (percentage > 0.5) return Colors.blue.shade500;
    if (percentage > 0.2) return Colors.blue.shade300;
    return Colors.grey.shade400;
  }
}