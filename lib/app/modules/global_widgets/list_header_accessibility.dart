import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

/// The surface and contrast-sensitive colours shared by the list header and
/// the toolbar on its search route.
class HeaderPalette {
  HeaderPalette(ThemeData theme)
    : colors = theme.colorScheme,
      scheme = AppScheme.of(theme.brightness).copyWith(
        primary: theme.colorScheme.primary,
        onPrimary: theme.colorScheme.onPrimary,
      );

  factory HeaderPalette.of(BuildContext context) =>
      HeaderPalette(Theme.of(context));

  final ColorScheme colors;
  final AppScheme scheme;

  Color get surface => scheme.fg;
  Color get muted => scheme.textMuted;
  Color get ink => scheme.text;
  Color get error => colors.error;
  Color get appliedFill =>
      Color.alphaBlend(scheme.primary.withValues(alpha: .12), surface);

  Color get appliedInk {
    final primary = scheme.primary;
    if (colors.brightness == Brightness.light) {
      if (primary == AppAccent.blue.lightPrimary) return AppColors.blue700;
      if (primary == AppAccent.purple.lightPrimary) return AppColors.purple700;
    } else if (primary == AppAccent.brand.darkPrimary) {
      return AppColors.red300;
    }

    final background = appliedFill.computeLuminance();
    final foreground = primary.computeLuminance();
    final ratio =
        (math.max(background, foreground) + .05) /
        (math.min(background, foreground) + .05);
    return ratio >= 4.5 ? primary : ink;
  }

  Color addFill(Set<WidgetState> states) =>
      _actionFill(states, colors.onSurface);

  Color bulkFill(Set<WidgetState> states) =>
      _actionFill(states, error, pressedAlpha: 26);

  Color _actionFill(
    Set<WidgetState> states,
    Color color, {
    int pressedAlpha = 20,
  }) {
    if (states.contains(WidgetState.disabled)) return surface;
    if (states.contains(WidgetState.pressed)) {
      return Color.alphaBlend(color.withAlpha(pressedAlpha), surface);
    }
    if (states.contains(WidgetState.hovered)) {
      return Color.alphaBlend(color.withAlpha(20), surface);
    }
    return surface;
  }

  Color appliedFillFor(bool enabled) => enabled ? appliedFill : surface;
  Color appliedInkFor(bool enabled) => enabled ? appliedInk : muted;
  Color appliedPerimeterFor(bool enabled) => enabled ? scheme.primary : muted;

  Color get toolbarBadgeFill => colors.brightness == Brightness.dark
      ? AppColors.red300
      : AppColors.red700;

  Color get toolbarBadgeInk =>
      colors.brightness == Brightness.dark ? scheme.bg : scheme.onPrimary;

  Color get toolbarBadgeRing => surface;

  TextSelectionThemeData get searchSelection => TextSelectionThemeData(
    cursorColor: scheme.primary,
    selectionHandleColor: scheme.primary,
    selectionColor: Color.alphaBlend(
      scheme.primary.withValues(alpha: .20),
      surface,
    ),
  );

  Color get quickPressedLayer => colors.onSurface.withAlpha(20);
}

/// Disables filter commands without disabling the surrounding list toolbar.
class ListHeaderFilterScope extends InheritedWidget {
  const ListHeaderFilterScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ListHeaderFilterScope>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(ListHeaderFilterScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Lets shared selectable chips in the bottom slot opt in to the header style.
class ListHeaderBottomScope extends InheritedWidget {
  const ListHeaderBottomScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListHeaderBottomScope>() !=
      null;

  @override
  bool updateShouldNotify(ListHeaderBottomScope oldWidget) => false;
}

/// Restores the OS scaler at the header boundary where the app root has
/// replaced it with the app preference. Isolated widgets inherit their host.
class ListHeaderTextScope extends StatefulWidget {
  const ListHeaderTextScope({super.key, required this.child});

  final Widget child;

  @override
  State<ListHeaderTextScope> createState() => _ListHeaderTextScopeState();
}

class _ListHeaderTextScopeState extends State<ListHeaderTextScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeTextScaleFactor() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ThemeController>()) return widget.child;
    final controller = Get.find<ThemeController>();
    final platformScaler = MediaQueryData.fromView(View.of(context)).textScaler;
    final ambient = MediaQuery.of(context);
    return Obx(() {
      final preset = controller.textSize.value.factor;
      return MediaQuery(
        data: ambient.copyWith(
          textScaler: preset == 1
              ? platformScaler
              : HeaderTextScaler(platformScaler, preset),
        ),
        child: widget.child,
      );
    });
  }
}

class HeaderTextScaler extends TextScaler {
  const HeaderTextScaler(this.platformScaler, this.preset);

