import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/todo_model.dart';

// =============================================================================
// Pure helpers — kept top-level so they are unit-testable without a widget
// tree (same pattern as pos_dn_grouping.dart).
// =============================================================================

/// Flattens a ToDo's rich-text description to a single-line plain string.
/// Frappe stores ToDo descriptions as HTML (text-editor field).
String todoPlainText(String html) {
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Orders ToDos for the dashboard: dated tasks first (soonest due date first),
/// dateless tasks after (keeping their incoming order), capped at [max].
///
/// The server query orders by `date asc`, but MariaDB sorts NULL/empty dates
/// FIRST in ascending order — this reorder puts them last where they belong.
List<ToDo> selectUpcomingTodos(List<ToDo> todos, {int max = 5}) {
  final dated = todos.where((t) => t.date.isNotEmpty).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final dateless = todos.where((t) => t.date.isEmpty).toList();
  return [...dated, ...dateless].take(max).toList();
}

/// Human label for a ToDo due date relative to [today]; null when the ToDo
/// has no (parseable) date.
DueLabel? dueLabelFor(String date, DateTime today) {
  if (date.isEmpty) return null;
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return null;
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final t = DateTime(today.year, today.month, today.day);
  if (day.isBefore(t)) {
    return DueLabel('Overdue · ${DateFormat('d MMM').format(day)}', isOverdue: true);
  }
  if (day.isAtSameMomentAs(t)) return const DueLabel('Due today');
  return DueLabel('Due ${DateFormat('d MMM').format(day)}');
}

class DueLabel {
  final String text;
  final bool isOverdue;
  const DueLabel(this.text, {this.isOverdue = false});
}

// =============================================================================
// DashboardTodoCard — compact actionable task row for the dashboard's
// "Upcoming tasks" section. Visual language matches AttentionRow.
// =============================================================================

class DashboardTodoCard extends StatelessWidget {
  final ToDo todo;
  final VoidCallback onTap;

  const DashboardTodoCard({super.key, required this.todo, required this.onTap});

  static IconData _priorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Icons.priority_high;
      case 'high':
        return Icons.keyboard_double_arrow_up;
      case 'low':
        return Icons.keyboard_double_arrow_down;
      default: // medium
        return Icons.drag_handle;
    }
  }

  // Status-colour-as-text rule: x700 in light mode, x300 in dark.
  static Color _priorityInk(String priority, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (priority.toLowerCase()) {
      case 'urgent':
        return isDark ? AppColors.red300 : AppColors.red700;
      case 'high':
        return isDark ? AppColors.orange300 : AppColors.orange700;
      case 'low':
        return context.scheme.textMuted;
      default: // medium
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final priorityColor = _priorityInk(todo.priority, context);
    final due = dueLabelFor(todo.date, DateTime.now());
    final redInk = isDark ? AppColors.red300 : AppColors.red700;

    final title = todoPlainText(todo.description);

    return Material(
      color: scheme.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(_priorityIcon(todo.priority), color: priorityColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : todo.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: scheme.text,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          todo.priority,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: priorityColor,
                          ),
                        ),
                        if (due != null) ...[
                          Text(
                            ' · ',
                            style: TextStyle(fontSize: 12, color: scheme.textMuted),
                          ),
                          Flexible(
                            child: Text(
                              due.text,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: due.isOverdue ? FontWeight.w700 : FontWeight.w400,
                                color: due.isOverdue ? redInk : scheme.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.textSubtle, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
