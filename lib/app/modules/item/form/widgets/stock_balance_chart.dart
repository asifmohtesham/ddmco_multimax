import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:intl/intl.dart';

class StockBalanceChart extends StatelessWidget {
  final List<WarehouseStock> stockLevels;

  const StockBalanceChart({super.key, required this.stockLevels});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (stockLevels.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.3))
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, color: cs.onSurfaceVariant, size: 32),
            const SizedBox(height: 8),
            Text('No stock distribution data', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    double maxQty = 0;
    for (var stock in stockLevels) {
      if (stock.quantity > maxQty) maxQty = stock.quantity;
    }
    if (maxQty == 0) maxQty = 1;

    final sortedStocks = List<WarehouseStock>.from(stockLevels)
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          children: sortedStocks.where((stock) => stock.quantity > 0).map((stock) => _buildStockCard(context, stock, maxQty)).toList(),
        ),
      ],
    );
  }

  Widget _buildStockCard(BuildContext context, WarehouseStock stock, double maxQty) {
    final cs = Theme.of(context).colorScheme;
    final double qty = stock.quantity < 0 ? 0 : stock.quantity;
    final double percentage = (qty / maxQty).clamp(0.0, 1.0);

    final String displayName = (stock.rack != null && stock.rack!.isNotEmpty)
        ? stock.rack!
        : stock.warehouse;

    final String label = (stock.rack != null && stock.rack!.isNotEmpty)
        ? 'Rack'
        : 'Warehouse';

    final Color barColor = percentage > 0.2 ? cs.tertiary : cs.secondary;

    return Container(
      width: (MediaQuery.of(context).size.width / 1) - 18,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                label == 'Rack' ? Icons.shelves : Icons.store,
                size: 14,
                color: cs.onSurfaceVariant,
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

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                NumberFormat.compact().format(stock.quantity),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Qty',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Stack(
            children: [
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.8),
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
