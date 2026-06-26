import 'package:flutter/material.dart';

/// A lightweight, **passive** empty-state for use *inside* DocType form tabs
/// and sections (e.g. "No attachments found.", "No stock available.").
///
/// Distinct from [ListEmptyState], which is the *list-screen* empty state with
/// Clear-Filters / Reload call-to-action buttons. This one is just an icon +
/// message (with an optional [title] and optional [action]) and consolidates
/// the private `_buildEmptyState` helpers that were copy-pasted across the
/// Item, Material Request and other form screens.
///
/// Returns a centred [Padding]/[Column]; callers may wrap it in [Center] or
/// place it directly as a tab body.
class FormEmptyState extends StatelessWidget {
  const FormEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.action,
  });

  final IconData icon;
  final String message;

  /// Optional bold heading shown above [message].
  final String? title;

  /// Optional trailing call-to-action (e.g. a button), shown below [message].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}
