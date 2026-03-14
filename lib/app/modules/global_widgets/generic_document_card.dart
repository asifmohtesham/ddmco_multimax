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
  // Frappe / ERPNext canonical status colours — matches StatusPill exactly.
  // ---------------------------------------------------------------------------
  static Color _statusAccentColor(String? status) {
    switch (status) {
      case 'Submitted':
      case 'Active':
      case 'Completed':
      case 'Paid':
        return const Color(0xFF36A564);
      case 'Draft':
        return const Color(0xFFE54D4D);
      case 'Cancelled':
      case 'Rejected':
        return const Color(0xFF5A6673);
      case 'Pending':
      case 'In Progress':
      case 'Open':
        return const Color(0xFFFFA00A);
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = _statusAccentColor(status);
    final hasAccent = accentColor != Colors.transparent;

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
              // Left-edge Frappe status accent bar
              if (hasAccent)
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

              // Card body
              Expanded(
                child: Padding(
                  // Reduce left padding slightly when accent bar is present
                  // so total leading space stays visually consistent.
                  padding: EdgeInsets.fromLTRB(
                      hasAccent ? 12 : 16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header: title / subtitle / status pill ──────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style:
                                      theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'ShureTechMono',
                                    fontSize: 11,
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

                      // ── Stats row + expand chevron ───────────────────────
                      if (stats.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // Stats wrap so a 3-stat row doesn't overflow
                            Expanded(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: stats,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message:
                                  isExpanded ? 'Collapse' : 'Show details',
                              child: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0.0,
                                duration:
                                    const Duration(milliseconds: 300),
                                child: Icon(
                                  Icons.expand_more,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (isExpanded)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Tooltip(
                            message: 'Collapse',
                            child: AnimatedRotation(
                              turns: 0.5,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(Icons.expand_more,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),

                      // ── Expanded section ─────────────────────────────────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: !isExpanded
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 10),
                                  Divider(
                                      height: 1,
                                      color: colorScheme.outlineVariant),
                                  const SizedBox(height: 12),
                                  if (isLoadingDetails)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12.0),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: colorScheme
                                                      .primary),
                                        ),
                                      ),
                                    )
                                  else if (expandedContent != null)
                                    expandedContent!,
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

  // Stats cells — now uses bodySmall consistently, weight w500
  static Widget buildIconStat(
      BuildContext context, IconData icon, String text) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
