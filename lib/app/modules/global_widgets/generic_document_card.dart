import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class GenericDocumentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? status; // Made nullable
  final List<Widget> stats;
  final bool isExpanded;
  final bool isLoadingDetails;
  final VoidCallback onTap;
  final Widget? expandedContent;
  final Widget? leading; // Added support for leading image/icon

  const GenericDocumentCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.status,
    this.stats = const [],
    required this.isExpanded,
    required this.onTap,
    this.isLoadingDetails = false,
    this.expandedContent,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 0,
      color: colorScheme.surfaceContainer, // M3 Surface
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Optional Leading Widget (Image/Icon)
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 16),
                  ],

                  // Title & Subtitle
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'ShureTechMono',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Status Pill
                  if (status != null) ...[
                    const SizedBox(width: 8),
                    StatusPill(status: status!),
                  ],
                ],
              ),

              if (stats.isNotEmpty || isExpanded)
                const SizedBox(height: 16),

              // Stats Row
              if (stats.isNotEmpty)
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
                )
              else if (isExpanded)
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(Icons.expand_more, color: colorScheme.onSurfaceVariant),
                  ),
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

  // Static helper to build icon stats consistently
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