  final TextScaler platformScaler;
  final double preset;

  @override
  double scale(double fontSize) => platformScaler.scale(fontSize) * preset;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is HeaderTextScaler &&
      other.platformScaler == platformScaler &&
      other.preset == preset;

  @override
  int get hashCode => Object.hash(platformScaler, preset);
}

typedef HeaderTextMetrics = ({Size size, bool didExceedMaxLines});

HeaderTextMetrics measureHeaderText(
  BuildContext context,
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
  int? maxLines,
  String? ellipsis,
  TextScaler? textScaler,
}) {
  final ambient = DefaultTextStyle.of(context);
  final lineHeight = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  var effectiveStyle = style.inherit ? ambient.style.merge(style) : style;
  if (MediaQuery.boldTextOf(context)) {
    effectiveStyle = effectiveStyle.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }
  effectiveStyle = effectiveStyle.merge(
    TextStyle(
      height: lineHeight,
      letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
      wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
    ),
  );
  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle),
    textAlign: ambient.textAlign ?? TextAlign.start,
    textDirection: Directionality.of(context),
    textScaler: textScaler ?? MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: maxLines ?? ambient.maxLines,
    ellipsis: ellipsis,
    textWidthBasis: ambient.textWidthBasis,
    textHeightBehavior:
        ambient.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
  )..layout(maxWidth: maxWidth);
  final result = (
    size: painter.size,
    didExceedMaxLines: painter.didExceedMaxLines,
  );
  painter.dispose();
  return result;
}

double headerContourWidth(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) return 0;
  if (states.contains(WidgetState.pressed)) return 3;
  if (states.contains(WidgetState.focused)) return 2;
  return states.contains(WidgetState.hovered) ? 1 : 0;
}

/// A surface-separated focus and pointer contour around an action.
class HeaderActionContour extends StatelessWidget {
  static const _inset = EdgeInsets.all(2.5);

  const HeaderActionContour({
    super.key,
    required this.states,
    required this.child,
    this.borderRadius = 999,
    this.inset = _inset,
    this.paintBehindChild = false,
  });

  final Set<WidgetState> states;
  final Widget child;
  final double borderRadius;
  final EdgeInsets inset;
  final bool paintBehindChild;

  @override
  Widget build(BuildContext context) {
    final width = headerContourWidth(states);
    final palette = HeaderPalette.of(context);
    final contour = width == 0
        ? null
        : _ActionContourPainter(
            width: width,
            focusedAndPressed:
                states.contains(WidgetState.focused) &&
                states.contains(WidgetState.pressed),
            surface: palette.surface,
            ink: palette.muted,
            radius: borderRadius,
            inset: inset,
          );
    return CustomPaint(
      painter: paintBehindChild ? contour : null,
      foregroundPainter: paintBehindChild ? null : contour,
      child: child,
    );
  }
}

class _ActionContourPainter extends CustomPainter {
  const _ActionContourPainter({
    required this.width,
    required this.focusedAndPressed,
    required this.surface,
    required this.ink,
    required this.radius,
    required this.inset,
  });

  final double width;
  final bool focusedAndPressed;
  final Color surface;
  final Color ink;
  final double radius;
  final EdgeInsets inset;

  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = inset.deflateRect(Offset.zero & size);
    _paintContour(
      canvas,
      outerRect,
      radius: radius,
      width: width,
      focusedAndPressed: focusedAndPressed,
      markOutside: true,
      surface: surface,
      ink: ink,
    );
  }

  @override
  bool shouldRepaint(_ActionContourPainter old) =>
      width != old.width ||
      focusedAndPressed != old.focusedAndPressed ||
      surface != old.surface ||
      ink != old.ink ||
      radius != old.radius ||
      inset != old.inset;
}

void _paintContour(
  Canvas canvas,
  Rect rect, {
  required double radius,
  required double width,
  required bool focusedAndPressed,
  bool markOutside = false,
  required Color surface,
  required Color ink,
}) {
  if (rect.isEmpty) return;
  final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  final separation = Paint()
    ..color = surface
    ..style = PaintingStyle.stroke
    ..strokeWidth = width + 2;
  final stroke = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  canvas.drawRRect(shape, separation);
  canvas.drawRRect(shape, stroke);
  if (focusedAndPressed) {
    final center = rect.center.dx;
    final y = markOutside ? rect.bottom + 2 : rect.bottom - 4;
    final from = Offset(center - 5, y);
    final to = Offset(center + 5, y);
    canvas.drawLine(from, to, separation..strokeWidth = 3);
    canvas.drawLine(from, to, stroke..strokeWidth = 1);
  }
}

