import 'package:ddmco_multimax/app/core/utils/app_notification.dart';
import 'package:flutter/services.dart';

/// A backwards-compatible façade over [AppNotification].
///
/// All existing call sites use named parameters `title` and `message`.
/// This class preserves that API exactly so no call site needs to change
/// as part of this commit.  The underlying implementation now uses
/// [ScaffoldMessenger] via [AppNotification], completely removing the
/// dependency on [Get.snackbar] and its [LateInitializationError]-prone
/// [SnackbarController].
///
/// Scheduled for deletion in Commit 9 once all call sites are migrated
/// to call [AppNotification] directly.
class GlobalSnackbar {
  static void success({
    String title = 'Success',
    required String message,
  }) {
    HapticFeedback.lightImpact();
    AppNotification.success(_format(title, message));
  }

  static void error({
    String title = 'Error',
    required String message,
  }) {
    HapticFeedback.lightImpact();
    AppNotification.error(_format(title, message));
  }

  static void warning({
    String title = 'Warning',
    required String message,
  }) {
    AppNotification.warning(_format(title, message));
  }

  static void info({
    String title = 'Info',
    required String message,
  }) {
    AppNotification.info(_format(title, message));
  }

  /// Combines [title] and [message] into a single display string.
  /// When the caller passes the default title (e.g. 'Error') the output
  /// is just the message to avoid redundancy.  Custom titles are prepended.
  static String _format(String title, String message) {
    final defaultTitles = {'Success', 'Error', 'Warning', 'Info'};
    if (defaultTitles.contains(title)) return message;
    return '$title: $message';
  }
}
