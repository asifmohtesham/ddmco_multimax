import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/list_header_accessibility.dart';

/// A notification/count badge (ERPNext v15 `.count-badge`): 18px min, pill
/// shaped, red700 bg + white text by default; [muted] uses `scheme.textSubtle`
/// for quieter tab counts.
class CountBadge extends StatelessWidget {
  final int count;
  final bool muted;

  /// Adds a separating ring and keeps animated numerals inside the toolbar slot.
  final bool toolbar;
  final Size? toolbarBounds;

  const CountBadge({
    super.key,
    required this.count,
    this.muted = false,
    this.toolbar = false,
    this.toolbarBounds,
  });

  static const _numeral = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  static Size measureToolbar(BuildContext context, int count) {
    final label = measureHeaderText(context, '$count', _numeral).size;
    return Size(
      math.max(18, label.width.ceilToDouble() + 10),
      math.max(18, label.height.ceilToDouble() + 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    if (toolbar && !muted) {
      final palette = HeaderPalette.of(context);
      final size = toolbarBounds ?? measureToolbar(context, count);
      return Container(
        width: size.width,
        height: size.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.toolbarBadgeFill,
          border: Border.all(color: palette.toolbarBadgeRing),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          softWrap: false,
          style: _numeral.copyWith(color: palette.toolbarBadgeInk),
        ),
      );
    }
    final bg = muted ? s.textSubtle : AppColors.red700;
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
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Text(
          '$count',
          key: ValueKey(count),
          textAlign: TextAlign.center,
          style: _numeral.copyWith(color: muted ? s.text : Colors.white),
        ),
      ),
    );
  }
}
