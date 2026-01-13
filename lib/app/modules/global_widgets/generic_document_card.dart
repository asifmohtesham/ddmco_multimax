import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/theme/frappe_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 2),
            blurRadius: 4,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FrappeTheme.radius),
          splashColor: FrappeTheme.primary.withValues(alpha: 0.05),
          highlightColor: FrappeTheme.primary.withValues(alpha: 0.02),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leading Widget (Image/Icon)
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],

                    // Title & Subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: FrappeTheme.textBody,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: FrappeTheme.textLabel,
                              fontFamily: 'ShureTechMono', // Preserving your custom font
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
                      // Ensure StatusPill is also updated/compatible with the new theme
                      // if it relies on context. For now, it sits nicely here.
                      StatusPill(status: status!),
                    ],
                  ],
                ),

                // Spacing logic for stats/expansion
                if (stats.isNotEmpty || isExpanded)
                  const SizedBox(height: 16),

                // Stats Row & Expand Icon
                Row(
                  children: [
                    if (stats.isNotEmpty)
                      ...stats.expand((widget) => [widget, const SizedBox(width: 16)]),

                    const Spacer(),

                    // Animated Chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutBack,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isExpanded ? FrappeTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                            Icons.expand_more_rounded,
                            color: isExpanded ? FrappeTheme.primary : FrappeTheme.textLabel,
                            size: 20
                        ),
                      ),
                    ),
                  ],
                ),

                // Expanded Content Area
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
                        child: Divider(color: Colors.grey.shade100, height: 1),
                      ),
                      if (isLoadingDetails)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20.0),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: FrappeTheme.primary)
                              )
                          ),
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
      ),
    );
  }

  /// Helper: Builds standard icon stats (Date, Warehouse, etc.)
  /// Usage: GenericDocumentCard.buildIconStat(context, Icons.calendar_today, "2023-10-10")
  static Widget buildIconStat(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: FrappeTheme.textLabel),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: FrappeTheme.textLabel,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}