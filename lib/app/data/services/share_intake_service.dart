import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/native_intake.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/stock_sheet/items_from_photos_controller.dart';

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
    void Function(List<String> paths)? openItemsFromPhotos,
    ItemsFromPhotosController? Function()? activeItemsFromPhotos,
    void Function(String message)? notify,
    Stream<List<String>>? drops,
    Stream<int>? dropFailures,
    Future<List<String>> Function()? strandedShare,
    Future<void> Function()? markShareHandled,
    Stream<void>? resumes,
    this.strandedDelay = const Duration(milliseconds: 1500),
  }) : _warmShares = warmShares ?? _pluginWarmShares(),
       _initialShare = initialShare ?? _pluginInitialShare,
       _resetShare = resetShare ?? _pluginReset,
       _isAuthenticated = isAuthenticated,
       _currentRoute = currentRoute ?? (() => Get.currentRoute),
       _openItemsFromPhotos = openItemsFromPhotos ?? _defaultOpen,
       _activeItemsFromPhotos = activeItemsFromPhotos ?? _defaultActiveItemsFromPhotos,
       _notify =
           notify ?? ((message) => GlobalSnackbar.warning(message: message)),
       _drops = drops,
       _dropFailures = dropFailures,
       _strandedShare = strandedShare,
       _markShareHandled = markShareHandled,
       _resumes = resumes;

  static const String busyMessage =
      'Items from Photos is already generating a file.';

  /// A drop onto the window where no photo could be copied.
  static const String dropFailedMessage = "Couldn't read these photos.";

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
  final void Function(List<String> paths) _openItemsFromPhotos;
  final ItemsFromPhotosController? Function() _activeItemsFromPhotos;
  final void Function(String message) _notify;
  final Stream<List<String>>? _drops;
  final Stream<int>? _dropFailures;
  final Future<List<String>> Function()? _strandedShare;
  final Future<void> Function()? _markShareHandled;
  final Stream<void>? _resumes;

  /// How long after the app resumes to wait for a share's URL to arrive
  /// before looking for a stranded share. A URL-delivered share marks itself
  /// handled in that time, so it is not delivered twice.
  final Duration strandedDelay;

  /// Shared photos waiting for sign-in or for the app to reach HOME.
  final pendingPhotos = <String>[].obs;

  StreamSubscription<List<String>>? _warmSubscription;
  StreamSubscription<List<String>>? _dropSubscription;
  StreamSubscription<int>? _dropFailureSubscription;
  StreamSubscription<void>? _resumeSubscription;
  StreamController<void>? _lifecycleResumes;
  AppLifecycleListener? _lifecycleListener;
  Timer? _strandedTimer;
  Worker? _authWorker;

  RxBool get _signedIn =>
      _isAuthenticated ?? Get.find<AuthenticationController>().isAuthenticated;

  @override
  void onInit() {
    super.onInit();
    _warmSubscription = _warmShares.listen(
      _deliverShared,
      onError: (Object e, StackTrace st) => _log('share stream failed', e, st),
    );
    // The drops stream is broadcast, so it must be listened to from the start.
    _dropSubscription = (_drops ?? NativeIntake.instance.drops).listen(
      deliver,
      onError: (Object e, StackTrace st) => _log('drop stream failed', e, st),
    );
    _dropFailureSubscription =
        (_dropFailures ?? NativeIntake.instance.dropFailures).listen(
          (_) => _notify(dropFailedMessage),
          onError: (Object e, StackTrace st) =>
              _log('drop failure stream failed', e, st),
        );
    _resumeSubscription = (_resumes ?? _lifecycleResumeStream()).listen(
      (_) => _scheduleStrandedCheck(),
    );
    _authWorker = ever<bool>(_signedIn, (_) => _openPending());
    unawaited(_takeInitialShare());
    // A cold launch whose share URL never arrives leaves the share stranded.
    _scheduleStrandedCheck();
  }

  @override
  void onClose() {
    _warmSubscription?.cancel();
    _dropSubscription?.cancel();
    _dropFailureSubscription?.cancel();
    _resumeSubscription?.cancel();
    _strandedTimer?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleResumes?.close();
    _authWorker?.dispose();
    super.onClose();
  }

  /// Hands a share to the stock sheet, now or once the app is ready.
  void deliver(List<String> paths) {
    if (paths.isEmpty) return;
    _resetShare();

    final sheet = _currentRoute() == AppRoutes.ITEMS_FROM_PHOTOS
        ? _activeItemsFromPhotos()
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

  /// A share that arrived by URL: deliver it, then tell the native side so the
  /// copy it saved is not offered again as stranded.
  void _deliverShared(List<String> paths) {
    deliver(paths);
    if (paths.isNotEmpty) unawaited(_markHandled());
  }

  Future<void> _markHandled() async {
    try {
      await (_markShareHandled ?? NativeIntake.instance.markShareHandled)();
    } catch (e, st) {
      _log('marking the share handled failed', e, st);
    }
  }

  Stream<void> _lifecycleResumeStream() {
    final controller = _lifecycleResumes = StreamController<void>.broadcast();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => controller.add(null),
    );
    return controller.stream;
  }

  void _scheduleStrandedCheck() {
    _strandedTimer?.cancel();
    _strandedTimer = Timer(strandedDelay, () => unawaited(_takeStranded()));
  }

  Future<void> _takeStranded() async {
    try {
      deliver(
        await (_strandedShare ?? NativeIntake.instance.takeStrandedShare)(),
      );
    } catch (e, st) {
      _log('stranded share failed', e, st);
    }
  }

  /// Called on every route change; opens the sheet once the app reaches a
  /// signed-in screen.
  void onRouteChanged() => _openPending();

  void _openPending() {
    if (pendingPhotos.isEmpty || !_signedIn.value) return;
    if (_handOverRoutes.contains(_currentRoute())) return;
    final paths = pendingPhotos.toList();
    pendingPhotos.clear();
    _openItemsFromPhotos(paths);
  }

  Future<void> _takeInitialShare() async {
    try {
      _deliverShared(await _initialShare());
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
      Get.toNamed<void>(AppRoutes.ITEMS_FROM_PHOTOS, arguments: paths);
    });
  }

  static ItemsFromPhotosController? _defaultActiveItemsFromPhotos() =>
      Get.isRegistered<ItemsFromPhotosController>()
      ? Get.find<ItemsFromPhotosController>()
      : null;
}
