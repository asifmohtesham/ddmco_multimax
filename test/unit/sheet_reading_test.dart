import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/logic/sheet_reading.dart';

CodeBox _box(double left, double top, [double w = 80, double h = 30]) =>
    (left: left, top: top, width: w, height: h);

void main() {
  group('tileRects', () {
    test('nine tiles, 60% of each side, the last ones on the edge', () {
      final tiles = SheetReading.tileRects(1000, 500);
      expect(tiles, hasLength(9));
      expect(tiles.every((t) => t.width == 600 && t.height == 300), isTrue);
      expect(tiles.map((t) => t.x).toSet(), {0, 200, 400});
      expect(tiles.map((t) => t.y).toSet(), {0, 100, 200});
      for (final t in tiles) {
        expect(t.x + t.width, lessThanOrEqualTo(1000));
        expect(t.y + t.height, lessThanOrEqualTo(500));
      }
    });

    test('any label up to 40% of a side lies whole in some tile', () {
      const w = 1000, h = 1000, label = 400;
      final tiles = SheetReading.tileRects(w, h);
      for (var x = 0; x + label <= w; x += 37) {
        for (var y = 0; y + label <= h; y += 41) {
          final inside = tiles.any(
            (t) =>
                t.x <= x &&
                t.y <= y &&
                x + label <= t.x + t.width &&
                y + label <= t.y + t.height,
          );
          expect(inside, isTrue, reason: 'label at ($x, $y)');
        }
      }
    });
  });

  test('scaleFor enlarges small tiles up to 4x, never large ones', () {
    expect(SheetReading.scaleFor(2400), 1);
    expect(SheetReading.scaleFor(1200), 1);
    expect(SheetReading.scaleFor(600), 2);
    expect(SheetReading.scaleFor(500), 3);
    expect(SheetReading.scaleFor(100), 4);
  });

  test('boxInPhoto maps tile pixels back to the photo', () {
    final box = SheetReading.boxInPhoto(
      [(x: 40, y: 20), (x: 240, y: 20), (x: 240, y: 80), (x: 40, y: 80)],
      (x: 100, y: 50, scale: 2),
    );
    expect(box, (left: 120.0, top: 60.0, width: 100.0, height: 30.0));
    expect(
      SheetReading.boxInPhoto(const [], (x: 0, y: 0, scale: 1)),
      isNull,
    );
  });

  group('inReadingOrder', () {
    test('rows top to bottom, each row left to right', () {
      // A 3 x 2 sheet found out of order, the photo slightly tilted.
      final found = [
        FoundCode('r2c3', _box(400, 104)),
        FoundCode('r1c2', _box(200, 3)),
        FoundCode('r2c1', _box(0, 98)),
        FoundCode('r1c1', _box(0, 0)),
        FoundCode('r2c2', _box(200, 101)),
        FoundCode('r1c3', _box(400, 6)),
      ];
      expect(SheetReading.inReadingOrder(found), [
        'r1c1',
        'r1c2',
        'r1c3',
        'r2c1',
        'r2c2',
        'r2c3',
      ]);
    });

    test('a code read twice keeps its first box; codes with no box '
        'follow in the order found', () {
      final found = [
        FoundCode('b', _box(200, 0)),
        FoundCode('a', _box(0, 0)),
        FoundCode('loose'),
        FoundCode('b', _box(0, 500)),
        FoundCode('a'),
      ];
      expect(SheetReading.inReadingOrder(found), ['a', 'b', 'loose']);
    });

    test('no boxes at all keeps the order found, once each', () {
      final found = [FoundCode('x'), FoundCode('y'), FoundCode('x')];
      expect(SheetReading.inReadingOrder(found), ['x', 'y']);
    });
  });

  group('writeTiles', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('tiles'));
    tearDown(() async => dir.delete(recursive: true));

    test('enlarged tiles come smooth and sharp, nine of each', () {
      // A one-pixel black bar every other column: the thinnest bars a small
      // image can hold.
      final source = img.Image(width: 300, height: 200);
      for (var x = 0; x < 300; x++) {
        for (var y = 0; y < 200; y++) {
          final v = x.isEven ? 0 : 255;
          source.setPixelRgb(x, y, v, v, v);
        }
      }
      final photo = Uint8List.fromList(img.encodePng(source));
      final tiles = SheetReading.writeTiles(photo, dir.path, 't');
      expect(tiles, hasLength(18));
      // 180 x 120 tiles, enlarged 4x (the cap) towards a 1200 px side.
      expect(tiles.every((t) => t.scale == 4), isTrue);
      expect(tiles.map((t) => t.path).toSet(), hasLength(18));
      // Both copies of a tile sit at the same place.
      expect(tiles.map((t) => (t.x, t.y)).toSet(), hasLength(9));
      expect(tiles.map((t) => (t.x, t.y)).last, (120, 80));

      img.Image read(SheetTile t) =>
          img.decodePng(File(t.path).readAsBytesSync())!;
      final copies = tiles.where((t) => t.x == 0 && t.y == 0).toList();
      expect(copies, hasLength(2));
      for (final t in copies) {
        final tile = read(t);
        expect((tile.width, tile.height), (720, 480));
      }
      // The sharp copy repeats each pixel 4x4: every column is pure black or
      // white. The smooth copy blends neighbouring bars into greys.
      bool pure(img.Image t) => [
        for (var x = 0; x < 40; x++) t.getPixel(x, 10).r.toInt(),
      ].every((v) => v == 0 || v == 255);
      expect(copies.where((t) => pure(read(t))), hasLength(1));
    });

    test('a tile large enough is written once, not enlarged', () {
      final photo = Uint8List.fromList(
        img.encodePng(img.Image(width: 2500, height: 2100)),
      );
      final tiles = SheetReading.writeTiles(photo, dir.path, 't');
      expect(tiles, hasLength(9));
      expect(tiles.every((t) => t.scale == 1), isTrue);
    });

    test('bytes that are not an image give no tiles', () {
      final tiles = SheetReading.writeTiles(
        Uint8List.fromList([1, 2, 3]),
        dir.path,
        't',
      );
      expect(tiles, isEmpty);
      expect(dir.listSync(), isEmpty);
    });
  });
}
