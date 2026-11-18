import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_fingerprint.dart';

void main() {
  test('same bytes under two names give the same fingerprint', () async {
    final dir = await Directory.systemTemp.createTemp('photo_fingerprint');
    addTearDown(() => dir.delete(recursive: true));
    final a = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    final b = File('${dir.path}/b.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    final c = File('${dir.path}/c.jpg')..writeAsBytesSync([9, 9, 9]);

    final fp = await fingerprintPhotos([a.path, b.path, c.path]);

    expect(fp[a.path], fp[b.path]);
    expect(fp[a.path], isNot(fp[c.path]));
    expect(fp[a.path], hasLength(64));
  });

  test('a missing file gets a unique unreadable fingerprint', () async {
    final fp = await fingerprintPhotos(['/no/such.jpg']);
    expect(fp['/no/such.jpg'], 'unreadable:/no/such.jpg');
  });
}
