import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── Banner variant ────────────────────────────────────────────────────────────
/// Semantic type of an [InlineBanner]. Maps directly to the colour tokens
/// already used by [StatusPill] so the palette is never duplicated.
enum BannerType { success, error, warning, info }

// ── Design tokens (mirrored from status_pill.dart) ────────────────────────────
const _kSuccessBg   = Color(0xFFE5F8ED);
const _kSuccessText = Color(0xFF36A564);

const _kErrorBg     = Color(0xFFFFF5F5);
const _kErrorText   = Color(0xFFE54D4D);

const _kWarningBg   = Color(0xFFFFF3E1);
const _kWarningText = Color(0xFFFFA00A);

const _kInfoBg      = Color(0xFFEBF5FF);
const _kInfoText    = Color(0xFF3688E5);

// ── Token helpers ─────────────────────────────────────────────────────────────
Color _bgFor(BannerType t) => switch (t) {
  BannerType.success => _kSuccessBg,
  BannerType.error   => _kErrorBg,
  BannerType.warning => _kWarningBg,
  BannerType.info    => _kInfoBg,
};

Color _textFor(BannerType t) => switch (t) {
  BannerType.success => _kSuccessText,
  BannerType.error   => _kErrorText,
  BannerType.warning => _kWarningText,
  BannerType.info    => _kInfoText,
};

IconData _iconFor(BannerType t) => switch (t) {
  BannerType.success => Icons.check_circle_outline,
  BannerType.error   => Icons.cancel_outlined,
  BannerType.warning => Icons.warning_amber_outlined,
  BannerType.info    => Icons.info_outline,
};

// ── Widget ────────────────────────────────────────────────────────────────────
/// A zero-overlay, in-scaffold feedback banner.
///
/// Bind the three controller observables and drop the widget anywhere in
/// a [Column] or [CustomScrollView] body. The banner slides in/out with
/// an [AnimatedSwitcher] and auto-dismisses when [visible] becomes false.
///
/// ```dart
/// // In controller (uses ControllerFeedbackMixin):
/// showBanner('Delivery Note saved', type: BannerType.success);
///
/// // In view:
/// Obx(() => InlineBanner(
///   visible: controller.bannerVisible.value,
///   message: controller.bannerMessage.value,
///   type:    controller.bannerType.value,
/// ))
/// ```
///
/// **Why not GetX snackbar?**
/// `SnackbarController.configureOverlay()` calls `Overlay.of()` synchronously.
/// When invoked on the same frame a bottom-sheet route is popped the Theater
/// widget has already deactivated its overlay subtree, so `Overlay.of()` throws
/// *"No Overlay widget found"*. This widget lives inside the route's own
/// Scaffold tree and is therefore immune to that lifecycle hazard.
class InlineBanner extends StatelessWidget {
  /// Whether the banner is currently visible. Typically bound to
  /// `controller.bannerVisible.value` via an outer [Obx].
  final bool visible;

  /// The text to display inside the banner.
  final String message;

  /// Semantic type — controls colour and leading icon.
  final BannerType type;

  /// Optional override icon. Defaults to the canonical icon for [type].
  final IconData? icon;

  const InlineBanner({
    super.key,
    required this.visible,
    required this.message,
    this.type    = BannerType.info,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg      = _bgFor(type);
    final fg      = _textFor(type);
    final leadIcon = icon ?? _iconFor(type);

    // AnimatedSwitcher drives a combined slide-down + fade so the banner
    // appears/disappears without causing layout jumps in scroll views.
    // The ClipRect + Align height-tween collapses the banner to zero height
    // when hidden, matching the approach used in SaveIconButton transitions.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve:  Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, -0.4),
          end:   Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: animation.value,
            child: FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            ),
          ),
        );
      },
      child: visible
          ? _BannerContent(
              key:      ValueKey('${type.name}:$message'),
              bg:       bg,
              fg:       fg,
              leadIcon: leadIcon,
              message:  message,
            )
          : const SizedBox.shrink(key: ValueKey('__empty__')),
    );
  }
}

// ── Private content widget (extracted for clean key targeting) ────────────────
class _BannerContent extends StatelessWidget {
  final Color    bg;
  final Color    fg;
  final IconData leadIcon;
  final String   message;

  const _BannerContent({
    super.key,
    required this.bg,
    required this.fg,
    required this.leadIcon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width:   double.infinity,
      // Horizontal padding matches InfoBlock (12 px); vertical matches the
      // denser StatusPill rhythm (10 px) so the banner feels like a
      // full-width pill rather than a tall card.
      margin:  const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(leadIcon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color:      fg,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
