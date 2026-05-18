import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class GenericDocumentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? status;
  final List<Widget> stats;

  /// Optional second row of stats shown at a visually lower hierarchy
  /// (smaller, muted). Used for audit fields like Created By / Modified By.
  final List<Widget> auditStats;

  final bool isExpanded;
  final bool isLoadingDetails;
  final VoidCallback onTap;

  /// Optional long-press handler. When provided, a long-press on the card
  /// fires this callback instead of (or in addition to) [onTap].
  final VoidCallback? onLongPress;

  final Widget? expandedContent;
  final Widget? leading;

  /// When `true` the trailing chevron renders as a static
  /// [Icons.chevron_right] (tooltip: 'Open'), clearly communicating that
  /// [onTap] **navigates** rather than expands the card in-place.
  ///
  /// When `false` (default) the original [AnimatedRotation] behaviour is
  /// preserved: the chevron rotates 180 ° when [isExpanded] is `true` and
  /// the [expandedContent] panel is shown below the stats row.
  ///
  /// ## Choosing the correct value
  /// | Screen / use-case                    | value  |
  /// |--------------------------------------|--------|
  /// | StockEntry list card (expand panel)  | false  |
  /// | DeliveryNote list card (expand panel)| false  |
  /// | PackingSlip list card (expand panel) | false  |
  /// | Any card that only navigates on tap  | true   |
  ///
  /// ⚠️ UI/UX contract: never set [navigatesOnTap] to `true` on a card that
  /// also passes a non-null [expandedContent] — the affordances would
  /// contradict each other.
  final bool navigatesOnTap;

  const GenericDocumentCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.status,
    this.stats = const [],
    this.auditStats = const [],
    required this.isExpanded,
    required this.onTap,
    this.onLongPress,
    this.isLoadingDetails = false,
    this.expandedContent,
    this.leading,
    this.navigatesOnTap = false,
  });

  // Frappe / ERPNext canonical status colours — matches StatusPill exactly.
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

  /// Builds the trailing chevron widget for the stats row.
  ///
  /// - [navigatesOnTap] == `true`  → static [Icons.chevron_right], tooltip
  ///   'Open'. Signals that the card navigates to a detail screen.
  /// - [navigatesOnTap] == `false` → [AnimatedRotation] on [Icons.expand_more],
  ///   tooltip 'Show details' / 'Collapse'. Signals in-place expansion.
  Widget _buildTrailingChevron(ColorScheme colorScheme) {
    if (navigatesOnTap) {
      return Tooltip(
        message: 'Open',
        child: Icon(
          Icons.chevron_right,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Tooltip(
      message: isExpanded ? 'Collapse' : 'Show details',
      child: AnimatedRotation(
        turns: isExpanded ? 0.5 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Icon(
          Icons.expand_more,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
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
        onLongPress: onLongPress,
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
                  padding:
                      EdgeInsets.fromLTRB(hasAccent ? 12 : 16, 14, 16, 14),
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
                                  style: theme.textTheme.titleSmall?.copyWith(
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

                      // ── Row 1: primary stats + trailing chevron ─────────
                      if (stats.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: stats,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildTrailingChevron(colorScheme),
                          ],
                        ),
                      ] else if (isExpanded)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _buildTrailingChevron(colorScheme),
                        ),

                      // ── Row 2: audit stats (muted, smaller) ────────────
                      if (auditStats.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 2,
                          children: auditStats
                              .map((w) => _AuditStatWrapper(child: w))
                              .toList(),
                        ),
                      ],

                      // ── Expanded section ──────────────────────────────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: !isExpanded
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colorScheme.primary),
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

/// Wraps an audit stat widget with reduced opacity to signal lower hierarchy.
class _AuditStatWrapper extends StatelessWidget {
  final Widget child;
  const _AuditStatWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.72,
      child: Transform.scale(
        scale: 0.92,
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}
