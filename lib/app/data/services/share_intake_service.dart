import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/intake_photo_cleanup.dart';
import 'package:multimax/app/data/services/native_intake.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/item/widgets/share_item_quick_actions.dart';
import 'package:multimax/app/modules/stock_sheet/items_from_photos_controller.dart';

/// Receives photos shared to Multimax and opens Item quick actions or Items
/// from Photos.
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
    Future<void> Function(String path)? openItemQuickActions,
    ItemsFromPhotosController? Function()? activeItemsFromPhotos,
    void Function(String message)? notify,
    Stream<List<String>>? drops,
    Stream<int>? dropFailures,
    Future<List<String>> Function()? strandedShare,
    Future<void> Function()? markShareHandled,
    Stream<void>? resumes,
    Future<Directory> Function()? intakeSupportDir,
    this.strandedDelay = const Duration(milliseconds: 1500),
  }) : _warmShares = warmShares ?? _pluginWarmShares(),
       _initialShare = initialShare ?? _pluginInitialShare,
       _resetShare = resetShare ?? _pluginReset,
       _isAuthenticated = isAuthenticated,
       _currentRoute = currentRoute ?? (() => Get.currentRoute),
       _openItemsFromPhotos = openItemsFromPhotos,
       _openItemQuickActions = openItemQuickActions,
       _activeItemsFromPhotos =
           activeItemsFromPhotos ?? _defaultActiveItemsFromPhotos,
       _notify =
           notify ?? ((message) => GlobalSnackbar.warning(message: message)),
       _drops = drops,
       _dropFailures = dropFailures,
       _strandedShare = strandedShare,
       _markShareHandled = markShareHandled,
       _resumes = resumes,
       _intakeSupportDir =
           intakeSupportDir ??
           (_sharingSupported ? getApplicationSupportDirectory : null);

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
  final void Function(List<String> paths)? _openItemsFromPhotos;
  final Future<void> Function(String path)? _openItemQuickActions;
  final ItemsFromPhotosController? Function() _activeItemsFromPhotos;
  final void Function(String message) _notify;
  final Stream<List<String>>? _drops;
  final Stream<int>? _dropFailures;
  final Future<List<String>> Function()? _strandedShare;
  final Future<void> Function()? _markShareHandled;
  final Stream<void>? _resumes;
  final Future<Directory> Function()? _intakeSupportDir;

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
  Future<Directory?>? _intakeDirectory;
  int _delivery = 0;
  bool _quickActionsOpen = false;

  RxBool get _signedIn =>
      _isAuthenticated ?? Get.find<AuthenticationController>().isAuthenticated;

  @override
  void onInit() {
    super.onInit();
    final supportDir = _intakeSupportDir;
    if (supportDir != null) {
      _intakeDirectory = prepareIntakePhotoDirectory(supportDir, log: _log);
    }
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
    final abandoned = pendingPhotos.toList();
    pendingPhotos.clear();
    unawaited(_deletePhotoCopies(abandoned));
    super.onClose();
  }

  /// Takes ownership of a share before waiting for navigation or sign-in.
  Future<void> deliver(List<String> paths) async {
    if (paths.isEmpty || isClosed) return;
    _resetShare();
    final delivery = ++_delivery;
    final abandoned = pendingPhotos.toList();
    pendingPhotos.clear();
    final released = _deletePhotoCopies(abandoned);

    try {
      final preparing = _intakeDirectory;
      var copies = paths;
      if (preparing != null) {
        final directory = await preparing;
        copies = directory == null
            ? const []
            : await copyIntakePhotos(paths, directory, log: _log);
        // iOS intake gives each file a unique path. On Android the plugin can
        // reuse a cache path for a later intent, so let the OS purge that cache.
        if (!kIsWeb && Platform.isIOS) unawaited(_deletePhotoCopies(paths));
      }
      if (isClosed || delivery != _delivery) {
        await _deletePhotoCopies(copies);
      } else if (copies.isEmpty) {
        _notify(
          paths.length == 1 ? "Couldn't read this photo." : dropFailedMessage,
        );
      } else {
        pendingPhotos.assignAll(copies);
        _openPending();
      }
    } finally {
      await released;
    }
  }

  Future<void> _deletePhotoCopies(List<String> paths) =>
      deleteIntakePhotoCopies(paths, supportDir: _intakeSupportDir, log: _log);

  bool _offerToActiveSheet(List<String> paths, {bool protectReview = false}) {
    if (_currentRoute() != AppRoutes.ITEMS_FROM_PHOTOS) return false;
    final sheet = _activeItemsFromPhotos();
    if (sheet == null) return false;
    if (protectReview &&
        !sheet.busy.value &&
        sheet.phase.value != ItemsFromPhotosPhase.reviewing &&
        sheet.phase.value != ItemsFromPhotosPhase.awaitingChoice) {
      return false;
    }
    if (sheet.offerShare(paths) == ShareOffer.refusedBusy) {
      if (_intakeDirectory != null) unawaited(_deletePhotoCopies(paths));
      _notify(busyMessage);
    }
    return true;
  }

  void _openPhotoSheet(List<String> paths) {
    if (!_offerToActiveSheet(paths)) {
      (_openItemsFromPhotos ?? _defaultOpen)(paths);
    }
  }

  /// A share that arrived by URL: deliver it, then tell the native side so the
  /// copy it saved is not offered again as stranded.
  void _deliverShared(List<String> paths) {
    unawaited(deliver(paths));
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
      await deliver(
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
    if (_quickActionsOpen || pendingPhotos.isEmpty || !_signedIn.value) return;
    if (_handOverRoutes.contains(_currentRoute())) return;
    final paths = pendingPhotos.toList();
    pendingPhotos.clear();
    if (paths.length > 1) {
      _openPhotoSheet(paths);
    } else if (!_offerToActiveSheet(paths, protectReview: true)) {
      _quickActionsOpen = true;
      unawaited(_showQuickActions(paths.single, _delivery));
    }
  }

  Future<void> _showQuickActions(String path, int delivery) async {
    var handedOff = false;
    try {
      final open = _openItemQuickActions;
      if (open != null) {
        await open(path);
        return;
      }

      // The route observer runs with the navigator locked.
      await Future<void>.delayed(Duration.zero);
      final showCamera =
          _sharingSupported && !await NativeIntake.instance.isRunningOnMac();
      if (isClosed) return;
      if (!_signedIn.value || _handOverRoutes.contains(_currentRoute())) {
        if (delivery == _delivery && pendingPhotos.isEmpty) {
          pendingPhotos.add(path);
        }
        return;
      }
      final context = Get.key.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      final usePhotos = await showShareItemQuickActions(
        context,
        photoPath: path,
        showCamera: showCamera,
      );
      if (usePhotos && !isClosed && _signedIn.value) {
        _openPhotoSheet([path]);
        handedOff = true;
      }
    } catch (e, st) {
      _log('opening Item quick actions failed', e, st);
    } finally {
      if (!handedOff && !pendingPhotos.contains(path)) {
        unawaited(_deletePhotoCopies([path]));
      }
      _quickActionsOpen = false;
      if (!isClosed) _openPending();
    }
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
  void _defaultOpen(List<String> paths) {
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        if (isClosed ||
            !_signedIn.value ||
            Get.toNamed<void>(AppRoutes.ITEMS_FROM_PHOTOS, arguments: paths) ==
                null) {
          await _deletePhotoCopies(paths);
        }
      }),
    );
  }

  static ItemsFromPhotosController? _defaultActiveItemsFromPhotos() =>
      Get.isRegistered<ItemsFromPhotosController>()
      ? Get.find<ItemsFromPhotosController>()
      : null;
}
