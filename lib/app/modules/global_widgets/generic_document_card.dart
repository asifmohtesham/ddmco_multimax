import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class GenericDocumentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? status;
  final List<Widget> stats;
  final bool isExpanded;
  final bool isLoadingDetails;
  final VoidCallback onTap;
  final Widget? expandedContent;
  final Widget? leading;

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

  // ---------------------------------------------------------------------------
  // Frappe / ERPNext canonical status colours.
  // Matches the colour system used in StatusPill:
  //   Draft      → Red     (#E54D4D)
  //   Submitted  → Green   (#36A564)
  //   Cancelled  → Grey    (#5A6673)
  //   default    → transparent (no accent)
  // ---------------------------------------------------------------------------
  static Color _statusAccentColor(String? status) {
    switch (status) {
      case 'Submitted':
      case 'Active':
      case 'Completed':
      case 'Paid':
        return const Color(0xFF36A564); // Frappe success green
      case 'Draft':
      case 'Cancelled':
      case 'Rejected':
        return status == 'Draft'
            ? const Color(0xFFE54D4D)  // Frappe danger red
            : const Color(0xFF5A6673); // Frappe grey
      case 'Pending':
      case 'In Progress':
      case 'Open':
        return const Color(0xFFFFA00A); // Frappe warning orange
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = _statusAccentColor(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ----------------------------------------------------------------
              // Left-edge Frappe status accent bar — 4px wide, full card height.
              // Lets users scan document state while scrolling without reading
              // the StatusPill text.
              // Hidden (transparent) when status is unknown/default.
              // ----------------------------------------------------------------
              if (accentColor != Colors.transparent)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),

              // Main card content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 16),
                          ],
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
                          if (status != null) ...[
                            const SizedBox(width: 8),
                            StatusPill(status: status!),
                          ],
                        ],
                      ),

                      if (stats.isNotEmpty || isExpanded)
                        const SizedBox(height: 16),

                      // Stats Row + Expand chevron
                      if (stats.isNotEmpty)
                        Row(
                          children: [
                            ...stats.expand(
                                (widget) => [widget, const SizedBox(width: 16)]),
                            const Spacer(),
                            Tooltip(
                              message: isExpanded ? 'Collapse' : 'Show details',
                              child: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: Icon(Icons.expand_more,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        )
                      else if (isExpanded)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Tooltip(
                            message: 'Collapse',
                            child: AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(Icons.expand_more,
                                  color: colorScheme.onSurfaceVariant),
                            ),
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
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Divider(
                                        color: colorScheme.outlineVariant,
                                        height: 1),
                                  ),
                                  if (isLoadingDetails)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: 16.0),
                                      child: Center(
                                          child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))),
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
            ],
          ),
        ),
      ),
    );
  }

  static Widget buildIconStat(
      BuildContext context, IconData icon, String text) {
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
