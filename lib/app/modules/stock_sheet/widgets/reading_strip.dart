import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/logic/reading_status.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';

/// The strip under the review title: what is being read, how many photos are
/// read and a determinate bar of them. Renders nothing once every row is
/// settled. The line is a polite live region, so a screen reader announces
/// it when it changes, not every row.
class ReadingStrip extends StatelessWidget {
  const ReadingStrip({super.key, required this.entries});

  final List<ReviewEntry> entries;

  @override
  Widget build(BuildContext context) {
    final status = ReadingStatus.of(entries);
    if (status == null) return const SizedBox.shrink();
    final s = context.scheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: s.subtle,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: s.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status.tally,
                  style: TextStyle(fontSize: 12, color: s.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: status.progress,
              minHeight: 4,
              backgroundColor: s.border,
            ),
          ),
        ],
      ),
    );
  }
}
