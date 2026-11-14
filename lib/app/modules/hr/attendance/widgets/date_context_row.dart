import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/attendance_models.dart';
import 'package:multimax/app/modules/hr/attendance/attendance_logic.dart';

/// "‹  Today, Tue 9 Sep ▾  ›            ⏱ Updated 5 min ago"
class DateContextRow extends StatelessWidget {
  const DateContextRow({
    super.key,
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.loadedAt,
    required this.now,
    this.updating = false,
  });

  final DateTime date;
  final VoidCallback onPrevious;

  /// Null disables the arrow (already on today).
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final DateTime? loadedAt;
  final DateTime now;
  final bool updating;

  static String labelFor(DateTime date, DateTime now) {
    final d = DateFormat('EEE d MMM').format(date);
    if (dateOnly(date) == dateOnly(now)) return 'Today, $d';
    if (dateOnly(date) == dateOnly(now).subtract(const Duration(days: 1))) {
      return 'Yesterday, $d';
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Container(
      color: s.fg,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            tooltip: 'Previous day',
            icon: Icon(Icons.chevron_left, color: s.textMuted),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          DateContextChip(label: labelFor(date, now), onTap: onPick),
          IconButton(
            onPressed: onNext,
            tooltip: 'Next day',
            icon: Icon(Icons.chevron_right,
                color: onNext == null ? s.border : s.textMuted),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: FreshnessLabel(loadedAt: loadedAt, now: now, updating: updating),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DateContextChip extends StatelessWidget {
  const DateContextChip({super.key, required this.label, required this.onTap, this.leading});
  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Material(
      color: s.fg,
      shape: StadiumBorder(side: BorderSide(color: s.borderStrong)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          height: 36,
          padding: EdgeInsets.fromLTRB(leading == null ? 12 : 6, 0, 10, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s.text),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: s.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Updated 5 min ago"; turns orange with a warning glyph once the data is
/// older than the 15-minute agent sync interval — a nudge to refresh, not an
/// error.
class FreshnessLabel extends StatelessWidget {
  const FreshnessLabel({super.key, required this.loadedAt, required this.now, this.updating = false});
  final DateTime? loadedAt;
  final DateTime now;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stale = !updating && isStale(loadedAt, now);
    final color = stale ? (dark ? AppColors.orange300 : AppColors.orange700) : s.textMuted;
    final text = updating ? 'Updating…' : freshnessLabel(loadedAt, now);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stale ? Icons.warning_amber_rounded : Icons.history,
            size: 13, color: stale ? color : s.textSubtle),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}
