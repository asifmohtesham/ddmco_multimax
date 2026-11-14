import 'dart:async';

/// How a logout finished.
enum LogoutOutcome {
  /// The server ended the session and the device was cleared.
  serverConfirmed,

  /// The server could not be reached in time; only the device was cleared.
  /// The server-side session lingers until it expires on its own.
  localOnly,
}

/// Local-first logout: the device session is ALWAYS cleared; telling the
/// server is best-effort and bounded by [serverTimeout].
///
/// Handhelds are shared and warehouse WiFi is patchy — a dead network must
/// never leave a user signed in. [onServerTimeout] lets the caller cancel the
/// in-flight request so a late response cannot write cookies back after
/// [clearLocal] has run.
///
/// Throws only if [clearLocal] throws.
Future<LogoutOutcome> localFirstLogout({
  required Future<void> Function() serverLogout,
  required Future<void> Function() clearLocal,
  Duration serverTimeout = const Duration(seconds: 5),
  void Function()? onServerTimeout,
}) async {
  var outcome = LogoutOutcome.serverConfirmed;
  try {
    await serverLogout().timeout(serverTimeout);
  } on TimeoutException {
    onServerTimeout?.call();
    outcome = LogoutOutcome.localOnly;
  } catch (_) {
    outcome = LogoutOutcome.localOnly;
  }
  await clearLocal();
  return outcome;
}
