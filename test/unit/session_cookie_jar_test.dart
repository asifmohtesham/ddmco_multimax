import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/session_cookie_jar.dart';
import 'package:path/path.dart' as p;

void main() {
  final server = Uri.parse('https://erp.example.com');
  const index = '.index';
  const domains = '.domains';
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('multimax_cookie_jar_');
    addTearDown(() => directory.delete(recursive: true));
  });

  File cookieFile(String key) => File(p.join(directory.path, 'ie1_ps1', key));

  Future<void> saveSession({bool domainCookie = false}) async {
    final sid = Cookie('sid', 'saved');
    if (domainCookie) sid.domain = server.host;
    await createSessionCookieJar(directory.path).saveFromResponse(server, [sid]);
  }

  for (final key in [index, domains, server.host]) {
    test('deletes malformed $key and can load without a session', () async {
      await saveSession(domainCookie: key == domains);
      final badFile = await cookieFile(key).writeAsString('{');
      final jar = createSessionCookieJar(directory.path);

      expect(await jar.loadForRequest(server), isEmpty);
      expect(await badFile.exists(), isFalse);
      expect(await jar.loadForRequest(server), isEmpty);
    });

    test('ignores empty $key and can load without a session', () async {
      await saveSession(domainCookie: key == domains);
      await cookieFile(key).writeAsString('');
      final jar = createSessionCookieJar(directory.path);

      expect(await jar.loadForRequest(server), isEmpty);
      expect(await jar.loadForRequest(server), isEmpty);
    });

    test('propagates a read error for $key and retries it later', () async {
      await saveSession(domainCookie: key == domains);
      final files = [
        cookieFile(index),
        cookieFile(key == domains ? domains : server.host),
      ];
      final originals =
          await Future.wait(files.map((file) => file.readAsBytes()));
      final unreadableFile = cookieFile(key);
      final readError =
          FileSystemException('Temporarily locked', unreadableFile.path);
      var locked = true;
      var reads = 0;
      final jar = createSessionCookieJar(
        directory.path,
        readFile: (file) {
          if (p.basename(file.path) == key) {
            reads++;
            if (locked) throw readError;
          }
          return file.readAsBytes();
        },
      );

      await expectLater(jar.loadForRequest(server), throwsA(same(readError)));
      expect(reads, 1);
      expect(
        await Future.wait(files.map((file) => file.readAsBytes())),
        originals,
      );

      locked = false;
      final cookies = await jar.loadForRequest(server);
      expect(cookies.single.name, 'sid');
      expect(cookies.single.value, 'saved');
      expect(reads, 2);
    });
  }

  test('deletes a host file with invalid UTF-8 and returns no session', () async {
    await saveSession();
    final badFile = await cookieFile(server.host).writeAsBytes([0xff]);
    final jar = createSessionCookieJar(directory.path);

    expect(await jar.loadForRequest(server), isEmpty);
    expect(await badFile.exists(), isFalse);
  });

  test('deletes a host file with an invalid cookie entry', () async {
    await saveSession();
    final badFile =
        await cookieFile(server.host).writeAsString('{"/":{"sid":"sid=x"}}');
    final jar = createSessionCookieJar(directory.path);

    expect(await jar.loadForRequest(server), isEmpty);
    expect(await badFile.exists(), isFalse);
  });

  test('keeps valid host cookies when domain cookies are malformed', () async {
    await saveSession();
    final badFile = await cookieFile(domains).writeAsString('{');
    final jar = createSessionCookieJar(directory.path);

    expect((await jar.loadForRequest(server)).single.value, 'saved');
    expect(await badFile.exists(), isFalse);
  });
}
