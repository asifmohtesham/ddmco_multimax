import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverPersistentHeader;

import 'list_header_accessibility.dart';

const headerChipMinimum = 48.0;
const headerChipMinimumPaintHeight = 34.0;
const headerChipResetWidth = 48.0;
const headerChipLabelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
);

typedef HeaderChipSize = ({
  double width,
  double height,
  double paintHeight,
  bool stackedReset,
  bool stackedChoice,
  int? maxLines,
  bool ellipsized,
});

typedef HeaderChipMeasure =
    HeaderChipSize Function(BuildContext context, double maxWidth);
typedef HeaderChipBuilder =
    Widget Function(BuildContext context, HeaderChipSize size);

TextStyle headerBandLabelStyle(BuildContext context, [TextStyle? style]) {
  final theme = Theme.of(context).textTheme;
  return (style == null
          ? theme.labelLarge ?? const TextStyle(fontSize: 14)
          : (theme.bodyMedium ?? const TextStyle()).merge(style))
      .copyWith(inherit: false);
}

HeaderChipSize measureBandChip(
  BuildContext context,
  String caption, {
  required double maxWidth,
  required double insets,
  TextStyle? style,
  bool split = false,
  int? maxLines,
  bool centerChoice = false,
}) {
  final stacked = split && maxWidth < 2 * headerChipMinimum;
  final resetWidth = split && !stacked ? headerChipResetWidth : 0.0;
  const choiceAdornments = 2 * HeaderBandChoiceContent.adornmentInset;
  final inlineWidth = maxWidth - insets - choiceAdornments;
  var stackedChoice = centerChoice && inlineWidth <= 0;
  final labelStyle = headerBandLabelStyle(context, style);
  final natural = measureHeaderText(
    context,
    caption,
    labelStyle,
    onLayout: centerChoice && !stackedChoice
        ? (painter) {
            if (painter.width <= inlineWidth) return;
            var offset = 0;
            for (final grapheme in caption.characters) {
              final next = offset + grapheme.length;
              final boxes = painter.getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: next),
              );
              if (boxes.any((box) => box.right - box.left > inlineWidth)) {
                stackedChoice = true;
                return;
              }
              offset = next;
            }
          }
        : null,
  );
  final choiceInsets = centerChoice && !stackedChoice ? choiceAdornments : 0.0;
  final contentInsets = insets + choiceInsets;
  final naturalWidth =
      math.max(
        headerChipMinimum,
        (natural.size.width + contentInsets).ceilToDouble(),
      ) +
      resetWidth;
  final width = math.min(maxWidth, naturalWidth);
  final labelWidth = math.max(1.0, width - resetWidth - contentInsets);
  final laidOut = measureHeaderText(
    context,
    caption,
    labelStyle,
    maxWidth: labelWidth,
    maxLines: maxLines,
    ellipsis: maxLines != null ? '…' : null,
  );
  final choiceHeight = stackedChoice
      ? HeaderBandChoiceContent.adornmentInset
      : 0.0;
  final paintHeight = math.max(
    headerChipMinimumPaintHeight,
    laidOut.size.height.ceil() + 4.0 + choiceHeight,
  );
  final target = math.max(headerChipMinimum, paintHeight + 6);
  return (
    width: width,
    height: stacked ? 2 * target : target,
    paintHeight: paintHeight,
    stackedReset: stacked,
    stackedChoice: stackedChoice,
    maxLines: maxLines,
    ellipsized: laidOut.didExceedMaxLines,
  );
}

class HeaderBandCaption extends StatelessWidget {
  const HeaderBandCaption(
    this.caption, {
    super.key,
    required this.size,
    this.style,
    this.color,
    this.textAlign,
  });

  final String caption;
  final HeaderChipSize size;
  final TextStyle? style;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    caption,
    textAlign: textAlign,
    maxLines: size.maxLines,
    softWrap: true,
    overflow: size.maxLines == null
        ? TextOverflow.visible
        : TextOverflow.ellipsis,
    style: headerBandLabelStyle(context, style).copyWith(color: color),
  );
}

/// Balances the space for choice adornments to keep the caption centered as
/// the selection changes. Narrow slots put the adornments above the caption.
class HeaderBandChoiceContent extends StatelessWidget {
  const HeaderBandChoiceContent({
    super.key,
    required this.caption,
    required this.stacked,
    this.leading,
    this.trailing,
  });

  static const adornmentInset = 20.0;
  static const _adornmentHeight = 16.0;