class HeaderPill extends StatelessWidget {
  const HeaderPill({
    super.key,
    required this.fill,
    required this.perimeter,
    this.disabled = false,
    this.child,
  });

  final Color fill;
  final Color perimeter;
  final bool disabled;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PillPainter(fill, perimeter, disabled),
      child: child,
    );
  }
}

class _PillPainter extends CustomPainter {
  const _PillPainter(this.fill, this.perimeter, this.disabled);

  final Color fill;
  final Color perimeter;
  final bool disabled;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.5),
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(shape, Paint()..color = fill);
    final stroke = Paint()
      ..color = perimeter
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (!disabled) {
      canvas.drawRRect(shape, stroke);
      return;
    }
    final outline = Path()..addRRect(shape);
    for (final contour in outline.computeMetrics()) {
      for (var start = 0.0; start < contour.length; start += 6) {
        canvas.drawPath(
          contour.extractPath(start, math.min(start + 3, contour.length)),
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      fill != old.fill ||
      perimeter != old.perimeter ||
      disabled != old.disabled;
}

ButtonStyle headerActionButtonStyle(
  BuildContext context, {
  Color? foregroundColor,
  Color? disabledForegroundColor,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  WidgetStateProperty<Color?>? backgroundColor,
}) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.square(48)),
    padding: WidgetStatePropertyAll(padding),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundColor:
        backgroundColor ?? const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: foregroundColor == null && disabledForegroundColor == null
        ? null
        : WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? disabledForegroundColor
                : foregroundColor,
          ),
    splashFactory: NoSplash.splashFactory,
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    animationDuration: Duration.zero,
  );
}

/// The unowned toolbar actions keep their widget-level colors and callbacks.
class HeaderActionTheme extends StatelessWidget {
  const HeaderActionTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icons = IconButtonTheme.of(context);
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: headerActionButtonStyle(context)
              .merge(icons.style)
              .copyWith(
                backgroundBuilder: (context, states, child) =>
                    HeaderActionContour(states: states, child: child!),
              ),
        ),
        child: _HeaderPopupTheme(theme: theme, icons: icons, child: child),
      ),
    );
  }
}

/// Restores the source theme when a header control opens a popup route.
class _HeaderPopupTheme extends InheritedTheme {
  const _HeaderPopupTheme({
    required this.theme,
    this.icons,
    required super.child,
  });

  final ThemeData theme;
  final IconButtonThemeData? icons;

  @override
  Widget wrap(BuildContext context, Widget child) {
    final iconTheme = icons;
    return Theme(
      data: theme,
      child: iconTheme == null
          ? child
          : IconButtonTheme(data: iconTheme, child: child),
    );
  }

  @override
  bool updateShouldNotify(_HeaderPopupTheme oldWidget) =>
      theme != oldWidget.theme || icons != oldWidget.icons;
}

/// An owned toolbar icon whose full measured slot is interactive.
class HeaderIconAction extends StatelessWidget {
  const HeaderIconAction({
    super.key,
    required this.child,
    required this.tooltip,
    required this.onPressed,
    this.focusNode,
    this.foregroundColor,
    this.backgroundColor,
    this.width = 48,
    this.height = 48,
    this.iconSize = 24,
    this.discAlignment = Alignment.center,
    this.disabledFilter = false,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final double width;
  final double height;
  final double iconSize;
  final AlignmentGeometry discAlignment;
  final bool disabledFilter;

  @override
  Widget build(BuildContext context) {
    final palette = HeaderPalette.of(context);
    final disabled = disabledFilter && onPressed == null;
    return IconButton(
      iconSize: iconSize,
      tooltip: tooltip,
      onPressed: onPressed,
      focusNode: focusNode,
      style:
          headerActionButtonStyle(
            context,
            foregroundColor: foregroundColor ?? palette.ink,
            disabledForegroundColor: disabled ? palette.muted : null,
          ).copyWith(
            fixedSize: WidgetStatePropertyAll(Size(width, height)),
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
            backgroundBuilder: (context, states, child) => HeaderActionContour(
              states: states,
              paintBehindChild: true,
              child: child!,
            ),
          ),
      icon: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundColor != null || disabled)
              Align(
                alignment: discAlignment,
                child: SizedBox.square(
                  dimension: 40,
                  child: HeaderPill(
                    fill: disabled ? palette.surface : backgroundColor!,
                    perimeter: disabled ? palette.muted : backgroundColor!,
                    disabled: disabled,
                  ),
                ),
              ),
            Center(child: child),
          ],
        ),
      ),
    );
  }
}

enum HeaderChipPaint { add, bulk, split }

