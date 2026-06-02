import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A context-safe navigation utility that wraps [Navigator] using
/// [Get.context] for resolution. Use this instead of [Get.back] to
/// avoid interference with GetX's snackbar and overlay machinery.
abstract class AppNavigator {
  static NavigatorState get _nav {
    final ctx = Get.context;
    if (ctx == null) throw StateError('AppNavigator: no active context');
    return Navigator.of(ctx);
  }

  /// Pops the current route if the navigator stack allows it.
  /// Silently no-ops when there is no context or the stack is at root.
  static void pop<T>([T? result]) {
    final ctx = Get.context;
    if (ctx == null) return;
    final nav = Navigator.of(ctx);
    if (nav.canPop()) nav.pop(result);
  }

  /// Pushes a named route onto the navigator stack.
  static Future<T?> pushNamed<T>(String routeName, {Object? arguments}) {
    return _nav.pushNamed<T>(routeName, arguments: arguments);
  }

  /// Pushes a named route and removes all previous routes matching [predicate].
  /// Useful for post-login or post-logout navigation resets.
  static Future<T?> pushNamedAndRemoveUntil<T>(
    String routeName,
    RoutePredicate predicate, {
    Object? arguments,
  }) {
    return _nav.pushNamedAndRemoveUntil<T>(
      routeName,
      predicate,
      arguments: arguments,
    );
  }
}
