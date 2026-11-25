import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/app_update_platform.dart';
import 'package:multimax/app/data/services/app_update_service.dart';
import 'package:multimax/app/modules/global_widgets/app_update_prompts.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _available = PlayUpdateInfo(
  available: true,
  flexibleAllowed: true,
  availableVersionCode: 157,
);
final _storeUrl = Uri.parse('https://apps.apple.com/app/id123456');

void main() {
  group('installer gating', () {
    for (final (installer, package, release, expected) in [
      ('com.android.vending', 'com.ddmco.multimax', true, 1),
      ('com.android.packageinstaller', 'com.ddmco.multimax', true, 0),
      (null, 'com.ddmco.multimax', true, 0),
      ('com.android.vending', 'com.ddmco.multimax.smoke', true, 0),
      ('com.android.vending', 'com.ddmco.multimax', false, 0),
    ]) {
      test(
        'Android installer=$installer package=$package release=$release',
        () async {
          final fixture = _Fixture(
            installer: installer,
            packageName: package,
            release: release,
          );
          await fixture.service.onHomeShown();
          expect(fixture.play.checks, expected);
          expect(fixture.lookups, 0);
        },
      );
    }

    for (final (installer, receipt, release, expected) in [
      ('com.apple', true, true, 1),
      ('com.apple.testflight', true, true, 0),
      ('com.apple.simulator', true, true, 0),
      (null, true, true, 0),
      ('com.apple', false, true, 0),
      ('com.apple', true, false, 0),
    ]) {
      test(
        'iOS installer=$installer receipt=$receipt release=$release',
        () async {
          final fixture = _Fixture(
            platform: TargetPlatform.iOS,
            installer: installer,
            hasReceipt: receipt,
            release: release,
          );
          await fixture.service.onHomeShown();
          expect(fixture.lookups, expected);
          expect(fixture.play.checks, 0);
        },
      );
    }

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      test('${platform.name} skips package and store APIs', () async {
        final fixture = _Fixture(platform: platform);
        await fixture.service.onHomeShown();
        await fixture.service.onAppResumed();
        expect(fixture.packageReads, 0);
      });
    }
  });

  test('starts after signed-in Home and resumes only after 12 hours', () async {
    final fixture = _Fixture()..authenticated.value = false;
    await fixture.service.onAppResumed();
    await fixture.service.onHomeShown();
    expect(fixture.play.checks, 0);

    fixture.authenticated.value = true;
    await fixture.service.onHomeShown();
    await fixture.service.onHomeShown();
    fixture.advance(const Duration(hours: 12));
    await fixture.service.onAppResumed();
    expect(fixture.play.checks, 1);

    fixture.advance(const Duration(milliseconds: 1));
    await fixture.service.onAppResumed();
    expect(fixture.play.checks, 2);
  });

  test('Play decline persists for 24 hours per version code', () async {
    final fixture = _Fixture();
    fixture.play.info = _available;
    await fixture.service.onHomeShown();
    expect(fixture.play.starts, 1);
    expect(fixture.snoozes[AppUpdateService.playDeclinesKey], {
      '157': fixture.now.millisecondsSinceEpoch,
    });

    fixture.advance(const Duration(hours: 13));
    await fixture.service.onAppResumed();
    expect(fixture.play.starts, 1);

    fixture.play.info = const PlayUpdateInfo(
      available: true,
      flexibleAllowed: true,
      availableVersionCode: 158,
    );
    await fixture.makeService().onHomeShown();
    expect(fixture.play.starts, 2);

    fixture.play.info = _available;
    await fixture.makeService().onHomeShown();
    expect(fixture.play.starts, 2);
    fixture.advance(const Duration(hours: 11));
    await fixture.makeService().onHomeShown();
    expect(fixture.play.starts, 3);
  });

  test('downloaded update is shown on Home and on an early resume', () async {
    final fixture = _Fixture();
    fixture.play.info = const PlayUpdateInfo(downloaded: true);
    await fixture.service.onHomeShown();
    expect(fixture.prompts.restartShows, 1);
    fixture.prompts.hideRestart();
    await fixture.service.onAppResumed();
    expect(fixture.prompts.restartShows, 2);
    expect(fixture.play.checks, 1);
    expect(fixture.play.starts, 0);
  });

  test('an early resume recovers a download seen in progress', () async {
    final fixture = _Fixture();
    fixture.play.info = const PlayUpdateInfo(downloadInProgress: true);
    await fixture.service.onHomeShown();
    expect(fixture.prompts.restartShows, 0);
    fixture.play.info = const PlayUpdateInfo(downloaded: true);
    await fixture.service.onAppResumed();
    expect(fixture.prompts.restartShows, 1);
    expect(fixture.play.starts, 0);
  });

  test('fresh flexible download shows the banner when ready', () async {
    final fixture = _Fixture();
    fixture.play.info = _available;
    fixture.play.start = () async => PlayUpdateResult.downloaded;
    await fixture.service.onHomeShown();
    expect(fixture.play.starts, 1);
    expect(fixture.prompts.restartShows, 1);
  });

  test(
    'Restart guards concurrent calls and recovers after a failure',
    () async {
      final fixture = _Fixture();
      final completion = Completer<void>();
      fixture.play.info = const PlayUpdateInfo(downloaded: true);
      fixture.play.complete = () => completion.future;
      await fixture.service.onHomeShown();
      final restart = fixture.prompts.restart!;
      final first = restart();
      expect(await restart(), isFalse);
      expect(fixture.play.completions, 1);

      completion.completeError(StateError('Play unavailable'));
      expect(await first, isFalse);
      fixture.play.complete = () async {};
      expect(await restart(), isTrue);
      expect(await restart(), isFalse);
      expect(fixture.play.completions, 2);
    },
  );

  test('iOS snoozes Later for 24 hours per store version', () async {
    final fixture = _Fixture(
      platform: TargetPlatform.iOS,
      installer: 'com.apple',
    );
    await fixture.service.onHomeShown();
    expect(fixture.prompts.storeShows, 1);
    expect(fixture.country, 'ae');
    expect(fixture.snoozes[AppUpdateService.appStoreSnoozesKey], {
      '2.58.10': fixture.now.millisecondsSinceEpoch,
    });

    fixture.advance(const Duration(hours: 13));
    await fixture.service.onAppResumed();
    expect(fixture.prompts.storeShows, 1);
    fixture.storeVersion = '2.58.11';
    await fixture.makeService().onHomeShown();
    expect(fixture.prompts.storeShows, 2);
    fixture.storeVersion = '2.58.10';
    fixture.advance(const Duration(hours: 11));
    await fixture.makeService().onHomeShown();
    expect(fixture.prompts.storeShows, 3);
  });

  test('iOS deferral keeps the version eligible for the next check', () async {
    final fixture = _Fixture(
      platform: TargetPlatform.iOS,
      installer: 'com.apple',
    );
    fixture.prompts.storeResult = AppStorePromptResult.deferred;
    await fixture.service.onHomeShown();
    expect(fixture.snoozes, isEmpty);
    fixture.advance(const Duration(hours: 13));
    fixture.prompts.storeResult = AppStorePromptResult.later;
    await fixture.service.onAppResumed();
    expect(fixture.prompts.storeShows, 2);
  });

  test('iOS store launch false and exceptions are handled', () async {
    final fixture = _Fixture(
      platform: TargetPlatform.iOS,
      installer: 'com.apple',
    );
    await fixture.service.onHomeShown();
    expect(await fixture.prompts.openStore!(), isFalse);
    fixture.openStore = (_) async => throw StateError('Store unavailable');
    expect(await fixture.prompts.openStore!(), isFalse);
    fixture.openStore = (url) async => url == _storeUrl;
    expect(await fixture.prompts.openStore!(), isTrue);
  });

  test(
    'only one check runs when resumes arrive while it is in flight',
    () async {
      final fixture = _Fixture();
      final pending = Completer<PlayUpdateInfo>();
      fixture.play.check = () => pending.future;
      final first = fixture.service.onHomeShown();
      await Future<void>.delayed(Duration.zero);
      fixture.advance(const Duration(hours: 13));
      await fixture.service.onAppResumed();
      expect(fixture.play.checks, 1);
      pending.complete(const PlayUpdateInfo());
      await first;
      await fixture.service.onAppResumed();
      expect(fixture.play.checks, 2);
    },
  );

  test('Play errors are swallowed and the next check can run', () async {
    final fixture = _Fixture();
    fixture.play.check = () async => throw StateError('No Play services');
    await fixture.service.onHomeShown();
    expect(fixture.prompts.restartShows, 0);
    fixture.advance(const Duration(hours: 13));
    fixture.play.check = () async => const PlayUpdateInfo(downloaded: true);
    await fixture.service.onAppResumed();
    expect(fixture.prompts.restartShows, 1);
  });

  test('Apple lookup failures never surface a dialog', () async {
    final fixture = _Fixture(
      platform: TargetPlatform.iOS,
      installer: 'com.apple',
    );
    fixture.lookupError = StateError('No network');
    await fixture.service.onHomeShown();
    expect(fixture.prompts.storeShows, 0);
  });
}