  final Widget caption;
  final bool stacked;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: _adornmentHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading case final icon?) icon,
                if (trailing case final icon?) icon,
              ],
            ),
          ),
          const SizedBox(height: adornmentInset - _adornmentHeight),
          caption,
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: _adornmentHeight,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: adornmentInset),
            child: caption,
          ),
          if (leading case final icon?)
            PositionedDirectional(start: 0, child: icon),
          if (trailing case final icon?)
            PositionedDirectional(end: 0, child: icon),
        ],
      ),
    );
  }
}

/// Adapts a control with custom content to the band using a pure measurement.
/// [builder] receives the same metrics that allocated the real control's slot.
class MeasuredHeaderChip extends StatelessWidget {
  const MeasuredHeaderChip({
    required LocalKey super.key,
    required this.measure,
    required this.builder,
  });

  final HeaderChipMeasure measure;
  final HeaderChipBuilder builder;

  @override
  Widget build(BuildContext context) {
    final size = context
        .dependOnInheritedWidgetOfExactType<HeaderChipSizeScope>()!
        .size;
    return builder(context, size);
  }
}

class HeaderChipSizeScope extends InheritedWidget {
  const HeaderChipSizeScope({
    super.key,
    required this.size,
    required super.child,
  });

  final HeaderChipSize size;

  static HeaderChipSize? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderChipSizeScope>()?.size;

  @override
  bool updateShouldNotify(HeaderChipSizeScope oldWidget) =>
      size != oldWidget.size;
}

enum HeaderQuickRole { choice, toggle, command }

/// A report action with a fixed slot for its check, glyph or spinner.
class HeaderQuickChip extends StatelessWidget {
  const HeaderQuickChip({
    super.key,
    required this.caption,
    required this.label,
    required this.role,
    required this.onPressed,
    this.value,
    this.active = false,
    this.saving = false,
    this.focusNode,
  });

  final String caption;
  final String label;
  final HeaderQuickRole role;
  final VoidCallback? onPressed;
  final String? value;
  final bool active;
  final bool saving;
  final FocusNode? focusNode;

  static HeaderChipSize measureCaption(
    BuildContext context,
    String caption,
    double maxWidth,
  ) => measureBandChip(context, caption, maxWidth: maxWidth, insets: 32);

  HeaderChipSize measure(BuildContext context, double maxWidth) =>
      role == HeaderQuickRole.choice
      ? measureBandChip(
          context,
          caption,
          maxWidth: maxWidth,
          insets: 12,
          centerChoice: true,
        )
      : measureCaption(context, caption, maxWidth);

  @override
  Widget build(BuildContext context) {
    final size =
        HeaderChipSizeScope.maybeOf(context) ??
        measure(context, double.infinity);
    final palette = HeaderPalette.of(context);
    final ink = palette.quickInk(
      selected: active,
      enabled: onPressed != null,
      command: role == HeaderQuickRole.command,
    );
    final indicator = switch (role) {
      HeaderQuickRole.choice => active ? Icons.check : null,
      HeaderQuickRole.toggle =>
        active ? Icons.check_box_outlined : Icons.check_box_outline_blank,
      HeaderQuickRole.command => Icons.tune,
    };
    final glyph = saving
        ? SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          )
        : indicator == null
        ? null
        : Icon(indicator, size: 16, color: ink);
    final isChoice = role == HeaderQuickRole.choice;
    final labelText = HeaderBandCaption(
      caption,
      size: size,
      color: ink,
      textAlign: isChoice ? TextAlign.center : null,
    );
    return Stack(
      children: [
        HeaderChipButton(
          label: label,
          value: value,
          selected: role == HeaderQuickRole.choice ? active : null,
          toggled: role == HeaderQuickRole.toggle ? active : null,
          tooltip: size.ellipsized ? caption : null,
          onPressed: onPressed,
          focusNode: focusNode,
          width: size.width,
          height: size.height,
          paintedHeight: size.paintHeight,
          paint: HeaderChipPaint.quick,
          quickActive: active,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: isChoice
              ? HeaderBandChoiceContent(
                  stacked: size.stackedChoice,
                  leading: glyph,
                  caption: labelText,
                )
              : Row(
                  children: [
                    SizedBox.square(dimension: 16, child: glyph),
                    const SizedBox(width: 4),
                    Expanded(child: labelText),
                  ],
                ),
        ),
        if (saving)
          Positioned(
            top: 0,
            left: 0,
            child: Semantics(
              container: true,
              label: 'Saving View',
              liveRegion: true,
              child: const SizedBox.square(dimension: 1),
            ),
          ),
      ],
    );
  }
}

typedef HeaderBandSlot = ({HeaderChipSize size, int run, double x, double y});

typedef HeaderBandPlan = ({double height, List<HeaderBandSlot> slots});

