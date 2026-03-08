import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/home/home_controller.dart';

class InventoryHealthCard extends StatelessWidget {
  final HomeController controller;

  const InventoryHealthCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Simulated inventory metrics (replace with real API calls)
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Stock Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.goToItem,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View Items'),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stock Status Grid
            Row(
              children: [
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'In Stock',
                    count: 1247,
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'Low Stock',
                    count: 34,
                    icon: Icons.warning,
                    color: Colors.orange,
                    hasAlert: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'Out of Stock',
                    count: 12,
                    icon: Icons.error,
                    color: Colors.red,
                    hasAlert: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'Expiring Soon',
                    count: 8,
                    icon: Icons.schedule,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Recent Stock Movements
            const Text(
              'Recent Movements',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildMovementRow(
              context,
              type: 'Inward',
              itemCount: 45,
              time: '2 hours ago',
              icon: Icons.arrow_downward,
              color: Colors.green,
            ),
            const SizedBox(height: 8),
            _buildMovementRow(
              context,
              type: 'Outward',
              itemCount: 67,
              time: '4 hours ago',
              icon: Icons.arrow_upward,
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildMovementRow(
              context,
              type: 'Transfer',
              itemCount: 23,
              time: '5 hours ago',
              icon: Icons.swap_horiz,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockStatusCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    bool hasAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              if (hasAlert)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementRow(
    BuildContext context, {
    required String type,
    required int itemCount,
    required String time,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '$itemCount items • $time',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
        ],
      ),
    );
  }
}