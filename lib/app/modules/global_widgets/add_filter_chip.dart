import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  static double requiredHeight(BuildContext context) =>
      math.max(48, _paintHeight(context));

  @override
  Widget build(BuildContext context) {
    final palette = HeaderPalette.of(context);
    final available = enabled && ListHeaderFilterScope.enabledOf(context);
    return HeaderChipButton(
      label: _action,
      tooltip: _action,
      onPressed: available ? onTap : null,
      focusNode: focusNode,
      paint: HeaderChipPaint.add,
      paintedHeight: _paintHeight(context),
      padding: _padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 16, color: palette.muted),
          const SizedBox(width: 4),
          Text(
            _caption,
            style: DefaultTextStyle.of(context).style
                .merge(_style)
                .copyWith(color: palette.muted, inherit: false),
          ),
        ],
      ),
    );
  }
}
