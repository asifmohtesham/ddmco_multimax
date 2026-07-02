import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// KeyboardSafeBottomSheet
///
/// Standard wrapper for modal sheets that contain TextField / TextFormField
/// widgets. It guarantees:
/// - Keyboard is dismissed before the sheet route is pushed
/// - Sheet is scrollable when vertical space is tight
/// - No double-counting of viewInsets.bottom (no phantom gaps above keyboard)
///
/// Usage:
///   showKeyboardSafeBottomSheet(
///     context: context,
///     child: YourSheetContent(),
///   );
class KeyboardSafeBottomSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Defaults to the themed surface; a hardcoded light colour here renders
  /// theme-coloured (light) text invisible in dark mode.
  final Color? backgroundColor;

  const KeyboardSafeBottomSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24.0),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }
}

/// Opens a bottom sheet that is safe with respect to the soft keyboard.
/// - Unfocuses any current text field before pushing the sheet
/// - Defers the route push to the next frame so MediaQuery.viewInsets is stable
Future<T?> showKeyboardSafeBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(24.0),
  bool isScrollControlled = true,
}) {
  // 1) Dismiss any open keyboard on the current route.
  FocusManager.instance.primaryFocus?.unfocus();

  // 2) Push the sheet on the next frame, after viewInsets have updated.
  return Future<T?>.delayed(Duration.zero, () {
    return Get.bottomSheet<T>(
      KeyboardSafeBottomSheet(
        padding: padding,
        child: child,
      ),
      isScrollControlled: isScrollControlled,
    );
  });
}
