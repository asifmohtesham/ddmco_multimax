import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

abstract interface class PlayUpdateApi {
  Future<PlayUpdateInfo> checkForUpdate();
  Future<PlayUpdateResult> startFlexibleUpdate();
  Future<void> completeFlexibleUpdate();
}

class PlayUpdateInfo {
  const PlayUpdateInfo({
    this.availableVersionCode,
    this.available = false,
    this.flexibleAllowed = false,
    this.downloaded = false,
    this.downloadInProgress = false,
  });

  final int? availableVersionCode;
  final bool available;
  final bool flexibleAllowed;
  final bool downloaded;
  final bool downloadInProgress;
}

enum PlayUpdateResult { downloaded, declined, failed }

class GooglePlayUpdateApi implements PlayUpdateApi {
  const GooglePlayUpdateApi();

  @override
  Future<PlayUpdateInfo> checkForUpdate() async {
    final info = await InAppUpdate.checkForUpdate();
    return PlayUpdateInfo(
      availableVersionCode: info.availableVersionCode,
      available: info.updateAvailability == UpdateAvailability.updateAvailable,
      flexibleAllowed: info.flexibleUpdateAllowed,
      downloaded: info.installStatus == InstallStatus.downloaded,
      downloadInProgress: switch (info.installStatus) {
        InstallStatus.pending ||
        InstallStatus.downloading ||
        InstallStatus.installing => true,
        _ => false,
      },
    );
  }

  @override
  Future<PlayUpdateResult> startFlexibleUpdate() async {
    return switch (await InAppUpdate.startFlexibleUpdate()) {
      // The Android plugin reports success when the download completes.
      AppUpdateResult.success => PlayUpdateResult.downloaded,
      AppUpdateResult.userDeniedUpdate => PlayUpdateResult.declined,
      AppUpdateResult.inAppUpdateFailed => PlayUpdateResult.failed,
    };
  }

  @override
  Future<void> completeFlexibleUpdate() {
    // The plugin calls Play's completeUpdate without replying to Dart. Play
    // restarts the app on success, so time out to release the UI if it stays up.
    return InAppUpdate.completeFlexibleUpdate().timeout(
      const Duration(seconds: 10),
    );
  }
}

class AppStoreRelease {
  const AppStoreRelease({required this.version, required this.url});

  final String version;
  final Uri url;
}

class AppStoreLookup {
  AppStoreLookup({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );

  final Dio _dio;

  Future<AppStoreRelease?> lookup({String? country}) async {
    try {
      final region = country == null || country.isEmpty
          ? null
          : country.toLowerCase();
      var data = await _fetch(region);
      if (data['resultCount'] == 0 && region != null) {
        data = await _fetch(null);
      }
      if (data['resultCount'] == 0) return null;

      final results = data['results'];
      if (results is! List || results.isEmpty) {
        throw const FormatException('Missing App Store results');
      }
      final result = results.first;
      if (result is! Map<String, Object?>) {
        throw const FormatException('Invalid App Store result');
      }
      final version = result['version'];
      final storeUrl = result['trackViewUrl'];
      final url = storeUrl is String ? Uri.tryParse(storeUrl) : null;
      if (version is! String ||
          url == null ||
          url.host.isEmpty ||
          !(url.isScheme('https') || url.isScheme('http'))) {
        throw const FormatException('Missing App Store version or link');
      }
      return AppStoreRelease(version: version, url: url);
    } on FormatException catch (error) {
      debugPrint('App Store update lookup failed: ${error.message}');
      return null;
    }
  }

  Future<Map<String, Object?>> _fetch(String? country) async {
    final uri = Uri.https('itunes.apple.com', '/lookup', {
      'bundleId': 'com.ddmco.multimax',
      if (country != null) 'country': country,
    });
    final response = await _dio.getUri<String>(
      uri,
      options: Options(responseType: ResponseType.plain),
    );
    final data = jsonDecode(response.data ?? '');
    final count = data is Map<String, Object?> ? data['resultCount'] : null;
    if (data is! Map<String, Object?> || count is! int || count < 0) {
      throw const FormatException('Invalid App Store result count');
    }
    return data;
  }
}

final _dotSeparatedVersion = RegExp(r'^[0-9]+(?:\.[0-9]+)*$');

bool isNewerAppVersion(String candidate, String installed) {
  final candidateParts = _versionParts(candidate);
  final installedParts = _versionParts(installed);
  if (candidateParts == null || installedParts == null) return false;

  for (
    var index = 0;
    index < candidateParts.length || index < installedParts.length;
    index++
  ) {
    final candidatePart = index < candidateParts.length
        ? candidateParts[index]
        : 0;
    final installedPart = index < installedParts.length
        ? installedParts[index]
        : 0;
    if (candidatePart != installedPart) return candidatePart > installedPart;
  }
  return false;
}

List<int>? _versionParts(String version) {
  if (!_dotSeparatedVersion.hasMatch(version)) return null;
  final parts = <int>[];
  for (final part in version.split('.')) {
    final number = int.tryParse(part);
    if (number == null) return null;
    parts.add(number);
  }
  return parts;
}
