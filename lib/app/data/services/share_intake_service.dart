import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';

/// Receives photos shared to Multimax from the gallery and opens the stock
/// sheet for them.
///
/// The photos are held in [pendingPhotos] until the app can show the screen:
/// signed in, and past the splash and login routes. Both of those finish with
/// `Get.offAllNamed`, which would wipe a stock sheet opened on top of them, so
/// a cold start or a share while signed out waits for that hand-over to HOME
/// (reported through [onRouteChanged] from `GetMaterialApp.routingCallback`).
class ShareIntakeService extends GetxService {
  ShareIntakeService({
    Stream<List<String>>? warmShares,
    Future<List<String>> Function()? initialShare,
    void Function()? resetShare,
    RxBool? isAuthenticated,
    String Function()? currentRoute,
    void Function(List<String> paths)? openStockSheet,
    StockSheetController? Function()? activeStockSheet,
    void Function(String message)? notify,
  }) : _warmShares = warmShares ?? _pluginWarmShares(),
       _initialShare = initialShare ?? _pluginInitialShare,
       _resetShare = resetShare ?? _pluginReset,
       _isAuthenticated = isAuthenticated,
       _currentRoute = currentRoute ?? (() => Get.currentRoute),
       _openStockSheet = openStockSheet ?? _defaultOpen,
       _activeStockSheet = activeStockSheet ?? _defaultActiveStockSheet,
       _notify =
           notify ?? ((message) => GlobalSnackbar.warning(message: message));

  static const String busyMessage = 'A stock sheet is already being made.';

  /// Routes that are replaced wholesale once the session is known.
  static const Set<String> _handOverRoutes = {
    '',
    '/',
    AppRoutes.SPLASH,
    AppRoutes.LOGIN,
  };

  final Stream<List<String>> _warmShares;
  final Future<List<String>> Function() _initialShare;
  final void Function() _resetShare;
  final RxBool? _isAuthenticated;
  final String Function() _currentRoute;
  final void Function(List<String> paths) _openStockSheet;
  final StockSheetController? Function() _activeStockSheet;
  final void Function(String message) _notify;

  /// Shared photos waiting for sign-in or for the app to reach HOME.
  final pendingPhotos = <String>[].obs;

  StreamSubscription<List<String>>? _warmSubscription;
  Worker? _authWorker;

  RxBool get _signedIn =>
      _isAuthenticated ?? Get.find<AuthenticationController>().isAuthenticated;

  @override
  void onInit() {
    super.onInit();
    _warmSubscription = _warmShares.listen(
      deliver,
      onError: (Object e, StackTrace st) => _log('share stream failed', e, st),
    );
    _authWorker = ever<bool>(_signedIn, (_) => _openPending());
    unawaited(_takeInitialShare());
  }

  @override
  void onClose() {
    _warmSubscription?.cancel();
    _authWorker?.dispose();
    super.onClose();
  }

  /// Hands a share to the stock sheet, now or once the app is ready.
  void deliver(List<String> paths) {
    if (paths.isEmpty) return;
    _resetShare();

    final sheet = _currentRoute() == AppRoutes.STOCK_SHEET
        ? _activeStockSheet()
        : null;
    if (sheet != null) {
      // A share held as pending is the screen's to ask about.
      if (sheet.offerShare(paths) == ShareOffer.refusedBusy) {
        _notify(busyMessage);
      }
      return;
    }

    pendingPhotos.assignAll(paths);
    _openPending();
  }

  /// Called on every route change; opens the sheet once the app reaches a
  /// signed-in screen.
  void onRouteChanged() => _openPending();

  void _openPending() {
    if (pendingPhotos.isEmpty || !_signedIn.value) return;
    if (_handOverRoutes.contains(_currentRoute())) return;
    final paths = pendingPhotos.toList();
    pendingPhotos.clear();
    _openStockSheet(paths);
  }

  Future<void> _takeInitialShare() async {
    try {
      deliver(await _initialShare());
    } catch (e, st) {
      _log('initial share failed', e, st);
    }
  }

  void _log(String what, Object e, StackTrace st) {
    if (kDebugMode) debugPrint('ShareIntakeService: $what: $e\n$st');
  }

  // --- Defaults: receive_sharing_intent and GetX navigation ---------------

  static bool get _sharingSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Stream<List<String>> _pluginWarmShares() {
    if (!_sharingSupported) return const Stream.empty();
    return ReceiveSharingIntent.instance.getMediaStream().map(_imagePaths);
  }

  static Future<List<String>> _pluginInitialShare() async {
    if (!_sharingSupported) return const [];
    return _imagePaths(await ReceiveSharingIntent.instance.getInitialMedia());
  }

  static void _pluginReset() {
    if (!_sharingSupported) return;
    unawaited(ReceiveSharingIntent.instance.reset());
  }

  static List<String> _imagePaths(List<SharedMediaFile> files) => [
    for (final f in files)
      if (f.type == SharedMediaType.image) f.path,
  ];

  /// Deferred a tick: [onRouteChanged] runs inside a navigator observer, where
  /// a push would hit the navigator's lock.
  static void _defaultOpen(List<String> paths) {
    Future<void>.delayed(Duration.zero, () {
      Get.toNamed<void>(AppRoutes.STOCK_SHEET, arguments: paths);
    });
  }

  static StockSheetController? _defaultActiveStockSheet() =>
      Get.isRegistered<StockSheetController>()
      ? Get.find<StockSheetController>()
      : null;
}
