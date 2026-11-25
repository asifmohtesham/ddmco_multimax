import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'header_chip_band.dart';
import 'list_header_accessibility.dart';

/// Adds a filter through the same operation as the list toolbar funnel.
class AddFilterChip extends StatelessWidget {
  const AddFilterChip({
    super.key,
    required this.onTap,
    this.enabled = true,
    this.focusNode,
  });

  final VoidCallback onTap;
  final bool enabled;
  final FocusNode? focusNode;

  static const _caption = 'Filter';
  static const _action = 'Add filter';
  static const _style = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
  static const _padding = EdgeInsetsDirectional.only(start: 11, end: 13);

  static double _paintHeight(BuildContext context) => math.max(
    34,
    measureHeaderText(context, _caption, _style).size.height.ceil() + 2,
  );

  static HeaderChipSize measureInBand(BuildContext context, double maxWidth) =>
      measureBandChip(
        context,
        _caption,
        maxWidth: maxWidth,
        insets: 36,
        style: headerChipLabelStyle,
      );

  @override
  Widget build(BuildContext context) {
    final palette = HeaderPalette.of(context);
    final available = enabled && ListHeaderFilterScope.enabledOf(context);
    final size = HeaderChipSizeScope.maybeOf(context);
    return HeaderChipButton(
      label: _action,
      tooltip: _action,
      onPressed: available ? onTap : null,
      focusNode: focusNode,
      paint: HeaderChipPaint.add,
      width: size?.width,
      height: size?.height,
      paintedHeight: size?.paintHeight ?? _paintHeight(context),
      padding: size == null
          ? _padding
          : const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 16, color: palette.muted),
          const SizedBox(width: 4),
          if (size == null)
            Text(
              _caption,
              style: DefaultTextStyle.of(context).style
                  .merge(_style)
                  .copyWith(color: palette.muted, inherit: false),
            )
          else
            Expanded(
              child: HeaderBandCaption(
                _caption,
                size: size,
                style: headerChipLabelStyle,
                color: palette.muted,
              ),
            ),
        ],
      ),
    );
  }
}
