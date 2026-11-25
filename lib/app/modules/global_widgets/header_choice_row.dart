import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import 'header_chip_band.dart';
import 'list_header_accessibility.dart';

class HeaderChoiceOption {
  const HeaderChoiceOption({
    required this.id,
    required this.groupId,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onPressed,
    this.selectedHint,
    this.dotColor,
  });

  final String id;
  final String groupId;
  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onPressed;
  final String? selectedHint;
  final Color? dotColor;
}

typedef HeaderChoicePaint = ({
  Color fill,
  Color caption,
  Color check,
  Color perimeter,
  bool dashed,
  double contour,
});

HeaderChoicePaint resolveHeaderChoicePaint(
  HeaderPalette palette,
  Set<WidgetState> states, {
  required bool selected,
  bool solidSelection = false,
}) {
  final disabled = states.contains(WidgetState.disabled);
  final contour = headerContourWidth(states);
  if (solidSelection) {
    final base = palette.choiceFill(selected, !disabled);
    final ink = palette.choiceInk(selected, !disabled);
    final fill = !disabled && states.contains(WidgetState.pressed)
        ? Color.alphaBlend(palette.quickPressedLayer, base)
        : base;
    return (
      fill: fill,
      caption: ink,
      check: ink,
      perimeter: selected ? fill : palette.muted,
      dashed: false,
      contour: contour,
    );
  }
  final applied = selected && !disabled;
  return (
    fill: applied ? palette.appliedFill : palette.addFill(states),
    caption: applied ? palette.appliedInk : palette.muted,
    check: applied ? palette.ink : palette.muted,
    perimeter: palette.appliedPerimeterFor(applied),
    dashed: disabled,
    contour: contour,
  );
}

class HeaderChoiceButton extends StatefulWidget {
  const HeaderChoiceButton({
    super.key,
    required this.option,
    required this.size,
    required this.stacked,
    required this.pillRadius,
    this.focusNode,
    this.busy = false,
    this.solidSelection = false,
  });

  final HeaderChoiceOption option;
  final Size size;
  final bool stacked;
  final double pillRadius;
  final FocusNode? focusNode;
  final bool busy;
  final bool solidSelection;

  static const _pillInset = 7.0;
  static const _captionInset = 4.0;
  static const _horizontalInsets = 2 * (_pillInset + _captionInset);

  static HeaderChipSize _measure(
    BuildContext context,
    String label,
    double maxWidth,
  ) {
    final size = measureBandChip(
      context,
      label,
      maxWidth: maxWidth,
      insets: _horizontalInsets,
      centerChoice: true,
    );
    return (
      width: size.width,
      height: math.max(headerChipMinimum, size.paintHeight + 2 * _pillInset),
      paintHeight: size.paintHeight,
      stackedReset: size.stackedReset,
      stackedChoice: size.stackedChoice,
      maxLines: size.maxLines,
      ellipsized: size.ellipsized,
    );
  }

  @override
  State<HeaderChoiceButton> createState() => _HeaderChoiceButtonState();
}

