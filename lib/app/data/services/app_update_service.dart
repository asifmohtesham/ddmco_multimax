import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:multimax/app/data/services/app_update_platform.dart';
import 'package:multimax/app/modules/global_widgets/app_update_prompts.dart';

class AppUpdateService extends GetxService with WidgetsBindingObserver {
  AppUpdateService({
    required this.prompts,
    required RxBool isAuthenticated,
    TargetPlatform? platform,
    bool isReleaseBuild = kReleaseMode,
    PlayUpdateApi play = const GooglePlayUpdateApi(),
    Future<AppStoreRelease?> Function({String? country})? lookup,
    Future<PackageInfo> Function()? packageInfo,
    Future<bool> Function()? hasAppStoreReceipt,
    String? Function()? country,
    DateTime Function()? clock,
    Object? Function(String key)? readSnoozes,
    Future<void> Function(String key, Map<String, int> value)? writeSnoozes,
    Future<bool> Function(Uri url)? openStore,
  }) : _authenticated = isAuthenticated,
       _platform = platform ?? (kIsWeb ? null : defaultTargetPlatform),
       _isReleaseBuild = isReleaseBuild,
       _play = play,
       _lookup = lookup ?? AppStoreLookup().lookup,
       _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       _hasAppStoreReceipt = hasAppStoreReceipt ?? _readAppStoreReceipt,
       _country =
           country ?? (() => PlatformDispatcher.instance.locale.countryCode),
       _clock = clock ?? DateTime.now,
       _readSnoozes = readSnoozes ?? ((key) => GetStorage().read<Object>(key)),
       _writeSnoozes =
           writeSnoozes ?? ((key, value) => GetStorage().write(key, value)),
       _openStore =
           openStore ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  static const playDeclinesKey = 'app_update_play_declines';
  static const appStoreSnoozesKey = 'app_update_app_store_snoozes';
  static const _resumeInterval = Duration(hours: 12);
  static const _snoozeInterval = Duration(hours: 24);
  static const _packageName = 'com.ddmco.multimax';

  final AppUpdatePrompts prompts;
  final RxBool _authenticated;
  final TargetPlatform? _platform;
  final bool _isReleaseBuild;
  final PlayUpdateApi _play;
  final Future<AppStoreRelease?> Function({String? country}) _lookup;
  final Future<PackageInfo> Function() _packageInfo;
  final Future<bool> Function() _hasAppStoreReceipt;
  final String? Function() _country;
  final DateTime Function() _clock;
  final Object? Function(String) _readSnoozes;
  final Future<void> Function(String, Map<String, int>) _writeSnoozes;
  final Future<bool> Function(Uri) _openStore;

  Worker? _authWorker;
  DateTime? _lastCheck;
  bool _homeShown = false;
  bool _foreground = true;
  bool _checking = false;
  bool _restarting = false;
  bool _playDownloaded = false;
  bool _playDownloadInProgress = false;

