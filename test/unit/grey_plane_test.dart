import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/logic/grey_plane.dart';

/// A greyscale picture of noise with hard black and white runs, the worst
/// case for a cubic's overshoot and for rounding.
img.Image _noise(int width, int height, int seed) {
  final random = math.Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final roll = random.nextInt(10);
      final v = roll < 3
          ? 0
          : roll < 6
          ? 255
          : random.nextInt(256);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

Uint8List _red(img.Image image) => Uint8List.fromList([
  for (var y = 0; y < image.height; y++)
    for (var x = 0; x < image.width; x++) image.getPixel(x, y).r.toInt(),
]);

void main() {
  // The sizes cover every border case: one, two and three pixels wide or
  // tall (no interior at all), odd sizes, and a tile-like size.
  const sizes = [(1, 1), (2, 3), (3, 2), (4, 4), (5, 9), (31, 17), (97, 64)];

  group('enlargedSmooth', () {
    test('gives exactly the pixels of the image package\'s cubic resize', () {
      var seed = 0;
      for (final (w, h) in sizes) {
        for (final scale in [2, 3, 4]) {
          final source = _noise(w, h, seed++);
          final expected = img.copyResize(
            source,
            width: w * scale,
            height: h * scale,
            interpolation: img.Interpolation.cubic,
          );
          final got = GreyPlane.of(source).enlargedSmooth(w * scale, h * scale);
          expect((got.width, got.height), (w * scale, h * scale));
          expect(got.pixels, _red(expected), reason: '$w x $h at ${scale}x');
        }
      }
    });

    test('the same for a size that is not a whole multiple', () {
      final source = _noise(23, 11, 99);
      final expected = img.copyResize(
        source,
        width: 61,
        height: 40,
        interpolation: img.Interpolation.cubic,
      );
      expect(
        GreyPlane.of(source).enlargedSmooth(61, 40).pixels,
        _red(expected),
      );
    });
  });

  test('enlargedSharp gives exactly the pixels of the image package\'s '
      'nearest resize', () {
    var seed = 100;
    for (final (w, h) in sizes) {
      for (final scale in [2, 3, 4]) {
        final source = _noise(w, h, seed++);
        final expected = img.copyResize(
          source,
          width: w * scale,
          height: h * scale,
          interpolation: img.Interpolation.nearest,
        );
        final got = GreyPlane.of(source).enlargedSharp(w * scale, h * scale);
        expect(got.pixels, _red(expected), reason: '$w x $h at ${scale}x');
      }
    }
  });

  test('crop gives exactly the pixels of the image package\'s crop', () {
    final source = _noise(40, 30, 7);
    final expected = img.copyCrop(source, x: 8, y: 5, width: 24, height: 18);
    final got = GreyPlane.of(source).crop(8, 5, 24, 18);
    expect((got.width, got.height), (24, 18));
    expect(got.pixels, _red(expected));
  });

  group('decode', () {
    test('a colour photo becomes its upright greyscale', () {
      final source = img.Image(width: 6, height: 4);
      img.fill(source, color: img.ColorRgb8(200, 40, 40));
      source.setPixelRgb(5, 0, 0, 255, 0);
      final bytes = Uint8List.fromList(img.encodePng(source));
      final expected = img.grayscale(img.decodePng(bytes)!);
      final plane = GreyPlane.decode(bytes)!;
      expect((plane.width, plane.height), (6, 4));
      expect(plane.pixels, _red(expected));
    });

    test('a photo with a sideways EXIF orientation is turned upright', () {
      final source = img.Image(width: 6, height: 4);
      source.exif.imageIfd.orientation = 6; // Rotate 90 degrees to view.
      final plane = GreyPlane.decode(
        Uint8List.fromList(img.encodeJpg(source)),
      )!;
      expect((plane.width, plane.height), (4, 6));
    });

    test('null for bytes that are not an image', () {
      expect(GreyPlane.decode(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  test('toPng writes a PNG any reader takes, grey as red, green and blue', () {
    final source = _noise(37, 21, 3);
    final plane = GreyPlane.of(source);
    final png = plane.toPng();
    final decoded = img.decodePng(png)!;
    expect((decoded.width, decoded.height), (37, 21));
    expect(decoded.numChannels, 3);
    // The same picture the image package's own encoder writes.
    final reference = img.decodePng(img.encodePng(source, level: 1))!;
    expect(decoded.toUint8List(), reference.toUint8List());
  });
}
