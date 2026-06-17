import 'dart:math' as math;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // clampDouble
import 'package:flutter/services.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

export 'package:multimax/app/data/enums/save_result.dart';

// ── Layout constants ──────────────────────────────────────────────────────────

/// Height of the collapsed two-line toolbar (caption + doc name).
const double _kCollapsedToolbar = 64.0;

/// Height of the single-line expanded toolbar row.
const double _kExpandedToolbar = 56.0;

/// Height of the large-title area (doctype label + doc name + status row).
const double _kExpandedExtra = 96.0;

/// Total height of expanded content = toolbar + large area.
const double _kMaxContent = _kExpandedToolbar + _kExpandedExtra; // 152dp

/// Minimum font size for AutoSizeText in the collapsed toolbar doc-name line.
const double _kAutoSizeMinFont = 11.0;

// ── Public widget ─────────────────────────────────────────────────────────────

/// A standalone sliver header for DocType **form** screens.
///
/// Produces exactly one [SliverPersistentHeader].
///
/// **Expanded state** (user at top):
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  ←  [faded title]             ↻  💾  ↗          │  56dp toolbar
/// ├──────────────────────────────────────────────────┤
/// │  WORK ORDER                                      │  11sp maroon label
/// │  WO-2024-00123                                   │  24sp bold doc name
/// │  [Draft]  ● Unsaved changes                      │  pill + amber indicator
/// └──────────────────────────────────────────────────┘
/// ```
///
/// **Collapsed state** (scrolled):
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  ←  WORK ORDER  [Draft]        ↻  💾  ↗         │  10sp maroon cap + pill
/// │     WO-2024-00123                                │  15sp bold navy name
/// └──────────────────────────────────────────────────┘  64dp total
/// ```
///
/// [docType] and [statusLabel] are nullable so existing call sites that omit
/// them compile and render without the label or pill (no breaking change).
class DocTypeFormHeader extends StatelessWidget {
  final String title;

  /// e.g. `'Work Order'` — shown as uppercase maroon label.
  /// Null → no label rendered.
  final String? docType;

  /// e.g. `'Draft'` — drives [StatusPill].
  /// Null → no pill rendered.
  final String? statusLabel;

  final VoidCallback? onReload;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final VoidCallback? onSubmit;

  final bool canSave;
  final bool canSubmit;
  final int docStatus;
  final bool isSaving;
  final bool isSubmitting;
  final SaveResult saveResult;

  final PreferredSizeWidget? bottom;
  final List<Widget>? extraActions;

  const DocTypeFormHeader({
    super.key,
    required this.title,
    this.docType,
    this.statusLabel,
    this.onReload,
    this.onSave,
    this.onShare,
    this.onSubmit,
    this.canSave      = false,
    this.canSubmit    = false,
    this.docStatus    = 0,
    this.isSaving     = false,
    this.isSubmitting = false,
    this.saveResult   = SaveResult.idle,
    this.bottom,
    this.extraActions,
  });

