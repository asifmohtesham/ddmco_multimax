import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';

/// Ink for a summary indicator — x700 in light, x300 in dark (AA on the
/// surface); `none` falls back to body text.
Color summaryInk(BuildContext context, SummaryIndicator indicator) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return switch (indicator) {
    SummaryIndicator.green => isDark ? AppColors.green300 : AppColors.green700,
    SummaryIndicator.red => isDark ? AppColors.red300 : AppColors.red700,
    SummaryIndicator.blue => isDark ? AppColors.blue300 : AppColors.blue700,
    SummaryIndicator.orange =>
      isDark ? AppColors.orange300 : AppColors.orange700,
    SummaryIndicator.none => context.scheme.text,
  };
}

/// The script report's own `report_summary` cards, in one horizontally
/// scrolling row — the same numbers Desk shows above the grid.
class ReportSummaryStrip extends StatelessWidget {
  const ReportSummaryStrip({super.key, required this.items});

  final List<ReportSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final s = context.scheme;

    // A Row in a horizontal scroller sizes to the tallest tile, so larger
    // system text grows the strip instead of clipping it.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: s.fg,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: s.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: summaryInk(context, item.indicator),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: s.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The selected period, a result count, and one-tap presets.
class ReportPeriodBar extends StatelessWidget {
  const ReportPeriodBar({
    super.key,
    required this.label,
    required this.presets,
    required this.selected,
    required this.onPreset,
    this.count,
    this.countNoun = 'record',
  });

  final String label;
  final List<ReportPeriod> presets;
  final ReportPeriod? selected;
  final ValueChanged<ReportPeriod> onPreset;
  final int? count;
  final String countNoun;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final n = count;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.date_range_outlined, size: 16, color: s.textSubtle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: s.text,
                    ),
                  ),
                ),
                if (n != null && n > 0)
                  Text(
                    '$n $countNoun${n == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: s.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final preset = presets[i];
                return ChoiceChip(
                  label: Text(preset.label),
                  selected: preset == selected,
                  onSelected: (_) => onPreset(preset),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Upper-case bucket heading drawn above the first row of a group.
class ReportGroupHeading extends StatelessWidget {
  const ReportGroupHeading({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: s.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Expanded(child: Text(title.toUpperCase(), style: style)),
          if (trailing != null) Text(trailing!, style: style),
        ],
      ),
    );
  }
}

/// Centred icon + text for the empty, error and not-yet-run states.
class ReportMessage extends StatelessWidget {
  const ReportMessage({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: s.textSubtle),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: s.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
