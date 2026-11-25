import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'list_header_accessibility.dart';

/// An applied filter with independent Edit and Reset targets.
class FilterChipWidget extends StatelessWidget {
  const FilterChipWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.onDeleted,
    this.onTap,
    this.maxLabelWidth,
    this.enabled = true,
    this.editSemanticLabel,
    this.resetSemanticLabel,
    this.dismissesChip = false,
    this.editFocusNode,
    this.resetFocusNode,
    this.onResetInvoked,
  });

  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  /// A width cap opts the caption into one line with an ellipsis.
  final double? maxLabelWidth;

  /// A null callback keeps the caption readable without making it a command.
  final VoidCallback? onTap;

  final bool enabled;
  final String? editSemanticLabel;
  final String? resetSemanticLabel;
  final bool dismissesChip;
  final FocusNode? editFocusNode;
  final FocusNode? resetFocusNode;

  /// Records the current focus before the filter owner can mutate the row.
  final VoidCallback? onResetInvoked;

  static const _labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
  static const _editInset = 13.0;
  static const _iconSize = 16.0;
  static const _labelGap = 6.0;
  static const _contourEndClearance = 4.0;
  static const _contourVerticalClearance = 5.0;
  static const _resetWidth = 48.0;
  static const _endGutter = 6.0;

  HeaderTextMetrics _measure(BuildContext context) => measureHeaderText(
    context,
    label,
    _labelStyle,
    maxWidth: maxLabelWidth ?? double.infinity,
    maxLines: maxLabelWidth == null ? null : 1,
    ellipsis: maxLabelWidth == null ? null : '…',
  );

  double _paintHeight(Size caption) => math.max(34, caption.height.ceil() + 2);

  double _hitHeight(Size caption) => math.max(
    48,
    onTap == null
        ? _paintHeight(caption)
        : caption.height.ceil() + 2 * _contourVerticalClearance,
  );

  double requiredHeight(BuildContext context) =>
      _hitHeight(_measure(context).size);

  FilterChipWidget withHeaderFocus({
    required FocusNode editFocusNode,
    required FocusNode resetFocusNode,
    required VoidCallback onResetInvoked,
  }) => FilterChipWidget(
    key: key,
    icon: icon,
    label: label,
    onDeleted: onDeleted,
    maxLabelWidth: maxLabelWidth,
    onTap: onTap,
    enabled: enabled,
    editSemanticLabel: editSemanticLabel,
    resetSemanticLabel: resetSemanticLabel,
    dismissesChip: dismissesChip,
    editFocusNode: this.editFocusNode ?? editFocusNode,
    resetFocusNode: this.resetFocusNode ?? resetFocusNode,
    onResetInvoked: () {
      onResetInvoked();
      this.onResetInvoked?.call();
    },
  );

  @override
  Widget build(BuildContext context) {
    final palette = HeaderPalette.of(context);
    final available = enabled && ListHeaderFilterScope.enabledOf(context);
    final ink = palette.appliedInkFor(available);
    final caption = _measure(context).size;
    final pillHeight = _paintHeight(caption);
    final hitHeight = _hitHeight(caption);
    final endInset = onTap == null ? 0.0 : _contourEndClearance;
    final editWidth = math.max(
      48.0,
      _editInset + _iconSize + _labelGap + caption.width + endInset,
    );

    final content = SizedBox(
      width: editWidth,
      height: hitHeight,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: _editInset, end: endInset),
        child: Row(
          children: [
            Icon(icon, size: _iconSize, color: ink),
            const SizedBox(width: _labelGap),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxLabelWidth ?? double.infinity,
                ),
                child: Text(
                  label,
                  maxLines: maxLabelWidth == null ? null : 1,
                  overflow: maxLabelWidth == null
                      ? null
                      : TextOverflow.ellipsis,
                  style: DefaultTextStyle.of(context).style
                      .merge(_labelStyle)
                      .copyWith(color: ink, inherit: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    void reset() {
      onResetInvoked?.call();
      onDeleted();
    }

    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        PositionedDirectional(
          start: 0,
          end: _endGutter,
          height: pillHeight,
          child: IgnorePointer(
            child: HeaderPill(
              fill: palette.appliedFillFor(available),
              perimeter: palette.appliedPerimeterFor(available),
              disabled: !available,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onTap == null)
              content
            else
              HeaderChipButton(
                label: editSemanticLabel ?? 'Edit $label',
                onPressed: available ? onTap : null,
                paint: HeaderChipPaint.split,
                focusNode: editFocusNode,
                width: editWidth,
                height: hitHeight,
                child: content,
              ),
            HeaderChipButton(
              label: resetSemanticLabel ?? 'Reset $label',
              onPressed: available ? reset : null,
              paint: HeaderChipPaint.split,
              focusNode: resetFocusNode,
              semanticDismiss: dismissesChip ? reset : null,
              width: _resetWidth,
              height: hitHeight,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: _endGutter),
                child: Icon(Icons.close, size: 15, color: ink),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