/// A native button with a header-local name and interaction contour.
class HeaderChipButton extends StatelessWidget {
  const HeaderChipButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    required this.paint,
    this.focusNode,
    this.paintedHeight = 34,
    this.tooltip,
    this.semanticDismiss,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final HeaderChipPaint paint;
  final FocusNode? focusNode;
  final double paintedHeight;
  final String? tooltip;
  final VoidCallback? semanticDismiss;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = HeaderPalette.of(context);
    final disabled = onPressed == null;
    final button = TextButton(
      onPressed: onPressed,
      focusNode: focusNode,
      style:
          headerActionButtonStyle(
            context,
            padding: padding,
            foregroundColor: paint == HeaderChipPaint.bulk
                ? palette.error
                : palette.muted,
            disabledForegroundColor: palette.muted,
          ).copyWith(
            fixedSize: WidgetStatePropertyAll(
              Size(
                width ?? double.infinity,
                height ?? math.max(48, paintedHeight),
              ),
            ),
            shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
            backgroundBuilder: (context, states, child) {
              return HeaderActionContour(
                states: states,
                borderRadius: paint == HeaderChipPaint.split ? 10 : 999,
                inset: paint == HeaderChipPaint.split
                    ? const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2.5)
                    : HeaderActionContour._inset,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (paint != HeaderChipPaint.split)
                      Positioned.fill(
                        child: Align(
                          child: SizedBox(
                            width: double.infinity,
                            height: paintedHeight,
                            child: HeaderPill(
                              fill: paint == HeaderChipPaint.add
                                  ? palette.addFill(states)
                                  : palette.bulkFill(states),
                              perimeter:
                                  paint == HeaderChipPaint.add || disabled
                                  ? palette.muted
                                  : palette.bulkFill(states),
                              disabled: disabled,
                            ),
                          ),
                        ),
                      ),
                    child!,
                  ],
                ),
              );
            },
          ),
      child: Semantics(
        label: label,
        onDismiss: disabled ? null : semanticDismiss,
        child: ExcludeSemantics(child: child),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip, excludeFromSemantics: true, child: button);
  }
}

/// Preserves native chip state and selection roles while bounding Ink to one
/// pressed highlight and moving the focus contour outside the painted chip.
class ListHeaderQuickChipTheme extends StatelessWidget {
  const ListHeaderQuickChipTheme({super.key, required this.child});

  final Widget child;

  static ThemeData resolve(ThemeData theme) {
    final palette = HeaderPalette(theme);
    return theme.copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: palette.quickPressedLayer,
      chipTheme: theme.chipTheme.copyWith(
        side: WidgetStateBorderSide.resolveWith((states) {
          final width = headerContourWidth(states);
          if (width > 0) {
            return _QuickChipContourSide(
              color: palette.muted,
              width: width,
              // Material 3 selected RawChips keep a transparent 1 dp side.
              restingInset:
                  theme.useMaterial3 || !states.contains(WidgetState.selected)
                  ? 1
                  : 0,
              focusAndPress:
                  states.contains(WidgetState.focused) &&
                  states.contains(WidgetState.pressed),
            );
          }
          if (states.contains(WidgetState.selected) ||
              states.contains(WidgetState.disabled)) {
            return null;
          }
          return BorderSide(color: palette.muted);
        }),
        shape: _QuickChipBorder(surface: palette.surface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: resolve(theme),
      child: _HeaderPopupTheme(theme: theme, child: child),
    );
  }
}

class _QuickChipContourSide extends BorderSide {
  const _QuickChipContourSide({
    required super.color,
    required super.width,
    required this.restingInset,
    required this.focusAndPress,
  });

  final double restingInset;
  final bool focusAndPress;

  @override
  bool operator ==(Object other) =>
      other is _QuickChipContourSide &&
      color == other.color &&
      width == other.width &&
      restingInset == other.restingInset &&
      focusAndPress == other.focusAndPress;

  @override
  int get hashCode => Object.hash(color, width, restingInset, focusAndPress);
}

class _QuickChipBorder extends RoundedRectangleBorder {
  const _QuickChipBorder({required this.surface, super.side})
    : super(borderRadius: const BorderRadius.all(Radius.circular(8)));

  final Color surface;

  @override
  EdgeInsetsGeometry get dimensions => side is _QuickChipContourSide
      ? EdgeInsets.all((side as _QuickChipContourSide).restingInset)
      : super.dimensions;

  @override
  _QuickChipBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => _QuickChipBorder(surface: surface, side: side ?? this.side);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final active = side;
    if (active is! _QuickChipContourSide) {
      super.paint(canvas, rect, textDirection: textDirection);
      return;
    }
    _paintContour(
      canvas,
      rect.inflate(active.width / 2),
      radius: 8 + active.width / 2,
      width: active.width,
      focusedAndPressed: active.focusAndPress,
      surface: surface,
      ink: active.color,
    );
  }
}
