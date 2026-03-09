import 'package:flutter/material.dart';

/// Enhanced Dashboard Metric Card with improved visual hierarchy
/// 
/// FIXED: Overflow issue by using LayoutBuilder and responsive sizing
class DashboardMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;
  final VoidCallback? onTap;
  final bool isCritical;

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
    final double cardElevation = isCritical ? 6 : 3;
    
    return Card(
      elevation: cardElevation,
      shadowColor: isCritical 
          ? Colors.red.withValues(alpha: 0.4)
          : color.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCritical 
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
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
          // FIXED: Use LayoutBuilder for responsive sizing
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate responsive sizes based on available space
              final availableHeight = constraints.maxHeight;
              final availableWidth = constraints.maxWidth;
              
              // Responsive padding (reduce on smaller cards)
              final cardPadding = availableHeight > 100 ? 16.0 : 12.0;
              
              // Responsive icon size (scale with card height)
              final iconSize = (availableHeight * 0.25).clamp(20.0, 28.0);
              final iconPadding = (iconSize * 0.4).clamp(8.0, 12.0);
              
              // Responsive value font size (scale with card height)
              final valueFontSize = (availableHeight * 0.35).clamp(24.0, 36.0);
              
              // Responsive title font size
              final titleFontSize = (availableHeight * 0.14).clamp(11.0, 13.0);
              
              // Responsive spacing
              final headerValueGap = (availableHeight * 0.12).clamp(8.0, 16.0);
              final valueTitleGap = (availableHeight * 0.06).clamp(4.0, 6.0);
              
              return Padding(
                padding: EdgeInsets.all(cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // CRITICAL: Don't force max height
                  children: [
                    // Header Row: Icon + Trend (fixed height)
                    SizedBox(
                      height: iconSize + (iconPadding * 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon container
                          Container(
                            padding: EdgeInsets.all(iconPadding),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
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
                          
                          // Trend badge (if present)
                          if (trend != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPositiveTrend
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isPositiveTrend
                                      ? Colors.green.shade200
                                      : Colors.red.shade200,
                                  width: 1,
                                ),
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
                                    size: 12,
                                    color: isPositiveTrend
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    trend!.replaceAll('+', ''),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isPositiveTrend
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Flexible spacer
                    SizedBox(height: headerValueGap),
                    
                    // FIXED: Use Expanded to fill remaining space
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Primary metric value - MOST PROMINENT
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                value,
                                style: TextStyle(
                                  fontSize: valueFontSize,
                                  fontWeight: FontWeight.w800,
                                  color: isCritical ? Colors.red.shade700 : Colors.black87,
                                  height: 1.0,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          
                          SizedBox(height: valueTitleGap),
                          
                          // Secondary label - clear but subdued
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: titleFontSize,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}