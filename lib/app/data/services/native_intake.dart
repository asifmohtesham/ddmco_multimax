import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app-side end of the iOS intake channel.
///
/// The native side reports whether the iPhone/iPad app is running on a Mac,
/// hands over photos dropped onto the window and shares stranded by the share
/// extension, and lists the folders whose copies must be cleaned up.
///
/// Every call is guarded to iOS and reads a channel error as "nothing", so
/// callers never need their own platform checks or error handling.
class NativeIntake {
  NativeIntake({MethodChannel? channel, bool Function()? isIOS})
    : _channel = channel ?? const MethodChannel(channelName),
      _isIOS = isIOS ?? _defaultIsIOS {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String channelName = 'com.ddmco.multimax/intake';

  /// The one instance shared by the app, so there is a single channel handler.
  static final NativeIntake instance = NativeIntake();

  static bool _defaultIsIOS() => !kIsWeb && Platform.isIOS;

  final MethodChannel _channel;
  final bool Function() _isIOS;
  final StreamController<List<String>> _drops =
      StreamController<List<String>>.broadcast();

  bool? _onMac;

  /// Paths of photos dropped onto the window (Mac only).
  Stream<List<String>> get drops => _drops.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'dropped') {
      final paths = _paths(call.arguments);
      if (paths.isNotEmpty) _drops.add(paths);
    }
    return null;
  }

  static List<String> _paths(Object? raw) =>
      raw is List ? raw.whereType<String>().toList() : const <String>[];

  /// Whether the iOS app is running on a Mac. Cached after the first answer;
  /// `false` off iOS or on any error.
  Future<bool> isRunningOnMac() async {
    final cached = _onMac;
    if (cached != null) return cached;
    if (!_isIOS()) return false;
    try {
      return _onMac =
          await _channel.invokeMethod<bool>('isRunningOnMac') ?? false;
    } on PlatformException {
      return _onMac = false;
    } on MissingPluginException {
      return _onMac = false;
    }
  }

  /// Absolute paths of a share the extension left behind, or `[]`.
  Future<List<String>> takeStrandedShare() => _list('takeStrandedShare');

  /// Tells the native side the stranded share has been dealt with.
  Future<void> markShareHandled() async {
    if (!_isIOS()) return;
    try {
      await _channel.invokeMethod<void>('markShareHandled');
    } on PlatformException {
      // Nothing to mark.
    } on MissingPluginException {
      // Nothing to mark.
    }
  }

  /// Absolute paths of the folders whose copies must be cleaned up, or `[]`.
  Future<List<String>> sharedFolders() => _list('sharedFolders');

  Future<List<String>> _list(String method) async {
    if (!_isIOS()) return const <String>[];
    try {
      return _paths(await _channel.invokeMethod<Object?>(method));
    } on PlatformException {
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }
}