class _Fixture {
  _Fixture({
    this.platform = TargetPlatform.android,
    this.installer = 'com.android.vending',
    this.packageName = 'com.ddmco.multimax',
    this.hasReceipt = true,
    this.release = true,
  });

  final TargetPlatform platform;
  final String? installer;
  final String packageName;
  final bool hasReceipt;
  final bool release;
  final play = _Play();
  final prompts = _Prompts();
  final authenticated = true.obs;
  final snoozes = <String, Map<String, int>>{};
  DateTime now = DateTime.utc(2026, 11, 25);
  int packageReads = 0;
  int lookups = 0;
  String storeVersion = '2.58.10';
  String? country;
  Object? lookupError;
  Future<bool> Function(Uri) openStore = (_) async => false;

  late final service = makeService();

  void advance(Duration elapsed) => now = now.add(elapsed);

  AppUpdateService makeService() => AppUpdateService(
    prompts: prompts,
    isAuthenticated: authenticated,
    platform: platform,
    isReleaseBuild: release,
    play: play,
    packageInfo: () async {
      packageReads++;
      return PackageInfo(
        appName: 'Multimax',
        packageName: packageName,
        version: '2.58.9',
        buildNumber: '156',
        buildSignature: '',
        installerStore: installer,
      );
    },
    hasAppStoreReceipt: () async => hasReceipt,
    lookup: ({country}) async {
      this.country = country;
      lookups++;
      if (lookupError case final error?) throw error;
      return AppStoreRelease(version: storeVersion, url: _storeUrl);
    },
    country: () => 'AE',
    clock: () => now,
    readSnoozes: (key) => snoozes[key],
    writeSnoozes: (key, value) async => snoozes[key] = value,
    openStore: (url) => openStore(url),
  );
}

