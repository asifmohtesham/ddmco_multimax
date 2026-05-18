import 'package:flutter/material.dart';

/// A standardised filter chip used by all `*ListAppBar` widgets.
///
/// Renders a [Chip] with a leading [icon], a [label], and a delete button
/// that calls [onDeleted].  All colour and typography values come from the
/// ambient [Theme] so the chip automatically adapts to light / dark mode.
class FilterChipWidget extends StatelessWidget {
  const FilterChipWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.onDeleted,
  });

  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: cs.onSecondaryContainer),
      label: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: cs.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: cs.secondaryContainer,
      deleteIconColor: cs.onSecondaryContainer,
      onDeleted: onDeleted,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
