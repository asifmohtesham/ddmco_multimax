import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/logic/thumbnail_maker.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('thumb_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('shrinks the long side to 480 and keeps the aspect ratio',
      (tester) async {
    await tester.runAsync(() async {
      final src = img.Image(width: 3000, height: 1500);
      img.fill(src, color: img.ColorRgb8(200, 30, 30));
      final file = File('${dir.path}/big.png')
        ..writeAsBytesSync(img.encodePng(src));

      final bytes = await ThumbnailMaker.make(file.path);

      expect(bytes, isNotNull);
      final out = img.decodeJpg(bytes!);
      expect(out, isNotNull);
      expect(out!.width, 480);
      expect(out.height, 240);
    });
  });

  testWidgets('returns null for a file that is not an image', (tester) async {
    await tester.runAsync(() async {
      final rnd = Random(1);
      final file = File('${dir.path}/junk.jpg')
        ..writeAsBytesSync(List.generate(2048, (_) => rnd.nextInt(256)));

      expect(await ThumbnailMaker.make(file.path), isNull);
    });
  });
}
