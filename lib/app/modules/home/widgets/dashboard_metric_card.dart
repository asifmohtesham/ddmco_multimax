import 'package:flutter/material.dart';

/// Enhanced Dashboard Metric Card with improved visual hierarchy
/// 
/// Changes:
/// - Larger metric values (36px vs 28px) for prominence
/// - Dynamic elevation based on trend importance
/// - Enhanced color contrast for better readability
/// - Subtle glow effect for critical metrics
/// - Improved spacing ratios (Golden ratio: 1.618)
class DashboardMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;
  final VoidCallback? onTap;
  final bool isCritical; // NEW: Highlights urgent items

  const DashboardMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
    this.onTap,
    this.isCritical = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPositiveTrend = trend?.startsWith('+') ?? true;
    final bool hasNegativeTrend = trend?.startsWith('-') ?? false;
    
    // Enhanced elevation system for hierarchy
    final double cardElevation = isCritical ? 6 : 3; // Critical items elevated
    final double iconSize = 28.0; // Slightly larger for better visibility
    
    return Card(
      elevation: cardElevation,
      shadowColor: isCritical 
          ? Colors.red.withValues(alpha: 0.4) // Red glow for critical
          : color.withValues(alpha: 0.25), // Stronger shadow
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        // Critical items get a colored border
        side: isCritical 
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        // Enhanced haptic feedback
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
          // Subtle gradient background for depth
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: isCritical
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade50.withValues(alpha: 0.3),
                      Colors.white,
                    ],
                  )
                : null,
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header Row: Icon + Trend
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Enhanced icon container with better contrast
                  Container(
                    padding: const EdgeInsets.all(12), // Slightly larger
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15), // More opaque
                      borderRadius: BorderRadius.circular(14),
                      // Subtle inner shadow for depth
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.1),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: iconSize),
                  ),
                  
                  // Enhanced trend badge with glow effect
                  if (trend != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPositiveTrend
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isPositiveTrend
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                          width: 1,
                        ),
                        // Glow effect for negative trends (alerts)
                        boxShadow: hasNegativeTrend
                            ? [
                                BoxShadow(
                                  color: Colors.red.shade200.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositiveTrend
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 14, // Slightly larger
                            color: isPositiveTrend
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trend!.replaceAll('+', ''),
                            style: TextStyle(
                              fontSize: 12, // Slightly larger
                              fontWeight: FontWeight.bold,
                              color: isPositiveTrend
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              letterSpacing: 0.5, // Better readability
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              
              // Golden ratio spacing (16 * 1.618 ≈ 26)
              const SizedBox(height: 16),
              
              // ENHANCED: Primary metric value - MOST PROMINENT
              Text(
                value,
                style: TextStyle(
                  fontSize: 36, // INCREASED from 28px for prominence
                  fontWeight: FontWeight.w800, // Extra bold
                  color: isCritical ? Colors.red.shade700 : Colors.black87,
                  height: 1.1, // Tighter line height
                  letterSpacing: -0.5, // Tighter for large numbers
                ),
              ),
              
              // Optimal spacing
              const SizedBox(height: 6),
              
              // Secondary label - clear but subdued
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700], // Darker for better contrast
                  fontWeight: FontWeight.w600, // Slightly bolder
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}