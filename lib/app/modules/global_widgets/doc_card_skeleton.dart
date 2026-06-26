import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';

/// A loading placeholder that mirrors [GenericDocumentCard]'s silhouette:
/// a title line, a shorter mono "doc-id" line, a trailing status-pill block,
/// and a stats row. Use [DocCardSkeletonList] to render several at once on a
/// list screen's first load.
class DocCardSkeleton extends StatelessWidget {
  const DocCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: 6),
      elevation: 0,
      color: s.fg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: s.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s4, 14, AppSpace.s4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.6,
                        child: SkeletonBox(height: 14),
                      ),
                      SizedBox(height: 6),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.4,
                        child: SkeletonBox(height: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.s2),
                const SkeletonBox(width: 64, height: 22, radius: AppRadius.full),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: const [
                SkeletonBox(width: 60, height: 11),
                SizedBox(width: AppSpace.s4),
                SkeletonBox(width: 48, height: 11),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A column of [DocCardSkeleton]s for a list screen's first-load state.
/// Drop into a `SliverToBoxAdapter`.
class DocCardSkeletonList extends StatelessWidget {
  final int count;
  const DocCardSkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (_) => const DocCardSkeleton()),
    );
  }
}
