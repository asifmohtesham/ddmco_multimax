import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// The `+ Filter` affordance in a list-screen chip row — an outlined pill that
/// opens the filter sheet, letting users add a filter directly from the chip
/// row (rather than only via the toolbar funnel icon).
///
/// Rendered by [DocTypeListHeader] at the trailing end of the chip row when an
/// `onFilterTap` callback is provided, so it appears on every list screen.
/// Sized to match [FilterChipWidget] (34dp tall, pill radius) so the applied
/// chips and the add-chip align.
class AddFilterChip extends StatelessWidget {
  final VoidCallback onTap;

  const AddFilterChip({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
          decoration: BoxDecoration(
            border: Border.all(color: s.border),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: s.textMuted),
              const SizedBox(width: 4),
              Text(
                'Filter',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: s.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