HeaderBandPlan planHeaderBand(
  BuildContext context,
  double width,
  List<HeaderChipMeasure> measures, {
  required bool hasSplit,
}) {
  if (measures.isEmpty) return (height: 0, slots: const []);
  const slotGap = 6.0;
  const runGap = 4.0;
  final minimumWidth = hasSplit ? 2 * headerChipMinimum : headerChipMinimum;
  final inset = ((width - minimumWidth) / 2).clamp(0.0, 12.0);
  final lineWidth = width - 2 * inset;
  final direction = Directionality.of(context);
  final slots = <HeaderBandSlot>[];
  final run = <({HeaderChipSize size, double x})>[];
  var y = 0.0;
  var x = inset;
  var tallest = 0.0;
  var runIndex = 0;

  void finishRun() {
    for (final item in run) {
      slots.add((
        size: item.size,
        run: runIndex,
        x: direction == TextDirection.ltr
            ? item.x
            : width - item.x - item.size.width,
        y: y + (tallest - item.size.height) / 2,
      ));
    }
    y += tallest + runGap;
    runIndex++;
    run.clear();
    x = inset;
    tallest = 0;
  }

  for (final measure in measures) {
    final size = measure(context, lineWidth);
    if (run.isNotEmpty && x + size.width > width - inset) finishRun();
    run.add((size: size, x: x));
    tallest = math.max(tallest, size.height);
    x += size.width + slotGap;
  }
  finishRun();
  return (height: y - runGap, slots: List.unmodifiable(slots));
}

bool _isHorizontal(TraversalDirection direction) =>
    direction == TraversalDirection.left ||
    direction == TraversalDirection.right;

class _HeaderBandFocusHistory {
  _HeaderBandFocusHistory(this.direction, this.current);

  final TraversalDirection direction;
  FocusNode current;
  final previous = <FocusNode>[];
}

/// Keeps directional focus within the nearest run before leaving the band.
class HeaderBandTraversalPolicy extends OrderedTraversalPolicy {
  HeaderBandTraversalPolicy(this.containsNode)
    : super(secondary: WidgetOrderTraversalPolicy()) {
    FocusManager.instance.addListener(_discardUnrelatedHistory);
  }

  final bool Function(FocusNode) containsNode;
  final _history = <FocusScopeNode, _HeaderBandFocusHistory>{};

  void dispose() {
    FocusManager.instance.removeListener(_discardUnrelatedHistory);
    _history.clear();
  }

  void _discardUnrelatedHistory() {
    final primary = FocusManager.instance.primaryFocus;
    _history.removeWhere((_, history) => history.current != primary);
  }

  @override
  void invalidateScopeData(FocusScopeNode node) {
    _history.remove(node);
    super.invalidateScopeData(node);
  }

  @override
  void changedScope({FocusNode? node, FocusScopeNode? oldScope}) {
    _history.remove(oldScope);
    super.changedScope(node: node, oldScope: oldScope);
  }

  void _move(FocusNode node, TraversalDirection direction) {
    requestFocusCallback(
      node,
      alignmentPolicy:
          direction == TraversalDirection.up ||
              direction == TraversalDirection.left
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);
    final origin = currentNode.rect;
    final horizontal = _isHorizontal(direction);
    final history = _history[scope];
    if (history != null) {
      if (history.current != currentNode ||
          _isHorizontal(history.direction) != horizontal) {
        _history.remove(scope);
      } else if (history.direction != direction) {
        while (history.previous.isNotEmpty) {
          final prior = history.previous.removeLast();
          if (prior.parent == null ||
              prior.nearestScope != scope ||
              !prior.canRequestFocus ||
              prior.skipTraversal ||
              !containsNode(prior)) {
            continue;
          }
          history.current = prior;
          if (history.previous.isEmpty) _history.remove(scope);
          _move(prior, direction);
          return true;
        }
        _history.remove(scope);
      }
    }
    final candidates = scope.traversalDescendants.where((candidate) {
      if (!containsNode(candidate)) return false;
      final target = candidate.rect;
      final sameRun = target.top < origin.bottom && target.bottom > origin.top;
      return switch (direction) {
        TraversalDirection.left =>
          sameRun && target.center.dx < origin.center.dx,
        TraversalDirection.right =>
          sameRun && target.center.dx > origin.center.dx,
        TraversalDirection.up =>
          !sameRun && target.center.dy < origin.center.dy,
        TraversalDirection.down =>
          !sameRun && target.center.dy > origin.center.dy,
      };
    });

    FocusNode? closest;
    var closestPrimary = double.infinity;
    var closestSecondary = double.infinity;
    for (final node in candidates) {
      final delta = node.rect.center - origin.center;
      final primary = (horizontal ? delta.dx : delta.dy).abs();
      final secondary = (horizontal ? delta.dy : delta.dx).abs();
      if (primary < closestPrimary ||
          (primary == closestPrimary && secondary < closestSecondary)) {
        closest = node;
        closestPrimary = primary;
        closestSecondary = secondary;
      }
    }
    if (closest == null) return super.inDirection(currentNode, direction);
    final next = _history.putIfAbsent(
      scope,
      () => _HeaderBandFocusHistory(direction, closest!),
    );
    next.previous.add(currentNode);
    next.current = closest;
    _move(closest, direction);
    return true;
  }
}