class _Play implements PlayUpdateApi {
  PlayUpdateInfo info = const PlayUpdateInfo();
  Future<PlayUpdateInfo> Function()? check;
  Future<PlayUpdateResult> Function() start = () async =>
      PlayUpdateResult.declined;
  Future<void> Function() complete = () async {};
  int checks = 0;
  int starts = 0;
  int completions = 0;

  @override
  Future<PlayUpdateInfo> checkForUpdate() async {
    checks++;
    return check == null ? info : await check!();
  }

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() {
    starts++;
    return start();
  }

  @override
  Future<void> completeFlexibleUpdate() {
    completions++;
    return complete();
  }
}

class _Prompts extends AppUpdatePrompts {
  AppStorePromptResult storeResult = AppStorePromptResult.later;
  Future<bool> Function()? restart;
  Future<bool> Function()? openStore;
  int restartShows = 0;
  int storeShows = 0;

  @override
  void showRestart(Future<bool> Function() restart) {
    if (this.restart == null) restartShows++;
    this.restart = restart;
  }

  @override
  void hideRestart() => restart = null;

  @override
  Future<AppStorePromptResult> showAppStore({
    required String installedVersion,
    required String storeVersion,
    required Future<bool> Function() openStore,
  }) async {
    this.openStore = openStore;
    storeShows++;
    return storeResult;
  }
}
