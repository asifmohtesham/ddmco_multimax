import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/home/home_controller.dart';

/// Enhanced Inventory Health Card with improved visual hierarchy
/// 
/// Changes:
/// - Critical alerts prominently highlighted
/// - Color-coded status system with better contrast
/// - Larger count values for quick scanning
/// - Enhanced movement timeline with visual progression
class InventoryHealthCard extends StatelessWidget {
  final HomeController controller;

  const InventoryHealthCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3, // Enhanced from 2
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0), // Slightly more padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enhanced header with better typography
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Stock Overview',
                  style: TextStyle(
                    fontSize: 17, // Larger
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: 0.3,
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.goToItem,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View Items', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ENHANCED Stock Status Grid with prominence
            Row(
              children: [
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'In Stock',
                    count: 1247,
                    icon: Icons.check_circle,
                    color: Colors.green,
                    importance: StatusImportance.normal,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'Low Stock',
                    count: 34,
                    icon: Icons.warning_amber_rounded,
                    color: Colors.orange,
                    importance: StatusImportance.high, // CRITICAL
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'Out of Stock',
                    count: 12,
                    icon: Icons.error,
                    color: Colors.red,
                    importance: StatusImportance.critical, // CRITICAL
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildStockStatusCard(
                    context,
                    title: 'Expiring Soon',
                    count: 8,
                    icon: Icons.schedule,
                    color: Colors.purple,
                    importance: StatusImportance.high,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(thickness: 1),
            const SizedBox(height: 16),

            // Enhanced section header
            Row(
              children: [
                Icon(Icons.timeline, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 6),
                const Text(
                  'Recent Movements',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            
            // Enhanced movement rows
            _buildMovementRow(
              context,
              type: 'Inward',
              itemCount: 45,
              time: '2 hours ago',
              icon: Icons.arrow_downward,
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            _buildMovementRow(
              context,
              type: 'Outward',
              itemCount: 67,
              time: '4 hours ago',
              icon: Icons.arrow_upward,
              color: Colors.blue,
            ),
            const SizedBox(height: 10),
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
    required StatusImportance importance,
  }) {
    // Enhanced elevation based on importance
    final double elevation = importance == StatusImportance.critical 
        ? 3 
        : importance == StatusImportance.high 
            ? 2 
            : 0;
    
    // Pulsing animation for critical items
    final bool isPulsing = importance == StatusImportance.critical;
    
    return Container(
      padding: const EdgeInsets.all(14), // More padding
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08), // More subtle
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: importance == StatusImportance.critical
              ? color // Solid border for critical
              : color.withValues(alpha: 0.3),
          width: importance == StatusImportance.critical ? 2 : 1,
        ),
        // Critical glow effect
        boxShadow: importance == StatusImportance.critical
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : elevation > 0
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24), // Larger icon
              if (importance != StatusImportance.normal)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: importance == StatusImportance.critical
                        ? Colors.red
                        : Colors.orange,
                    shape: BoxShape.circle,
                    // Pulse effect for critical
                    boxShadow: isPulsing
                        ? [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // ENHANCED: Larger count for prominence
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 26, // INCREASED from 22
              fontWeight: FontWeight.w800,
              color: importance == StatusImportance.critical
                  ? color
                  : color.withValues(alpha: 0.9),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$itemCount items',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ' • ',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
        ],
      ),
    );
  }
}

/// Importance levels for visual hierarchy
enum StatusImportance {
  normal,   // Standard status
  high,     // Needs attention
  critical, // Urgent action required
}