class _HeaderChoiceButtonState extends State<HeaderChoiceButton> {
  FocusNode? _ownedFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final onPressed = widget.busy ? null : option.onPressed;
    final enabled = onPressed != null;
    final palette = HeaderPalette.of(context);
    final button = TextButton(
      focusNode: _focus,
      onPressed: onPressed,
      style: headerActionButtonStyle(context).copyWith(
        fixedSize: WidgetStatePropertyAll(widget.size),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        backgroundBuilder: (context, states, child) {
          final paint = resolveHeaderChoicePaint(
            palette,
            states,
            selected: option.selected,
            solidSelection: widget.solidSelection,
          );
          final check = option.selected
              ? Icon(Icons.check, size: 16, color: paint.check)
              : null;
          final color = option.dotColor;
          final dot = color == null
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: paint.caption),
                  ),
                  child: const SizedBox.square(dimension: 7),
                );
          return ColoredBox(
            color: palette.surface,
            child: HeaderActionContour(
              states: states,
              inset: const EdgeInsets.all(3.5),
              borderRadius: widget.pillRadius + 3.5,
              child: Padding(
                padding: const EdgeInsets.all(HeaderChoiceButton._pillInset),
                child: HeaderPill(
                  fill: paint.fill,
                  perimeter: paint.perimeter,
                  disabled: paint.dashed,
                  radius: widget.pillRadius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HeaderChoiceButton._captionInset,
                    ),
                    child: HeaderBandChoiceContent(
                      stacked: widget.stacked,
                      leading: dot ?? check,
                      trailing: dot == null ? null : check,
                      caption: Text(
                        option.label,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: headerBandLabelStyle(
                          context,
                        ).copyWith(color: paint.caption),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      child: const SizedBox.shrink(),
    );
    return ListenableBuilder(
      listenable: _focus,
      child: button,
      builder: (context, child) => Semantics(
        container: true,
        excludeSemantics: true,
        label: option.semanticLabel,
        hint: option.selected && enabled ? option.selectedHint : null,
        button: true,
        selected: kIsWeb ? null : option.selected,
        checked: kIsWeb ? option.selected : null,
        inMutuallyExclusiveGroup: true,
        enabled: enabled,
        focusable: enabled,
        focused: enabled && _focus.hasPrimaryFocus,
        onTap: onPressed,
        onFocus: enabled ? _focus.requestFocus : null,
        onDidGainAccessibilityFocus: () => revealHeaderBandTarget(context),
        child: child!,
      ),
    );
  }
}

/// Full-size choices in the list header, wrapped in their logical order.
class HeaderChoiceRow extends StatefulWidget
    implements MeasuredListHeaderBottom {
  const HeaderChoiceRow({
    super.key,
    required this.options,
    this.busy = false,
    this.busyLabel,
    this.solidSelection = false,
  });

  final List<HeaderChoiceOption> options;
  final bool busy;
  final String? busyLabel;

  /// Paints the selected choice with the solid fill used for pricing facets.
  final bool solidSelection;

  static const _edge = 2.0;

  HeaderBandPlan _planFor(BuildContext context, double paneWidth) =>
      planHeaderBand(context, paneWidth, [
        for (final option in options)
          (context, maxWidth) =>
              HeaderChoiceButton._measure(context, option.label, maxWidth),
      ], hasSplit: false);

  @override
  Size get preferredSize =>
      Size.fromHeight(options.isEmpty ? 0 : headerChipMinimum + 2 * _edge);

  @override
  double heightFor(BuildContext context, double paneWidth) =>
      options.isEmpty ? 0 : _planFor(context, paneWidth).height + 2 * _edge;

  @override
  State<HeaderChoiceRow> createState() => _HeaderChoiceRowState();
}

class _HeaderChoiceRowState extends State<HeaderChoiceRow> {
  final _park = FocusNode(
    debugLabel: 'Header choices loading',
    skipTraversal: true,
  );
  final _nodes = <String, FocusNode>{};
  late final _traversal = HeaderBandTraversalPolicy(_nodes.containsValue);
  String? _parkedId;
  double? _paneWidth;
  FocusNode? _pendingReveal;
  ({FocusNode node, HeaderBandScrollOffsets scrollOffsets})? _lastVisible;

  void _revealFocus(FocusNode focus) {
    if (_pendingReveal == focus) return;
    _pendingReveal = focus;
    revealHeaderBandFocus(
      context,
      focus,
      onComplete: (target) {
        if (_pendingReveal != focus) return;
        _pendingReveal = null;
        _lastVisible =
            target != null && isHeaderBandTargetVisible(target) == true
            ? (
                node: focus,
                scrollOffsets: captureHeaderBandScrollOffsets(target),
              )
            : null;
      },
    );
  }

  void _retainVisibleFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !_nodes.containsValue(focus)) return;
    final visible = isHeaderBandTargetVisible(focus.context);
    final last = _lastVisible;
    final wasVisible =
        last != null &&
        last.node == focus &&
        last.scrollOffsets.every(
          (entry) => entry.position.pixels == entry.pixels,
        );
    if (visible ?? wasVisible) _revealFocus(focus);
  }

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(HeaderChoiceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.busy && !oldWidget.busy) _retainVisibleFocus();
    if (widget.busy && !oldWidget.busy) {
      _parkedId = _nodes.entries
          .where((entry) => entry.value.hasPrimaryFocus)
          .firstOrNull
          ?.key;
      if (_parkedId != null) _park.requestFocus();
    } else if (!widget.busy && oldWidget.busy) {
      final id = _parkedId;
      _parkedId = null;
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !widget.busy &&
              _park.hasPrimaryFocus &&
              (ModalRoute.of(context)?.isCurrent ?? true)) {
            (_nodes[id] ?? _nodes.values.firstOrNull)?.requestFocus();
          }
        });
      }
    }
    _syncNodes();
  }

  KeyEventResult _leaveParkedFocus(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    // Include the anchor only as the starting point for this traversal.
    node.skipTraversal = false;
    try {
      final moved = HardwareKeyboard.instance.isShiftPressed
          ? node.previousFocus()
          : node.nextFocus();
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
    } finally {
      node.skipTraversal = true;
    }
  }

  void _syncNodes() {
    final ids = widget.options.map((option) => option.id).toSet();
    for (final id in ids) {
      _nodes.putIfAbsent(id, () {
        final node = FocusNode(debugLabel: id);
        node.addListener(() {
          if (mounted && node.hasPrimaryFocus) {
            _revealFocus(node);
          }
        });
        return node;
      });
    }
    for (final id in _nodes.keys.where((id) => !ids.contains(id)).toList()) {
      final removed = _nodes.remove(id)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    }
  }

  @override
  void dispose() {
    _traversal.dispose();
    _park.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (_paneWidth != null && width != _paneWidth) _retainVisibleFocus();
        _paneWidth = width;
        final plan = widget._planFor(context, width);
        final palette = HeaderPalette.of(context);
        final fontLine = measureHeaderText(
          context,
          'Ag',
          headerBandLabelStyle(context),
          maxLines: 1,
        ).size.height.ceilToDouble();
        final singleLinePill = math.max(
          headerChipMinimumPaintHeight,
          fontLine + 4,
        );
        final groups = <String, List<Widget>>{};
        for (final (index, option) in widget.options.indexed) {
          final slot = plan.slots[index];
          groups
              .putIfAbsent(option.groupId, () => [])
              .add(
                Positioned(
                  key: ValueKey(option.id),
                  left: slot.x,
                  top: slot.y,
                  width: slot.size.width,
                  height: slot.size.height,
                  child: Semantics(
                    container: true,
                    sortKey: OrdinalSortKey(index.toDouble()),
                    child: FocusTraversalOrder(
                      order: NumericFocusOrder(index.toDouble()),
                      child: HeaderChoiceButton(
                        option: option,
                        size: Size(slot.size.width, slot.size.height),
                        stacked: slot.size.stackedChoice,
                        pillRadius:
                            math.min(slot.size.paintHeight, singleLinePill) / 2,
                        focusNode: _nodes[option.id],
                        busy: widget.busy,
                        solidSelection: widget.solidSelection,
                      ),
                    ),
                  ),
                ),
              );
        }
        return FocusTraversalGroup(
          policy: _traversal,
          child: FocusTraversalOrder(
            order: const NumericFocusOrder(-1),
            child: Focus(
              focusNode: _park,
              onKeyEvent: _leaveParkedFocus,
              includeSemantics: false,
              child: ColoredBox(
                color: palette.surface,
                child: Column(
                  children: [
                    const SizedBox(height: HeaderChoiceRow._edge),
                    Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: SizedBox(
                        width: double.infinity,
                        height: plan.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final (index, entry) in groups.entries.indexed)
                              Semantics(
                                key: ValueKey(entry.key),
                                container: true,
                                explicitChildNodes: true,
                                sortKey: OrdinalSortKey(index.toDouble()),
                                child: Stack(children: entry.value),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: HeaderChoiceRow._edge,
                      child: widget.busyLabel == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Semantics(
                                container: true,
                                liveRegion: true,
                                label: widget.busyLabel,
                                child: ExcludeSemantics(
                                  child: LinearProgressIndicator(
                                    minHeight: HeaderChoiceRow._edge,
                                    color: widget.solidSelection
                                        ? palette.ink
                                        : palette.muted,
                                    backgroundColor: palette.surface,
                                    borderRadius: BorderRadius.zero,
                                    trackGap: 0,
                                    stopIndicatorRadius: 0,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
