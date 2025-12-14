import 'package:flutter/material.dart';

class InfoBlock extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? valueColor;

  const InfoBlock({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.icon,
    this.backgroundColor,
    this.iconColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surfaceContainerHigh.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                    icon,
                    size: 14,
                    color: iconColor ?? colorScheme.onSurfaceVariant
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          child ?? Text(
            value ?? '-',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}