  bool get _canSave => canSave && docStatus == 0;

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _DocTypeFormHeaderDelegate(
        title:           title,
        docType:         docType,
        statusLabel:     statusLabel,
        onReload:        onReload,
        onSave:          onSave,
        onShare:         onShare,
        onSubmit:        onSubmit,
        canSave:         _canSave,
        canSubmit:       canSubmit,
        isSaving:        isSaving,
        isSubmitting:    isSubmitting,
        saveResult:      saveResult,
        bottom:          bottom,
        extraActions:    extraActions,
        statusBarHeight: statusBarHeight,
      ),
    );
  }
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _DocTypeFormHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final String? docType;
  final String? statusLabel;
  final VoidCallback? onReload;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final VoidCallback? onSubmit;
  final bool canSave;
  final bool canSubmit;
  final bool isSaving;
  final bool isSubmitting;
  final SaveResult saveResult;
  final PreferredSizeWidget? bottom;
  final List<Widget>? extraActions;
  final double statusBarHeight;

  const _DocTypeFormHeaderDelegate({
    required this.title,
    required this.docType,
    required this.statusLabel,
    required this.onReload,
    required this.onSave,
    required this.onShare,
    required this.onSubmit,
    required this.canSave,
    required this.canSubmit,
    required this.isSaving,
    required this.isSubmitting,
    required this.saveResult,
    required this.bottom,
    required this.extraActions,
    required this.statusBarHeight,
  });

  double get _bottomHeight => bottom?.preferredSize.height ?? 0.0;

  /// Mirrors `frappe.get_indicator`: returns `'Not Saved'` (orange pill) when
  /// the document is dirty and editable, otherwise the stored [statusLabel].
  String? get _effectiveStatusLabel => canSave ? 'Not Saved' : statusLabel;

  @override
  double get minExtent => statusBarHeight + _kCollapsedToolbar + _bottomHeight;

  @override
  double get maxExtent => statusBarHeight + _kMaxContent + _bottomHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final shrinkRange = maxExtent - minExtent; // 88dp
    final collapseProgress = shrinkRange > 0
        ? clampDouble(shrinkOffset / shrinkRange, 0.0, 1.0)
        : 1.0;
    final expandProgress = 1.0 - collapseProgress;

    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ── System UI ────────────────────────────────────────────────────────────
    final surfaceLuminance = colorScheme.surface.computeLuminance();
    final iconBrightness   = surfaceLuminance > 0.5 ? Brightness.dark : Brightness.light;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness:     iconBrightness == Brightness.dark
          ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: iconBrightness,
    );

    // ── Actions (same in both states) ────────────────────────────────────────
    final actions = _buildActions(context);

    // ── Toolbar (animated height 56dp → 64dp) ─────────────────────────────────
    final toolbarHeight = _kExpandedToolbar + 8.0 * collapseProgress;

    final toolbar = SizedBox(
      height: toolbarHeight,
      child: NavigationToolbar(
        leading: _buildLeading(context),
        middle: Stack(
          children: [
            // Expanded middle: faded doc name (opacity fades out on collapse)
            Positioned.fill(
              child: Opacity(
                opacity: expandProgress,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AutoSizeText(
                    title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    minFontSize: _kAutoSizeMinFont,
                    overflow: TextOverflow.clip,
                    softWrap: true,
                  ),
                ),
              ),
            ),
            // Collapsed middle: two-line caption + doc name (fades in on collapse)
            Positioned.fill(
              child: Offstage(
                offstage: collapseProgress < 0.001,
                child: Opacity(
                  opacity: collapseProgress,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (docType != null)
                          Text(
                            docType!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: colorScheme.primary,
                              height: 1.0,
                            ),
                          ),
                        if (docType != null && _effectiveStatusLabel != null)
                          const SizedBox(width: 5),
                        if (_effectiveStatusLabel != null)
                          StatusPill(status: _effectiveStatusLabel!, compact: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    AutoSizeText(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.secondary,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      minFontSize: _kAutoSizeMinFont,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                ),
              ),
            ),
          ],
        ),
        trailing: actions,
        centerMiddle: false,
        middleSpacing: 8,
      ),
    );

    // ── Large title area (96dp, fades with expandProgress) ───────────────────
    final largeArea = Opacity(
      opacity: expandProgress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (docType != null)
              Text(
                docType!.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.77,
                  color: colorScheme.primary,
                  height: 1.0,
                ),
              ),
            if (docType != null) const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            if (_effectiveStatusLabel != null)
              StatusPill(status: _effectiveStatusLabel!),
          ],
        ),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Material(
        color: colorScheme.surface,
        elevation: overlapsContent ? 1.0 : 0.0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: statusBarHeight), // status-bar shield
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: math.max(0.0, _kExpandedExtra * expandProgress),
                    child: largeArea,
                  ),
                  toolbar,
                  if (bottom != null) bottom!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Leading ───────────────────────────────────────────────────────────────
  Widget? _buildLeading(BuildContext context) {
    final parentRoute = ModalRoute.of(context);
    final canPop      = parentRoute?.canPop ?? false;
    if (canPop) {
      return IconButton(
        icon:      const Icon(Icons.arrow_back),
        tooltip:   MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.maybeOf(context)?.maybePop(),
      );
    }
    return null;
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Widget? _buildActions(BuildContext context) {
    final items = <Widget>[
      if (onSubmit != null && canSubmit)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton(
            onPressed: isSubmitting ? null : onSubmit,
            style: FilledButton.styleFrom(
              // ERPNext desk's Submit is a blue btn-primary. This app's theme
              // primary is maroon, so we intentionally hardcode blue here to
              // match ERPNext rather than use colorScheme.primary.
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit'),
          ),
        ),
      ...(extraActions ?? []),
      if (onReload != null)
        IconButton(
          icon:      const Icon(Icons.refresh),
          tooltip:   'Reload',
          onPressed: onReload,
        ),
      if (onSave != null)
        SaveIconButton(
          onPressed:           onSave,
          isSaving:            isSaving,
          isDirty:             canSave,
          saveResult:          saveResult,
          tooltip:             'Save',
          showFilledWhenDirty: true,
        ),
      if (onShare != null)
        IconButton(
          icon:      const Icon(Icons.share_outlined),
          tooltip:   'Share',
          onPressed: onShare,
        ),
    ];
    if (items.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: items);
  }

  // ── shouldRebuild ─────────────────────────────────────────────────────────
  @override
  bool shouldRebuild(covariant _DocTypeFormHeaderDelegate old) {
    return title          != old.title          ||
           docType        != old.docType        ||
           statusLabel    != old.statusLabel    ||
           canSave        != old.canSave        ||
           isSaving       != old.isSaving       ||
           saveResult     != old.saveResult     ||
           statusBarHeight != old.statusBarHeight ||
           bottom         != old.bottom         ||
           (extraActions?.length ?? 0) != (old.extraActions?.length ?? 0) ||
           (onReload != null) != (old.onReload != null) ||
           (onSave   != null) != (old.onSave   != null) ||
           (onShare  != null) != (old.onShare  != null) ||
           canSubmit      != old.canSubmit             ||
           isSubmitting   != old.isSubmitting           ||
           (onSubmit != null) != (old.onSubmit != null);
  }
}
