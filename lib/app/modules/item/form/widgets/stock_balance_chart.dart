import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:intl/intl.dart';

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
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inventory_2_outlined, color: Colors.grey, size: 32),
            SizedBox(height: 8),
            Text('No stock distribution data', style: TextStyle(color: Colors.grey)),
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

    // Display all, assuming the list isn't massive (if massive, consider limiting or 'See More')
    final displayStocks = sortedStocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title isn't inside the card anymore to allow the Wrap to span full width cleanly
        // If the parent handles the title, we can remove this or keep it subtle.
        // For this widget, we'll assume it renders just the grid/content.

        Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          children: displayStocks.where((stock) => stock.quantity > 0).map((stock) => _buildStockCard(context, stock, maxQty)).toList(),
        ),
      ],
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

    // final Color primaryColor = percentage > 0.2 ? Theme.of(context).primaryColor : Colors.orange;
    final Color primaryColor = percentage > 0.2 ? Colors.green : Colors.orange;

    return Container(
      // Responsive width: ~2 cards per row on mobile
      width: (MediaQuery.of(context).size.width / 1) - 18,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
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
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Qty',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Visual Bar
          Stack(
            children: [
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(3),
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