  bool get _supported =>
      _isReleaseBuild &&
      (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  bool get _canPrompt => _homeShown && _authenticated.value && _foreground;

  static Future<bool> _readAppStoreReceipt() async {
    const channel = MethodChannel('com.ddmco.multimax/app_update');
    return await channel.invokeMethod<bool>('hasAppStoreReceipt') ?? false;
  }

  @override
  void onInit() {
    super.onInit();
    if (!_supported) return;
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    binding.addObserver(this);
    _authWorker = ever(_authenticated, (signedIn) {
      if (signedIn) return;
      _homeShown = false;
      _lastCheck = null;
      prompts.hideRestart();
    });
  }

  @override
  void onClose() {
    if (_supported) WidgetsBinding.instance.removeObserver(this);
    _authWorker?.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(onAppResumed());
  }

  Future<void> onHomeShown() async {
    if (!_supported || !_authenticated.value || _homeShown) return;
    _homeShown = true;
    await _check();
  }

  Future<void> onAppResumed() async {
    if (!_canPrompt) return;
    try {
      _showRestartIfPending();
      final lastCheck = _lastCheck;
      if (lastCheck == null ||
          _clock().difference(lastCheck) > _resumeInterval) {
        await _check();
      } else if (_playDownloadInProgress) {
        // Recover a download first seen in progress after process recreation.
        // This status refresh cannot start a new update or reset the offer timer.
        await _check(downloadOnly: true);
      }
    } catch (error) {
      _log('resume', error);
    }
  }

  Future<void> _check({bool downloadOnly = false}) async {
    if (!_canPrompt || _checking || _restarting) return;
    _checking = true;
    try {
      if (!downloadOnly) _lastCheck = _clock();
      final package = await _packageInfo();
      if (!_canPrompt || package.packageName != _packageName) return;
      if (_platform == TargetPlatform.android &&
          package.installerStore == 'com.android.vending') {
        await _checkPlay(downloadOnly: downloadOnly);
      } else if (_platform == TargetPlatform.iOS &&
          package.installerStore == 'com.apple' &&
          await _hasAppStoreReceipt() &&
          _canPrompt) {
        await _checkAppStore(package.version);
      }
    } catch (error) {
      _log('check', error);
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkPlay({required bool downloadOnly}) async {
    final update = await _play.checkForUpdate();
    _playDownloadInProgress = update.downloadInProgress;
    final wasDownloaded = _playDownloaded;
    _playDownloaded = update.downloaded;
    if (_playDownloaded) {
      _showRestartIfPending();
      return;
    }
    if (wasDownloaded) prompts.hideRestart();

    final version = update.availableVersionCode?.toString();
    if (downloadOnly ||
        !_canPrompt ||
        _playDownloadInProgress ||
        !update.available ||
        !update.flexibleAllowed ||
        version == null ||
        _isSnoozed(playDeclinesKey, version)) {
      return;
    }

    switch (await _play.startFlexibleUpdate()) {
      case PlayUpdateResult.downloaded:
        _playDownloaded = true;
        _showRestartIfPending();
      case PlayUpdateResult.declined:
        await _snooze(playDeclinesKey, version);
      case PlayUpdateResult.failed:
        debugPrint('App update: Play flexible update failed.');
    }
  }

  void _showRestartIfPending() {
    if (_playDownloaded && _canPrompt && !_restarting) {
      prompts.showRestart(_restart);
    }
  }

  Future<bool> _restart() async {
    if (_restarting || !_playDownloaded || !_canPrompt) return false;
    _restarting = true;
    try {
      await _play.completeFlexibleUpdate();
      _playDownloaded = false;
      return true;
    } catch (error) {
      _log('restart', error);
      return false;
    } finally {
      _restarting = false;
    }
  }

  Future<void> _checkAppStore(String installedVersion) async {
    final release = await _lookup(country: _country()?.toLowerCase());
    if (!_canPrompt ||
        release == null ||
        !isNewerAppVersion(release.version, installedVersion) ||
        _isSnoozed(appStoreSnoozesKey, release.version)) {
      return;
    }
    final result = await prompts.showAppStore(
      installedVersion: installedVersion,
      storeVersion: release.version,
      openStore: () => _launchStore(release.url),
    );
    if (result == AppStorePromptResult.later) {
      await _snooze(appStoreSnoozesKey, release.version);
    }
  }

  Future<bool> _launchStore(Uri url) async {
    try {
      if (await _openStore(url)) return true;
      debugPrint('App update: could not open the App Store.');
    } catch (error) {
      _log('open App Store', error);
    }
    return false;
  }

  Map<String, int> _snoozes(String key) {
    final raw = _readSnoozes(key);
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is int)
          entry.key as String: entry.value as int,
    };
  }

  bool _isSnoozed(String key, String version) {
    final millis = _snoozes(key)[version];
    return millis != null &&
        _clock().millisecondsSinceEpoch - millis <
            _snoozeInterval.inMilliseconds;
  }

  Future<void> _snooze(String key, String version) async {
    final now = _clock().millisecondsSinceEpoch;
    final values = _snoozes(key)
      ..removeWhere(
        (_, millis) => now - millis >= _snoozeInterval.inMilliseconds,
      )
      ..[version] = now;
    await _writeSnoozes(key, values);
  }

  static void _log(String operation, Object error) {
    debugPrint('App update $operation failed: $error');
  }
}
