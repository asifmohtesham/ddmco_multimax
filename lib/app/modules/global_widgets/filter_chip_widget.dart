import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// An applied-filter chip (ERPNext v15 `.chip.active`): maroon-tinted fill,
/// maroon border + text, with a trailing × to clear the filter. Used by every
/// DocType list screen via [DocTypeListHeader]'s `filterChipsBuilder`.
class FilterChipWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  const FilterChipWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final fill = Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg);
    final border = Color.alphaBlend(s.primary.withValues(alpha: 0.40), s.border);

    return Container(
      height: 34,
      padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: s.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: s.primary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDeleted,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Opacity(
                opacity: 0.7,
                child: Icon(Icons.close, size: 15, color: s.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
