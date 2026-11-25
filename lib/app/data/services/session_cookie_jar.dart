import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:path/path.dart' as p;

/// Opens the same persisted session in the app and in its background workers.
PersistCookieJar createSessionCookieJar(String directory) => PersistCookieJar(
      ignoreExpires: true,
      storage: _SessionCookieStorage(directory),
      deleteHostCookiesWhenLoadFailed: false,
    );

class _SessionCookieStorage extends FileStorage {
  _SessionCookieStorage(String super.dir);

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
    try {
      final contents = await file.readAsString();
      if (contents.isEmpty) throw const FormatException('Empty cookie file');
      return contents;
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    // The jar calls delete on these keys after a parse failure. Reject that
    // recovery so the caller can retry. Explicit sign-out uses deleteAll.
    if (key == '.index' || key == '.domains') {
      throw const FormatException('Unreadable cookie metadata');
    }
    await super.delete(key);
  }
}