Iterable<ScrollableState> _verticalScrollables(BuildContext context) sync* {
  var scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
  while (scrollable != null) {
    yield scrollable;
    scrollable = Scrollable.maybeOf(scrollable.context, axis: Axis.vertical);
  }
}

Rect? _boxBounds(RenderObject? renderObject) {
  if (renderObject is! RenderBox ||
      !renderObject.attached ||
      !renderObject.hasSize) {
    return null;
  }
  for (
    var ancestor = renderObject.parent;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    // A keyed row can already be attached to a newly mounted sliver while
    // its previous child geometry is still present.
    if (ancestor is RenderSliverPersistentHeader && ancestor.geometry == null) {
      return null;
    }
  }
  return MatrixUtils.transformRect(
    renderObject.getTransformTo(null),
    renderObject.paintBounds,
  );
}

Rect? _scrollableBounds(ScrollableState scrollable) =>
    _boxBounds(scrollable.notificationContext?.findRenderObject());

bool? isHeaderBandTargetVisible(BuildContext? targetContext) {
  if (targetContext == null || !targetContext.mounted) return null;
  final target = _boxBounds(targetContext.findRenderObject());
  if (target == null) return null;
  for (final scrollable in _verticalScrollables(targetContext)) {
    final viewport = _scrollableBounds(scrollable);
    if (viewport == null) return null;
    if (target.top < viewport.top - .01 ||
        target.bottom > viewport.bottom + .01) {
      return false;
    }
  }
  return true;
}

typedef HeaderBandScrollOffsets =
    List<({ScrollPosition position, double pixels})>;

HeaderBandScrollOffsets captureHeaderBandScrollOffsets(BuildContext context) =>
    [
      for (final scrollable in _verticalScrollables(context))
        if (scrollable.position.hasPixels)
          (position: scrollable.position, pixels: scrollable.position.pixels),
    ];

/// Brings a vertically clipped chip into view without changing keyboard focus.
void revealHeaderBandTarget(BuildContext targetContext) =>
    _scheduleHeaderBandReveal(() => targetContext);

/// Brings a keyboard target into view only while it owns focus.
void revealHeaderBandFocus(
  BuildContext bandContext,
  FocusNode focus, {
  void Function(BuildContext?)? onComplete,
}) => _scheduleHeaderBandReveal(
  () => bandContext.mounted && focus.hasPrimaryFocus ? focus.context : null,
  onComplete: onComplete,
);

void _scheduleHeaderBandReveal(
  BuildContext? Function() targetContext, {
  void Function(BuildContext?)? onComplete,
}) {
  final binding = WidgetsBinding.instance;
  final corrected = <ScrollableState>{};
  void reveal(Duration _) {
    final context = targetContext();
    if (context == null || !context.mounted) {
      onComplete?.call(null);
      return;
    }
    final target = _boxBounds(context.findRenderObject());
    if (target == null) {
      onComplete?.call(null);
      return;
    }

    for (final scrollable in _verticalScrollables(context)) {
      if (corrected.contains(scrollable)) continue;
      final position = scrollable.position;
      final viewport = _scrollableBounds(scrollable);
      if (!position.hasContentDimensions || viewport == null) continue;

      // An enlarged chip can exceed the scroll pane. Keep it in view when
      // already showing a portion, and leave its remaining area scrollable.
      if (target.height > viewport.height && target.overlaps(viewport)) {
        continue;
      }
      final overflow = target.top < viewport.top
          ? target.top - viewport.top
          : math.max(0.0, target.bottom - viewport.bottom);
      final correction = position.axisDirection == AxisDirection.up
          ? -overflow
          : overflow;
      final pixels = (position.pixels + correction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((pixels - position.pixels).abs() < .01) continue;
      corrected.add(scrollable);
      position.jumpTo(pixels);
      // An inner correction changes the target's bounds in the outer view.
      binding.addPostFrameCallback(reveal);
      return;
    }
    onComplete?.call(context);
  }

  binding.addPostFrameCallback(reveal);
  binding.ensureVisualUpdate();
}
