import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Accent-tinted card holding the generated rule sentence; first child of
/// every Pricing Rule form tab.
class RuleSummaryCard extends StatelessWidget {
  const RuleSummaryCard({super.key, required this.text, this.showLabel = false});

  final String text;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Container(
      padding: showLabel
          ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
          : const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(s.primary.withValues(alpha: 0.12), s.fg),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Color.alphaBlend(s.primary.withValues(alpha: 0.40), s.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 18, color: s.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showLabel)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('THIS RULE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: s.primary)),
                  ),
                Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: s.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
