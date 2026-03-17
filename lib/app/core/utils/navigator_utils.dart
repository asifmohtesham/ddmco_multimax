import 'package:flutter/material.dart';

/// Thin wrapper around [Navigator.of(context).pop()] intended for use inside
/// [Get.bottomSheet] and [Get.dialog] builders.
///
/// **Why not [Get.back()]?**
/// [GetNavigation.back()] unconditionally calls [Get.closeCurrentSnackbar()]
/// before popping the route. If a [SnackbarController] is in the GetX queue
/// but its `late AnimationController _controller` has not yet been
/// initialised (i.e. before the snackbar enters the Flutter Overlay),
/// [close()] throws [LateInitializationError] and crashes the app.
///
/// [Navigator.of(context).pop()] pops only the navigator route and never
/// interacts with the snackbar queue, making it unconditionally safe.
class NavigatorUtils {
  NavigatorUtils._();

  /// Safely dismisses the nearest sheet or dialog.
  /// Must be called with a [BuildContext] that is *inside* the sheet tree
  /// (e.g. from a [Builder] wrapping the sheet content).
  static void popSheet(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
