import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shared async-action controls that bake in the three things easy to get
/// wrong when a tap triggers a wait: a visible spinner, a disabled state
/// (re-entrancy protection), and feedback that actually repaints.
///
/// Both widgets carry their own [Obx], so they repaint even inside render
/// layers that skip rebuilds for content-only changes — notably a
/// `SliverPersistentHeader` whose `shouldRebuild` keys on action *count*
/// (a bare reactive read placed in `extraActions` would never repaint the
/// icon→spinner swap). Drive them with a controller's `RxBool` busy flag;
/// the controller still owns setting/clearing it (in a `finally`) and any
/// cross-surface re-entrancy guard.

/// [IconButton] that shows a spinner and disables itself while [busy] is true.
///
/// The spinner defaults to the ambient `IconTheme` colour, matching whatever
/// the surrounding icons use (`onPrimary` on the maroon form header, dark ink
/// on a white toolbar), so it stays visible without per-call contrast handling.
class AsyncIconButton extends StatelessWidget {
  final RxBool busy;
  final VoidCallback onPressed;
  final Widget icon;
  final String? tooltip;
  final Color? spinnerColor;
  final double spinnerSize;

  const AsyncIconButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.spinnerColor,
    this.spinnerSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isBusy = busy.value;
      return IconButton(
        tooltip: tooltip,
        onPressed: isBusy ? null : onPressed,
        icon: isBusy
            ? SizedBox(
                width: spinnerSize,
                height: spinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: spinnerColor ?? IconTheme.of(context).color,
                ),
              )
            : icon,
      );
    });
  }
}

/// [FilledButton.icon] that shows a spinner + [loadingLabel] and disables
/// itself while [busy] is true.
///
/// The spinner defaults to `colorScheme.onPrimary` — the FilledButton's
/// foreground on its primary-coloured background.
class AsyncFilledButton extends StatelessWidget {
  final RxBool busy;
  final VoidCallback onPressed;
  final Widget icon;
  final String label;
  final String? loadingLabel;
  final ButtonStyle? style;
  final Color? spinnerColor;
  final double spinnerSize;

  const AsyncFilledButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.loadingLabel,
    this.style,
    this.spinnerColor,
    this.spinnerSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isBusy = busy.value;
      return FilledButton.icon(
        onPressed: isBusy ? null : onPressed,
        icon: isBusy
            ? SizedBox(
                width: spinnerSize,
                height: spinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: spinnerColor ??
                      Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : icon,
        label: Text(isBusy ? (loadingLabel ?? label) : label),
        style: style,
      );
    });
  }
}
