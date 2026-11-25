import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:path/path.dart' as p;

/// Opens the same persisted session in the app and in its background workers.
PersistCookieJar createSessionCookieJar(
  String directory, {
  Future<List<int>> Function(File file)? readFile,
}) =>
    _SessionCookieJar(_SessionCookieStorage(directory, readFile));

class _SessionCookieJar extends PersistCookieJar {
  _SessionCookieJar(Storage storage)
      : super(ignoreExpires: true, storage: storage);

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    try {
      return await super.loadForRequest(uri);
    } on FileSystemException {
      rethrow;
    } catch (_) {
      // PersistCookieJar deletes malformed host content before rethrowing its
      // parse error. Load again so other cookies (such as domain cookies) can
      // still be used and a missing SID is visible on this attempt.
      return super.loadForRequest(uri);
    }
  }
}

class _SessionCookieStorage extends FileStorage {
  _SessionCookieStorage(String super.dir, this._readFile);

  final Future<List<int>> Function(File file)? _readFile;

  late String _cookieDirectory;

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    // Match FileStorage's existing on-disk layout.
    _cookieDirectory = p.join(
      dir!.replaceAll('\\', '/'),
      'ie${ignoreExpires ? 1 : 0}_ps${persistSession ? 1 : 0}',
    );
    await super.init(persistSession, ignoreExpires);
  }

  @override
  Future<String?> read(String key) async {
    // Opening directly distinguishes filesystem failures from an absent file.
    final file = File(p.join(_cookieDirectory, key));
    final List<int> bytes;
    try {
      bytes = await (_readFile?.call(file) ?? file.readAsBytes());
    } on PathNotFoundException {
      return null;
    }

    // Decode separately so invalid UTF-8 is treated as malformed content.
    try {
      return utf8.decode(bytes);
    } on FormatException {
      await delete(key);
      return null;
    }
  }
}
