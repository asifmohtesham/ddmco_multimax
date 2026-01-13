import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:intl/intl.dart';
import 'package:multimax/theme/frappe_theme.dart';

class StockBalanceChart extends StatelessWidget {
  final List<WarehouseStock> stockLevels;

  const StockBalanceChart({super.key, required this.stockLevels});

  @override
  Widget build(BuildContext context) {
    // 1. Handle Empty State
    if (stockLevels.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(FrappeTheme.radius),
            border: Border.all(color: Colors.grey.shade200)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inventory_2_outlined, color: FrappeTheme.textLabel, size: 32),
            SizedBox(height: 8),
            Text('No stock distribution data', style: TextStyle(color: FrappeTheme.textLabel)),
          ],
        ),
      );
    }

    // 2. Calculate Maximum Quantity for Scaling
    double maxQty = 0;
    for (var stock in stockLevels) {
      if (stock.quantity > maxQty) maxQty = stock.quantity;
    }
    if (maxQty == 0) maxQty = 1;

    // Sort stocks by quantity descending
    final sortedStocks = List<WarehouseStock>.from(stockLevels)
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    // Limit to top 6 to prevent UI clutter on mobile
    final displayStocks = sortedStocks.take(6).toList();

    return Wrap(
      spacing: 12.0,
      runSpacing: 12.0,
      children: displayStocks.where((stock) => stock.quantity > 0).map((stock) => _buildStockCard(context, stock, maxQty)).toList(),
    );
  }

  Widget _buildStockCard(BuildContext context, WarehouseStock stock, double maxQty) {
    final double qty = stock.quantity < 0 ? 0 : stock.quantity;
    final double percentage = (qty / maxQty).clamp(0.0, 1.0);

    // Determine Display Name (Rack preferred, else Warehouse)
    final String displayName = (stock.rack != null && stock.rack!.isNotEmpty)
        ? stock.rack!
        : stock.warehouse;

    final String label = (stock.rack != null && stock.rack!.isNotEmpty)
        ? 'Rack'
        : 'Warehouse';

    final Color primaryColor = percentage > 0.2 ? FrappeTheme.primary : Colors.orange;

    return Container(
      // Responsive width: ~2 cards per row on mobile (taking padding into account)
      width: (MediaQuery.of(context).size.width / 2) - 24,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                label == 'Rack' ? Icons.shelves : Icons.store,
                size: 14,
                color: FrappeTheme.textLabel,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: FrappeTheme.textBody),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quantity
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                NumberFormat.compact().format(stock.quantity),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: FrappeTheme.textBody,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'Qty',
                style: TextStyle(fontSize: 10, color: FrappeTheme.textLabel),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Visual Bar
          Stack(
            children: [
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: FrappeTheme.surface,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}