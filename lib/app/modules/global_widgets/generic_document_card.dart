import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class GenericDocumentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final List<Widget> stats;
  final bool isExpanded;
  final bool isLoadingDetails;
  final VoidCallback onTap;
  final Widget? expandedContent;

  const GenericDocumentCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.stats,
    required this.isExpanded,
    required this.onTap,
    this.isLoadingDetails = false,
    this.expandedContent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: status),
                ],
              ),

              const SizedBox(height: 16),

              // Stats Row
              Row(
                children: [
                  ...stats.expand((widget) => [widget, const SizedBox(width: 16)]),
                  const Spacer(),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(Icons.expand_more, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),

              // Expanded Content
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: !isExpanded
                    ? const SizedBox.shrink()
                    : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: colorScheme.outlineVariant, height: 1),
                    ),
                    if (isLoadingDetails)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (expandedContent != null)
                      expandedContent!
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Static helper to build icon stats consistently across screens
  static Widget buildIconStat(BuildContext context, IconData icon, String text) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}