import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

/// A drop-in [Scaffold] replacement for every DocType **list** screen.
///
/// Guarantees that `drawer: AppNavDrawer()` is always present, which is the
/// prerequisite for `automaticallyImplyLeading: false` on [DocTypeListHeader]
/// to show the hamburger menu icon instead of a back arrow.
///
/// ## Migration
///
/// Replace the raw [Scaffold] call in any list screen:
///
/// ```dart
/// // Before
/// return Scaffold(
///   backgroundColor: colorScheme.surfaceContainerLow,
///   drawer: const AppNavDrawer(),
///   body: ...,
///   floatingActionButton: ...,
/// );
///
/// // After
/// return AppShellScaffold(
///   body: ...,
///   floatingActionButton: ...,
/// );
/// ```
///
/// ## What is NOT forwarded
///
/// Parameters that belong exclusively to form or modal screens
/// (`endDrawer`, `appBar`, `bottomSheet`, `persistentFooterButtons`)
/// are intentionally excluded. Use a plain [Scaffold] for those.
///
/// See `docs/app_bar_conventions.md` for the full convention.
class AppShellScaffold extends StatefulWidget {
  // ── Required ───────────────────────────────────────────────────────────
  final Widget body;

  // ── Optional — forwarded verbatim to Scaffold ─────────────────────────

  /// Defaults to [ColorScheme.surfaceContainerLow], matching the convention
  /// used by all existing list screens.
  final Color? backgroundColor;

  /// Floating action button. Supports both [FloatingActionButton] and
  /// [FloatingActionButton.extended].
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// List header sliver that takes precedence over the FAB when they overlap.
  final GlobalKey? floatingActionButtonHeaderKey;

  /// Persistent bottom widget (e.g. the barcode scan bar on Stock Entry).
  final Widget? bottomNavigationBar;

  /// Whether the [body] should extend behind the [bottomNavigationBar].
  final bool extendBody;

  /// Whether the scaffold should resize when the keyboard appears.
  final bool resizeToAvoidBottomInset;

  const AppShellScaffold({
    super.key,
    required this.body,
    this.backgroundColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.floatingActionButtonHeaderKey,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  State<AppShellScaffold> createState() => _AppShellScaffoldState();
}

class _AppShellScaffoldState extends State<AppShellScaffold> {
  final _fabPaintKey = GlobalKey();
  bool _fabHidden = false;

  bool _onBodyLayoutChanged(Notification notification) {
    if (notification is ScrollNotification ||
        notification is ScrollMetricsNotification ||
        notification is SizeChangedLayoutNotification) {
      _fabPaintKey.currentContext?.findRenderObject()?.markNeedsPaint();
    }
    return false;
  }

  void _onFabVisibilityChanged(bool hidden) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fabHidden != hidden) {
        setState(() => _fabHidden = hidden);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerKey = widget.floatingActionButtonHeaderKey;
    final fab = widget.floatingActionButton;
    final guardFab = headerKey != null && fab != null;
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? cs.surfaceContainerLow,
      drawer: const AppNavDrawer(),
      body: guardFab
          ? NotificationListener<Notification>(
              onNotification: _onBodyLayoutChanged,
              child: widget.body,
            )
          : widget.body,
      floatingActionButton: guardFab
          ? _HeaderFab(
              key: _fabPaintKey,
              headerKey: headerKey,
              onVisibilityChanged: _onFabVisibilityChanged,
              child: ExcludeFocus(excluding: _fabHidden, child: fab),
            )
          : fab,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      bottomNavigationBar: widget.bottomNavigationBar,
      extendBody: widget.extendBody,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
    );
  }
}

class _HeaderFab extends SingleChildRenderObjectWidget {
  const _HeaderFab({
    super.key,
    required this.headerKey,
    required this.onVisibilityChanged,
    required super.child,
  });

  final GlobalKey headerKey;
  final ValueChanged<bool> onVisibilityChanged;

  @override
  _RenderHeaderFab createRenderObject(BuildContext context) => _RenderHeaderFab(
    Scaffold.of(context),
    Scaffold.geometryOf(context),
    headerKey,
    onVisibilityChanged,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderHeaderFab renderObject) {
    if (renderObject.headerKey == headerKey) return;
    renderObject.headerKey = headerKey;
    renderObject.markNeedsPaint();
  }
}

class _RenderHeaderFab extends RenderProxyBox {
  _RenderHeaderFab(
    this.scaffold,
    this.geometry,
    this.headerKey,
    this.onVisibilityChanged,
  );

  final ScaffoldState scaffold;
  final ValueListenable<ScaffoldGeometry> geometry;
  final ValueChanged<bool> onVisibilityChanged;
  GlobalKey headerKey;
  bool _hidden = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    geometry.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    geometry.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Both the sliver and Scaffold have finished layout. Use the actual FAB
    // position, including changes due to insets or a fixed SnackBar.
    final scaffoldBox = scaffold.context.findRenderObject();
    final fab = geometry.value.floatingActionButtonArea;
    final headerBottom = scaffoldBox == null
        ? null
        : DocTypeListHeader.extentInViewport(headerKey, scaffoldBox);
    final hidden =
        fab != null && headerBottom != null && headerBottom > fab.top;
    if (_hidden != hidden) {
      _hidden = hidden;
      markNeedsSemanticsUpdate();
      onVisibilityChanged(hidden);
    }
    if (!_hidden) super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_hidden && super.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_hidden) super.visitChildrenForSemantics(visitor);
  }
}
