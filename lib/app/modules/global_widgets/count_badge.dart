import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A notification/count badge (ERPNext v15 `.count-badge`): 18px min, pill
/// shaped, red500 bg + white text by default; [muted] uses `scheme.textSubtle`
/// for quieter tab counts.
///
/// The default red500 background with white text is intrinsic/spec-mandated
/// from ds.css `.count-badge`.
class CountBadge extends StatelessWidget {
  final int count;
  final bool muted;

  const CountBadge({super.key, required this.count, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    // ds.css .count-badge is intrinsically red500/#fff; muted swaps the bg only.
    final bg = muted ? s.textSubtle : AppColors.red500;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
        child: Text(
          '$count',
          key: ValueKey(count),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: muted ? s.text : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
