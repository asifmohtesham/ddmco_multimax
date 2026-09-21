import 'package:flutter/material.dart';
import 'package:multimax/app/core/widgets/keyboard_safe_bottom_sheet.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// The "Help on Search" table Frappe's Awesome Bar shows — what each kind of
/// query does — as a themed bottom sheet.
class AwesomeBarHelpSheet extends StatelessWidget {
  const AwesomeBarHelpSheet({super.key});

  /// The rows Frappe's `add_help` lists (tags / random password are not
  /// ported, so their rows are omitted).
  static const List<(String, String)> rows = [
    ('Create a new record', 'new type of document'),
    ('List a document type', 'document type…, e.g. customer'),
    ('Search in a document type', 'text in document type'),
    ('Open a module or tool', 'module name…'),
    ('Calculate', 'e.g. (55 + 434) / 4 or =2^10'),
  ];

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const KeyboardSafeBottomSheet(
          child: AwesomeBarHelpSheet(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Search Help',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: s.text,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: s.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: s.border),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          rows[i].$1,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: s.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          rows[i].$2,
                          style: TextStyle(color: s.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
