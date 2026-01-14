import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';
import 'package:multimax/theme/frappe_theme.dart';

class GenericDocumentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? status;
  final Color? statusColor; // Optional override
  final Widget? leading;
  final List<Widget>? stats;
  final Widget? expandedContent;
  final VoidCallback? onTap;
  final bool isExpanded;
  final bool isLoadingDetails;

  const GenericDocumentCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.status,
    this.statusColor,
    this.leading,
    this.stats,
    this.expandedContent,
    this.onTap,
    this.isExpanded = false,
    this.isLoadingDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header Row ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Optional Leading Icon/Image
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],

                  // Title & Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: FrappeTheme.textBody,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (status != null) ...[
                              const SizedBox(width: 8),
                              StatusPill(status: status!),
                            ],
                          ],
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: FrappeTheme.textLabel,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // --- Stats Section (FIX: Use Wrap instead of Row) ---
              if (stats != null && stats!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16.0, // Horizontal space between items
                  runSpacing: 8.0, // Vertical space between lines
                  children: stats!,
                ),
              ],

              // --- Expanded Content ---
              if (isExpanded || isLoadingDetails) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                if (isLoadingDetails)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (expandedContent != null)
                  expandedContent!,
              ],

              // --- Expand/Collapse Indicator (Optional hint) ---
              if (expandedContent != null && !isExpanded)
                Center(
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Colors.grey.shade300,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper to build consistent stat rows ---
  static Widget buildIconStat(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    // FIX: Add Flexible/Constraints to text to prevent overflow within the Wrap item itself if needed
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: FrappeTheme.textLabel),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: FrappeTheme.textBody,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
