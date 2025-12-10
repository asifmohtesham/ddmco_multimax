import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/item_model.dart';

class StockBalanceChart extends StatelessWidget {
  final List<WarehouseStock> stockLevels;

  const StockBalanceChart({super.key, required this.stockLevels});

  @override
  Widget build(BuildContext context) {
    // 1. Handle Empty State
    if (stockLevels.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.bar_chart, color: Colors.grey, size: 40),
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

    final displayStocks = sortedStocks.length > 5
        // ? sortedStocks.sublist(0, 5)
        ? sortedStocks
        : sortedStocks;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Distribution by Rack', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
            ...displayStocks.map((stock) => _buildBarRow(context, stock, maxQty)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarRow(BuildContext context, WarehouseStock stock, double maxQty) {
    final double qty = stock.quantity < 0 ? 0 : stock.quantity;
    final double percentage = (qty / maxQty).clamp(0.0, 1.0);
    log(stock.rack.toString());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          // Warehouse Abbreviation or Name
          SizedBox(
            width: 80,
            child: Text(
              stock.rack ?? stock.warehouse,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Bar
          Expanded(
            child: Stack(
              children: [
                Container(height: 8, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4))),
                FractionallySizedBox(
                  widthFactor: percentage,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: percentage > 0.5 ? Colors.blue : Colors.blue.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              stock.quantity.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}